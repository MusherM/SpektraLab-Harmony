#include <napi/native_api.h>
#include <spektrafilm/spk_engine.h>
#include <cstdint>
#include <array>
#include <atomic>
#include <fcntl.h>
#include <unistd.h>
#include <cerrno>
#include <system_error>
#include "raw_decode.hpp"
#include "raw_display.hpp"
#include "render_quality.hpp"
#include <algorithm>
#include <cmath>
#include <cstring>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>
#include <mutex>
#include <future>
#include <unordered_map>
#include <sys/stat.h>
#include <chrono>
#ifdef __ARM_NEON
#include <arm_neon.h>
#endif
#ifdef _OPENMP
#include <omp.h>
#endif

// Called from the editor worker with tightly packed, opaque sRGB RGBA8888 pixels.
namespace {
// N-API workers share this library; serialize engine and cache access.
std::mutex resourcesMutex;
struct Operation {
    std::atomic<bool> cancelled{false};
    std::mutex mutex;
    spk_session* session = nullptr;
};
struct Cancelled : std::runtime_error {
    Cancelled() : std::runtime_error("Operation cancelled") {}
};
std::mutex operationsMutex;
std::unordered_map<uint32_t, std::shared_ptr<Operation>> operations;
uint32_t nextOperation = 0;

std::shared_ptr<Operation> operationFor(napi_env env, napi_value value) {
    uint32_t id = 0;
    if (napi_get_value_uint32(env, value, &id) != napi_ok || id == 0) return {};
    std::lock_guard<std::mutex> lock(operationsMutex);
    const auto found = operations.find(id);
    return found == operations.end() ? nullptr : found->second;
}

void checkCancelled(const std::shared_ptr<Operation>& operation) {
    if (operation && operation->cancelled.load()) throw Cancelled();
}

class RenderRegistration {
public:
    RenderRegistration(const std::shared_ptr<Operation>& operation, spk_session* session) : operation_(operation) {
        if (!operation_) return;
        std::lock_guard<std::mutex> lock(operation_->mutex);
        checkCancelled(operation_);
        operation_->session = session;
    }
    ~RenderRegistration() {
        if (!operation_) return;
        std::lock_guard<std::mutex> lock(operation_->mutex);
        operation_->session = nullptr;
    }
private:
    std::shared_ptr<Operation> operation_;
};

using Engine = std::unique_ptr<spk_engine, decltype(&spk_engine_destroy)>;
using Session = std::unique_ptr<spk_session, decltype(&spk_session_release)>;
Engine cachedEngine(nullptr, spk_engine_destroy);
std::string enginePath;

// Cached preview session so paper/glare edits reuse the developed negative (spk_reprint)
// and film/exposure edits skip re-uploading source pixels and re-metering auto-exposure.
struct PreviewSessionCache {
    Session session{nullptr, spk_session_release};
    uint32_t width = 0;
    uint32_t height = 0;
    bool linear = false;
    bool fastMode = false;
    uint64_t inputHash = 0;
    std::unordered_map<std::string, std::string> lastFields;
    void reset() {
        session.reset();
        width = height = 0;
        linear = false;
        fastMode = false;
        inputHash = 0;
        lastFields.clear();
    }
} previewCache;

std::mutex rawCacheMutex;
std::shared_ptr<spk::io::DecodedRaw> cachedRaw;
struct stat rawIdentity{};
std::string rawWarning;
bool cachedRawHalfSize = false;
int cachedRawUserQual = 3;
uint64_t rawCacheEpoch = 0;

struct RawDecodeOutcome {
    std::shared_ptr<spk::io::DecodedRaw> raw;
    std::string warning;
    std::string error;
    bool cancelled = false;
};

struct InFlightRaw {
    struct stat identity{};
    bool halfSize = false;
    int userQual = 3;
    uint64_t epoch = 0;
    std::shared_future<RawDecodeOutcome> future;
};
std::shared_ptr<InFlightRaw> inFlightRaw;

constexpr size_t rawCacheLimit = 512u * 1024 * 1024;
constexpr uint64_t previewSessionMaxPixels = 4500000u; // ~2048x2048 preview ceiling
constexpr double kPreviewLongEdge = 1600.0;

spk_engine* acquireEngine(const std::string& path) {
    if (!cachedEngine || enginePath != path) {
        previewCache.reset();
        cachedEngine.reset();
        cachedEngine.reset(spk_engine_create(path.c_str(), nullptr));
        if (!cachedEngine) throw std::runtime_error(spk_last_error(nullptr));
        enginePath = path;
    }
    return cachedEngine.get();
}

bool sameSource(const struct stat& a, const struct stat& b) {
    return a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_size == b.st_size &&
        a.st_mtim.tv_sec == b.st_mtim.tv_sec && a.st_mtim.tv_nsec == b.st_mtim.tv_nsec &&
        a.st_ctim.tv_sec == b.st_ctim.tv_sec && a.st_ctim.tv_nsec == b.st_ctim.tv_nsec;
}

uint64_t hashInputBuffer(const void* data, size_t bytes) {
    const auto* p = static_cast<const uint8_t*>(data);
    uint64_t h = 14695981039346656037ull ^ bytes;
    const size_t step = std::max<size_t>(1, bytes / 4096);
    for (size_t i = 0; i < bytes; i += step) {
        h ^= p[i];
        h *= 1099511628211ull;
    }
    if (bytes >= 8) {
        uint64_t tail = 0;
        std::memcpy(&tail, p + bytes - 8, 8);
        h ^= tail;
        h *= 1099511628211ull;
    }
    return h;
}

// Parse flat JSON object {"key": value, ...} produced by Index.ets params() into
// raw key -> raw JSON value token map so we can send minimal deltas to spk_set_params.
bool parseFlatJsonObject(const std::string& json, std::unordered_map<std::string, std::string>& out) {
    out.clear();
    size_t i = 0, n = json.size();
    auto skipWs = [&]() { while (i < n && (json[i] == ' ' || json[i] == '\t' || json[i] == '\r' || json[i] == '\n')) ++i; };
    skipWs();
    if (i >= n || json[i] != '{') return false;
    ++i;
    for (;;) {
        skipWs();
        if (i >= n) return false;
        if (json[i] == '}') return true;
        if (json[i] != '"') return false;
        ++i;
        size_t kStart = i;
        while (i < n && json[i] != '"') {
            if (json[i] == '\\') ++i;
            ++i;
        }
        if (i >= n) return false;
        std::string key = json.substr(kStart, i - kStart);
        ++i;
        skipWs();
        if (i >= n || json[i] != ':') return false;
        ++i;
        skipWs();
        if (i >= n) return false;
        size_t vStart = i;
        if (json[i] == '"') {
            ++i;
            while (i < n && json[i] != '"') {
                if (json[i] == '\\') ++i;
                ++i;
            }
            if (i >= n) return false;
            ++i;
        } else if (json[i] == '{' || json[i] == '[') {
            return false; // nested object not expected; fall back to fresh open
        } else {
            while (i < n && json[i] != ',' && json[i] != '}' &&
                   json[i] != ' ' && json[i] != '\t' && json[i] != '\r' && json[i] != '\n') ++i;
        }
        out.emplace(std::move(key), json.substr(vStart, i - vStart));
        skipWs();
        if (i < n && json[i] == ',') { ++i; continue; }
        if (i < n && json[i] == '}') return true;
        return false;
    }
}

std::string buildDeltaJson(const std::unordered_map<std::string, std::string>& prev,
                           const std::unordered_map<std::string, std::string>& next) {
    std::string delta = "{";
    bool first = true;
    for (const auto& [k, v] : next) {
        if (k == "product_defaults") continue;
        auto it = prev.find(k);
        if (it != prev.end() && it->second == v) continue;
        if (!first) delta += ',';
        first = false;
        delta += '"'; delta += k; delta += "\":"; delta += v;
    }
    delta += '}';
    return delta;
}

std::string readText(napi_env env, napi_value value) {
    size_t size = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &size) != napi_ok)
        throw std::runtime_error("Expected a string");
    std::vector<char> data(size + 1);
    if (napi_get_value_string_utf8(env, value, data.data(), data.size(), &size) != napi_ok)
        throw std::runtime_error("Cannot read string");
    return {data.data(), size};
}

struct Output {
    spk_result value{};
    ~Output() { spk_result_free(&value); }
};

// Bit-exact ARM64 NEON + OpenMP conversion of uint16 RGBA16 -> uint8 RGBA8:
// For all v in [0, 65535], ((v + 128) - ((v + 128) >> 8)) >> 8 == (v + 128) / 257.
void convertRgba16ToRgba8(const spk_result& frame, uint8_t* destination,
                          const std::shared_ptr<Operation>& operation) {
    const uint32_t w = frame.width;
    const uint32_t h = frame.height;
    const size_t stride4 = size_t(frame.row_stride_px) * 4u;
    const size_t rowLen = size_t(w) * 4u;
    std::atomic<bool> wasCancelled{false};
#pragma omp parallel for schedule(static) if(size_t(w) * h >= 262144u)
    for (size_t y = 0; y < h; ++y) {
        if ((y & 31u) == 0u && operation && operation->cancelled.load(std::memory_order_relaxed)) {
            wasCancelled.store(true, std::memory_order_relaxed);
            continue;
        }
        if (wasCancelled.load(std::memory_order_relaxed)) continue;
        const uint16_t* row = frame.rgba16 + y * stride4;
        uint8_t* out = destination + y * rowLen;
        size_t k = 0;
#ifdef __ARM_NEON
        const uint32x4_t c128 = vdupq_n_u32(128u);
        for (; k + 16 <= rowLen; k += 16) {
            uint16x8_t a = vld1q_u16(row + k);
            uint16x8_t b = vld1q_u16(row + k + 8);
            // Use exact 32-bit x = v + 128; (x - (x >> 8)) >> 8 to avoid uint16 overflow at 65535+128
            uint32x4_t a0 = vaddq_u32(vmovl_u16(vget_low_u16(a)), c128);
            uint32x4_t a1 = vaddq_u32(vmovl_u16(vget_high_u16(a)), c128);
            uint32x4_t b0 = vaddq_u32(vmovl_u16(vget_low_u16(b)), c128);
            uint32x4_t b1 = vaddq_u32(vmovl_u16(vget_high_u16(b)), c128);
            a0 = vshrq_n_u32(vsubq_u32(a0, vshrq_n_u32(a0, 8)), 8);
            a1 = vshrq_n_u32(vsubq_u32(a1, vshrq_n_u32(a1, 8)), 8);
            b0 = vshrq_n_u32(vsubq_u32(b0, vshrq_n_u32(b0, 8)), 8);
            b1 = vshrq_n_u32(vsubq_u32(b1, vshrq_n_u32(b1, 8)), 8);
            uint16x8_t na = vcombine_u16(vmovn_u32(a0), vmovn_u32(a1));
            uint16x8_t nb = vcombine_u16(vmovn_u32(b0), vmovn_u32(b1));
            vst1q_u8(out + k, vcombine_u8(vmovn_u16(na), vmovn_u16(nb)));
        }
#endif
        for (; k < rowLen; ++k) out[k] = static_cast<uint8_t>((row[k] + 128u) / 257u);
    }
    if (wasCancelled.load()) throw Cancelled();
}

napi_value finishRender(napi_env env, spk_engine* engine, spk_session* session, uint32_t w, uint32_t h,
    const std::shared_ptr<Operation>& operation, bool useReprint = false) {
    checkCancelled(operation);
    if (!session) throw std::runtime_error(spk_last_error(engine));
    Output result;
    spk_status status;
    {
        RenderRegistration registration(operation, session);
        status = useReprint ? spk_reprint(session, "full", &result.value)
                            : spk_render(session, "full", &result.value);
    }
    checkCancelled(operation);
    if (status == SPK_ERR_CANCELLED) throw Cancelled();
    if (status != SPK_OK)
        throw std::runtime_error(spk_last_error(engine));
    const auto& frame = result.value;
    if (!frame.rgba16 || frame.width != w || frame.height != h || frame.row_stride_px < w)
        throw std::runtime_error("Unexpected render dimensions");
    void* destination = nullptr;
    napi_value buffer{};
    if (napi_create_arraybuffer(env, size_t(w) * h * 4, &destination, &buffer) != napi_ok)
        throw std::runtime_error("Cannot allocate output pixels");
    convertRgba16ToRgba8(frame, static_cast<uint8_t*>(destination), operation);
    return buffer;
}

const std::array<float, 256>& u8_to_f32_lut() {
    static const std::array<float, 256> lut = [] {
        std::array<float, 256> t{};
        for (size_t i = 0; i < 256; ++i) t[i] = static_cast<float>(i) / 255.0f;
        return t;
    }();
    return lut;
}

template<bool Linear>
napi_value render(napi_env env, napi_callback_info info) {
    std::lock_guard<std::mutex> lock(resourcesMutex);
    try {
        napi_value args[7]{};
        size_t count = 7;
        if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok || count < 5)
            throw std::runtime_error("Expected resources, pixels, width, height and parameter JSON");
        const auto operation = count >= 6 ? operationFor(env, args[5]) : nullptr;
        bool fastMode = false;
        if (count >= 7) {
            bool parsedFast = false;
            if (napi_get_value_bool(env, args[6], &parsedFast) == napi_ok) fastMode = parsedFast;
        }
        harmony_perf::ScopedRenderQuality qualityScope(
            fastMode ? harmony_perf::fast_quality() : harmony_perf::exact_quality());
        checkCancelled(operation);
        const auto path = readText(env, args[0]);
        const auto params = readText(env, args[4]);
        void* raw = nullptr;
        size_t bytes = 0;
        uint32_t w = 0, h = 0;
        if (napi_get_arraybuffer_info(env, args[1], &raw, &bytes) != napi_ok || !raw ||
            napi_get_value_uint32(env, args[2], &w) != napi_ok ||
            napi_get_value_uint32(env, args[3], &h) != napi_ok || !w || !h ||
            bytes % (Linear ? 12 : 4) || bytes / (Linear ? 12 : 4) != uint64_t(w) * h)
            throw std::runtime_error("Invalid RGBA image");
        auto engine = acquireEngine(path);

        const bool isPreview = uint64_t(w) * h <= previewSessionMaxPixels;
        if (isPreview) {
            const uint64_t hash = hashInputBuffer(raw, bytes);
            std::unordered_map<std::string, std::string> fields;
            const bool parsed = parseFlatJsonObject(params, fields);
            if (parsed && previewCache.session && previewCache.width == w && previewCache.height == h &&
                previewCache.linear == Linear && previewCache.fastMode == fastMode &&
                previewCache.inputHash == hash) {
                const std::string delta = buildDeltaJson(previewCache.lastFields, fields);
                if (delta == "{}" || spk_set_params(previewCache.session.get(), delta.c_str(), nullptr) == SPK_OK) {
                    previewCache.lastFields = std::move(fields);
                    return finishRender(env, engine, previewCache.session.get(), w, h, operation, /*useReprint=*/true);
                }
                previewCache.reset();
            }
            previewCache.reset();
            Session session(nullptr, spk_session_release);
            if constexpr (Linear) {
                const spk_image input{static_cast<float*>(raw), w, h, 3};
                session.reset(spk_open(engine, &input, params.c_str(), nullptr));
            } else {
                const auto* pixels = static_cast<const uint8_t*>(raw);
                const size_t npx = bytes / 4;
                std::vector<float> rgb(npx * 3);
                const auto& lut = u8_to_f32_lut();
                float* dst = rgb.data();
#pragma omp parallel for schedule(static) if(npx >= 262144u)
                for (size_t i = 0; i < npx; ++i) {
                    dst[i * 3 + 0] = lut[pixels[i * 4 + 0]];
                    dst[i * 3 + 1] = lut[pixels[i * 4 + 1]];
                    dst[i * 3 + 2] = lut[pixels[i * 4 + 2]];
                }
                checkCancelled(operation);
                const spk_image input{rgb.data(), w, h, 3};
                session.reset(spk_open(engine, &input, params.c_str(), nullptr));
            }
            if (!session) throw std::runtime_error(spk_last_error(engine));
            napi_value out = finishRender(env, engine, session.get(), w, h, operation, /*useReprint=*/false);
            if (parsed) {
                previewCache.session = std::move(session);
                previewCache.width = w;
                previewCache.height = h;
                previewCache.linear = Linear;
                previewCache.fastMode = fastMode;
                previewCache.inputHash = hash;
                previewCache.lastFields = std::move(fields);
            }
            return out;
        }

        // Full-resolution one-shot export: drop preview session first to free GPU memory.
        previewCache.reset();
        Session session(nullptr, spk_session_release);
        if constexpr (Linear) {
            const spk_image input{static_cast<float*>(raw), w, h, 3};
            session.reset(spk_open(engine, &input, params.c_str(), nullptr));
        } else {
            const auto* pixels = static_cast<const uint8_t*>(raw);
            const size_t npx = bytes / 4;
            std::vector<float> rgb(npx * 3);
            const auto& lut = u8_to_f32_lut();
            float* dst = rgb.data();
            std::atomic<bool> wasCancelled{false};
#pragma omp parallel for schedule(static) if(npx >= 262144u)
            for (size_t i = 0; i < npx; ++i) {
                if ((i & 65535u) == 0u && operation && operation->cancelled.load(std::memory_order_relaxed)) {
                    wasCancelled.store(true, std::memory_order_relaxed);
                    continue;
                }
                if (wasCancelled.load(std::memory_order_relaxed)) continue;
                dst[i * 3 + 0] = lut[pixels[i * 4 + 0]];
                dst[i * 3 + 1] = lut[pixels[i * 4 + 1]];
                dst[i * 3 + 2] = lut[pixels[i * 4 + 2]];
            }
            if (wasCancelled.load()) throw Cancelled();
            const spk_image input{rgb.data(), w, h, 3};
            session.reset(spk_open(engine, &input, params.c_str(), nullptr));
        }
        return finishRender(env, engine, session.get(), w, h, operation, /*useReprint=*/false);
    } catch (const Cancelled& error) {
        napi_throw_error(env, nullptr, error.what());
        return nullptr;
    } catch (const std::exception& error) {
        previewCache.reset();
        cachedEngine.reset();
        napi_throw_error(env, nullptr, error.what());
        return nullptr;
    }
}

std::vector<uint8_t> readFdToMemory(int source, size_t expectedSize, const std::shared_ptr<Operation>& operation) {
    std::vector<uint8_t> data;
    if (expectedSize > 0 && expectedSize <= 512u * 1024 * 1024) data.reserve(expectedSize);
    std::array<uint8_t, 262144> buffer;
    off_t offset = 0;
    for (;;) {
        checkCancelled(operation);
        ssize_t count = pread(source, buffer.data(), buffer.size(), offset);
        if (count < 0 && errno == EINTR) continue;
        if (count < 0) throw std::system_error(errno, std::generic_category(), "RAW read");
        if (count == 0) break;
        data.insert(data.end(), buffer.data(), buffer.data() + count);
        offset += count;
    }
    if (data.empty()) throw std::runtime_error("RAW source is empty");
    return data;
}

std::shared_ptr<spk::io::DecodedRaw> readRaw(int fd, const std::string& /*cacheDir*/,
    const std::shared_ptr<Operation>& operation, bool halfSize, int userQual, std::string* warning = nullptr) {
    for (;;) {
        checkCancelled(operation);
        struct stat identity{};
        if (fstat(fd, &identity) != 0) throw std::system_error(errno, std::generic_category(), "RAW identity");

        std::shared_future<RawDecodeOutcome> waitFuture;
        std::shared_ptr<std::promise<RawDecodeOutcome>> ownPromise;
        std::shared_ptr<InFlightRaw> ownFlight;
        uint64_t startEpoch = 0;

        {
            std::lock_guard<std::mutex> lock(rawCacheMutex);
            if (cachedRaw && sameSource(identity, rawIdentity)) {
                // Reuse cached full-res decode if it matches requested quality, or reuse any cached
                // decode when only a half-size preview is requested.
                const bool exactMatch = (cachedRawHalfSize == halfSize && cachedRawUserQual == userQual);
                const bool fullSatisfiesHalf = (halfSize && !cachedRawHalfSize);
                if (exactMatch || fullSatisfiesHalf) {
                    if (warning) *warning = rawWarning;
                    return cachedRaw;
                }
            }
            if (inFlightRaw && sameSource(identity, inFlightRaw->identity) &&
                inFlightRaw->halfSize == halfSize && inFlightRaw->userQual == userQual) {
                waitFuture = inFlightRaw->future;
            } else {
                startEpoch = rawCacheEpoch;
                ownPromise = std::make_shared<std::promise<RawDecodeOutcome>>();
                ownFlight = std::make_shared<InFlightRaw>();
                ownFlight->identity = identity;
                ownFlight->halfSize = halfSize;
                ownFlight->userQual = userQual;
                ownFlight->epoch = startEpoch;
                ownFlight->future = ownPromise->get_future().share();
                inFlightRaw = ownFlight;
            }
        }

        if (waitFuture.valid()) {
            const RawDecodeOutcome outcome = waitFuture.get();
            checkCancelled(operation);
            if (outcome.raw) {
                if (warning) *warning = outcome.warning;
                return outcome.raw;
            }
            if (outcome.cancelled) {
                // Another waiter/predecode was cancelled; retry under our own operation.
                continue;
            }
            throw std::runtime_error(outcome.error.empty() ? "RAW decode failed" : outcome.error);
        }

        RawDecodeOutcome outcome;
        try {
            // Read RAW directly into memory and pass to LibRaw::open_buffer() (avoids flash temp copy).
            auto fileBytes = readFdToMemory(fd, identity.st_size > 0 ? size_t(identity.st_size) : 0, operation);
            checkCancelled(operation);
            std::string decodedWarning;
            harmony_raw::DecodeOptions options;
            options.user_qual = userQual;
            options.half_size = halfSize;
            auto raw = std::make_shared<spk::io::DecodedRaw>(
                harmony_raw::decode_buffer(fileBytes.data(), fileBytes.size(), options, &decodedWarning));
            std::vector<uint8_t>().swap(fileBytes);
            struct stat after{};
            if (fstat(fd, &after) != 0 || !sameSource(identity, after))
                throw std::runtime_error("RAW source changed while decoding");
            {
                std::lock_guard<std::mutex> lock(rawCacheMutex);
                if (inFlightRaw == ownFlight) inFlightRaw.reset();
                if (rawCacheEpoch == startEpoch && raw->rgb.size() <= rawCacheLimit / sizeof(float)) {
                    const bool preserveFull = cachedRaw && sameSource(identity, rawIdentity) &&
                                              !cachedRawHalfSize && halfSize;
                    if (!preserveFull) {
                        cachedRaw = raw;
                        rawIdentity = identity;
                        rawWarning = decodedWarning;
                        cachedRawHalfSize = halfSize;
                        cachedRawUserQual = userQual;
                    }
                }
            }
            outcome.raw = raw;
            outcome.warning = std::move(decodedWarning);
            ownPromise->set_value(outcome);
            checkCancelled(operation);
            if (warning) *warning = outcome.warning;
            return outcome.raw;
        } catch (const Cancelled&) {
            {
                std::lock_guard<std::mutex> lock(rawCacheMutex);
                if (inFlightRaw == ownFlight) inFlightRaw.reset();
            }
            outcome.cancelled = true;
            ownPromise->set_value(outcome);
            throw;
        } catch (const std::exception& err) {
            {
                std::lock_guard<std::mutex> lock(rawCacheMutex);
                if (inFlightRaw == ownFlight) inFlightRaw.reset();
            }
            outcome.error = err.what();
            ownPromise->set_value(outcome);
            throw;
        }
    }
}

napi_value predecodeRaw(napi_env env, napi_callback_info info) {
    napi_value result{};
    bool ok = false;
    try {
        napi_value args[4]{};
        size_t count = 4;
        int fd = -1;
        if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) == napi_ok &&
            count >= 2 && napi_get_value_int32(env, args[0], &fd) == napi_ok && fd >= 0) {
            const auto cacheDir = readText(env, args[1]);
            const auto operation = count >= 3 ? operationFor(env, args[2]) : nullptr;
            bool fastMode = false;
            if (count >= 4) {
                bool parsedFast = false;
                if (napi_get_value_bool(env, args[3], &parsedFast) == napi_ok) fastMode = parsedFast;
            }
            const int rawQual = fastMode ? 2 : 3;
            auto raw = readRaw(fd, cacheDir, operation, /*halfSize=*/false, rawQual);
            ok = static_cast<bool>(raw);
        }
    } catch (const Cancelled&) {
        ok = false;
    } catch (const std::exception&) {
        ok = false;
    }
    napi_get_boolean(env, ok, &result);
    return result;
}

napi_value renderRaw(napi_env env, napi_callback_info info) {
    try {
        napi_value args[6]{};
        size_t count = 6;
        int fd = -1;
        if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok ||
            count < 4 || napi_get_value_int32(env, args[1], &fd) != napi_ok || fd < 0)
            throw std::runtime_error("Expected resources, RAW file descriptor and parameter JSON");
        const auto operation = count >= 5 ? operationFor(env, args[4]) : nullptr;
        bool fastMode = false;
        if (count >= 6) {
            bool parsedFast = false;
            if (napi_get_value_bool(env, args[5], &parsedFast) == napi_ok) fastMode = parsedFast;
        }
        checkCancelled(operation);
        const auto path = readText(env, args[0]);
        const auto params = readText(env, args[2]);
        const auto cacheDir = readText(env, args[3]);
        const int rawQual = fastMode ? 2 : 3;
        // Decode or join any in-flight background pre-decode outside resourcesMutex.
        auto raw = readRaw(fd, cacheDir, operation, /*halfSize=*/false, rawQual);
        checkCancelled(operation);

        std::lock_guard<std::mutex> lock(resourcesMutex);
        try {
            harmony_perf::ScopedRenderQuality qualityScope(
                fastMode ? harmony_perf::fast_quality() : harmony_perf::exact_quality());
            auto engine = acquireEngine(path);
            previewCache.reset();
            Session session(nullptr, spk_session_release);
            const uint32_t width = raw->width;
            const uint32_t height = raw->height;
            {
                const spk_image input{raw->rgb.data(), width, height, 3};
                session.reset(spk_open(engine, &input, params.c_str(), nullptr));
            }
            raw.reset();
            napi_value result{}, w{}, h{};
            auto pixels = finishRender(env, engine, session.get(), width, height, operation, /*useReprint=*/false);
            if (napi_create_object(env, &result) != napi_ok ||
                napi_create_uint32(env, width, &w) != napi_ok || napi_create_uint32(env, height, &h) != napi_ok ||
                napi_set_named_property(env, result, "pixels", pixels) != napi_ok ||
                napi_set_named_property(env, result, "width", w) != napi_ok ||
                napi_set_named_property(env, result, "height", h) != napi_ok)
                throw std::runtime_error("Cannot return RAW print");
            return result;
        } catch (const Cancelled&) {
            throw;
        } catch (const std::exception&) {
            previewCache.reset();
            cachedEngine.reset();
            throw;
        }
    } catch (const Cancelled& error) {
        napi_throw_error(env, nullptr, error.what());
        return nullptr;
    } catch (const std::exception& error) {
        napi_throw_error(env, nullptr, error.what());
        return nullptr;
    }
}

// The caller holds the picker file descriptor open until decoding returns.
napi_value decodeRaw(napi_env env, napi_callback_info info) {
    try {
        napi_value args[3]{};
        size_t count = 3;
        int fd = -1;
        if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok ||
            count < 2 || napi_get_value_int32(env, args[0], &fd) != napi_ok || fd < 0)
            throw std::runtime_error("Expected RAW file descriptor");
        const auto operation = count == 3 ? operationFor(env, args[2]) : nullptr;
        std::string warning;
        const auto decodeStarted = std::chrono::steady_clock::now();
        // Fast half-size decode for preview import (full-res is pre-decoded in background / lazily on export).
        auto raw = readRaw(fd, readText(env, args[1]), operation, /*halfSize=*/true, /*userQual=*/3, &warning);
        const auto displayStarted = std::chrono::steady_clock::now();
        const double displayGain = harmony_raw::display_gain(raw->rgb);
        std::string rawInfo = raw->metadata.libraw_version + " | " +
            raw->metadata.make + " " + raw->metadata.model + " | " + raw->metadata.decoder_name +
            " | " + std::to_string(raw->width) + "x" + std::to_string(raw->height) +
            (warning.empty() ? " | WB=as-shot" : " | WB=daylight fallback");
        const double scale = std::min(1.0, kPreviewLongEdge / std::max(raw->width, raw->height));
        const auto width = std::max(1L, std::lround(raw->width * scale));
        const auto height = std::max(1L, std::lround(raw->height * scale));
        napi_value buffer{}, display{}, result{}, w{}, h{}, infoText{}, warningText{};
        void* destination{};
        void* displayDestination{};
        if (napi_create_arraybuffer(env, width * height * 3 * sizeof(float), &destination, &buffer) != napi_ok)
            throw std::runtime_error("Cannot allocate RAW preview");
        if (napi_create_arraybuffer(env, width * height * 4, &displayDestination, &display) != napi_ok)
            throw std::runtime_error("Cannot allocate RAW display");
        auto* outBase = static_cast<float*>(destination);
        auto* rgbaBase = static_cast<uint8_t*>(displayDestination);
        const float* srcBase = raw->rgb.data();
        const size_t rawW = raw->width;
        const size_t rawH = raw->height;
        std::atomic<bool> wasCancelled{false};
#pragma omp parallel for schedule(static)
        for (long y = 0; y < height; ++y) {
            if ((y & 31L) == 0 && operation && operation->cancelled.load(std::memory_order_relaxed)) {
                wasCancelled.store(true, std::memory_order_relaxed);
                continue;
            }
            if (wasCancelled.load(std::memory_order_relaxed)) continue;
            const size_t sy = (2 * size_t(y) + 1) * rawH / (2 * size_t(height));
            const float* srcRow = srcBase + sy * rawW * 3;
            float* out = outBase + size_t(y) * size_t(width) * 3;
            uint8_t* rgba = rgbaBase + size_t(y) * size_t(width) * 4;
            for (long x = 0; x < width; ++x) {
                const size_t sx = (2 * size_t(x) + 1) * rawW / (2 * size_t(width));
                const float* px = srcRow + sx * 3;
                out[0] = px[0]; out[1] = px[1]; out[2] = px[2];
                harmony_raw::display_pixel(out, rgba, displayGain);
                out += 3;
                rgba += 4;
            }
        }
        if (wasCancelled.load()) throw Cancelled();
        rawInfo += " | display_ev=" + std::to_string(std::log2(displayGain)) +
            " | decode_ms=" + std::to_string(std::chrono::duration<double, std::milli>(displayStarted - decodeStarted).count()) +
            " | display_ms=" + std::to_string(std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - displayStarted).count()) +
            " | workers=" + std::to_string(spk::io::raw_worker_limit());
        if (napi_create_object(env, &result) != napi_ok ||
            napi_create_uint32(env, width, &w) != napi_ok || napi_create_uint32(env, height, &h) != napi_ok ||
            napi_create_string_utf8(env, rawInfo.c_str(), rawInfo.size(), &infoText) != napi_ok ||
            napi_set_named_property(env, result, "rawInfo", infoText) != napi_ok ||
            napi_create_string_utf8(env, warning.c_str(), warning.size(), &warningText) != napi_ok ||
            napi_set_named_property(env, result, "warning", warningText) != napi_ok ||
            napi_set_named_property(env, result, "pixels", buffer) != napi_ok ||
            napi_set_named_property(env, result, "displayPixels", display) != napi_ok ||
            napi_set_named_property(env, result, "width", w) != napi_ok ||
            napi_set_named_property(env, result, "height", h) != napi_ok)
            throw std::runtime_error("Cannot return RAW preview");
        return result;
    } catch (const Cancelled& error) {
        napi_throw_error(env, nullptr, error.what());
        return nullptr;
    } catch (const std::exception& error) {
        napi_throw_error(env, nullptr, error.what());
        return nullptr;
    }
}

napi_value clearResources(napi_env env, napi_callback_info info) {
    napi_value arg{};
    size_t count = 1;
    bool releaseEngine = false;
    if (napi_get_cb_info(env, info, &count, &arg, nullptr, nullptr) != napi_ok || count != 1 ||
        napi_get_value_bool(env, arg, &releaseEngine) != napi_ok) {
        napi_throw_error(env, nullptr, "Expected releaseEngine flag");
        return nullptr;
    }
    {
        std::lock_guard<std::mutex> lock(rawCacheMutex);
        ++rawCacheEpoch;
        cachedRaw.reset();
        rawWarning.clear();
        cachedRawHalfSize = false;
        cachedRawUserQual = 3;
        inFlightRaw.reset();
    }
    {
        std::lock_guard<std::mutex> lock(resourcesMutex);
        previewCache.reset();
        if (releaseEngine) { cachedEngine.reset(); enginePath.clear(); }
    }
    napi_value result{};
    napi_get_undefined(env, &result);
    return result;
}

napi_value beginOperation(napi_env env, napi_callback_info) {
    std::lock_guard<std::mutex> lock(operationsMutex);
    do { ++nextOperation; } while (nextOperation == 0 || operations.count(nextOperation));
    operations.emplace(nextOperation, std::make_shared<Operation>());
    napi_value result{};
    napi_create_uint32(env, nextOperation, &result);
    return result;
}

napi_value cancelOperation(napi_env env, napi_callback_info info) {
    napi_value arg{}, result{};
    size_t count = 1;
    if (napi_get_cb_info(env, info, &count, &arg, nullptr, nullptr) == napi_ok && count == 1) {
        if (const auto operation = operationFor(env, arg)) {
            std::lock_guard<std::mutex> lock(operation->mutex);
            operation->cancelled.store(true);
            if (operation->session) spk_cancel(operation->session, nullptr);
        }
    }
    napi_get_undefined(env, &result);
    return result;
}

napi_value endOperation(napi_env env, napi_callback_info info) {
    napi_value arg{}, result{};
    size_t count = 1;
    uint32_t id = 0;
    if (napi_get_cb_info(env, info, &count, &arg, nullptr, nullptr) == napi_ok && count == 1 &&
        napi_get_value_uint32(env, arg, &id) == napi_ok) {
        std::lock_guard<std::mutex> lock(operationsMutex);
        operations.erase(id);
    }
    napi_get_undefined(env, &result);
    return result;
}

napi_value init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"render", nullptr, render<false>, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"renderLinear", nullptr, render<true>, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"renderRaw", nullptr, renderRaw, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"decodeRaw", nullptr, decodeRaw, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"predecodeRaw", nullptr, predecodeRaw, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"clearResources", nullptr, clearResources, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"beginOperation", nullptr, beginOperation, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"cancelOperation", nullptr, cancelOperation, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"endOperation", nullptr, endOperation, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    if (napi_define_properties(env, exports, sizeof desc / sizeof desc[0], desc) != napi_ok) return nullptr;
    return exports;
}
napi_module module{1, 0, nullptr, init, "spektralab", nullptr, {}};
}
extern "C" __attribute__((constructor)) void registerSpektraLab() { napi_module_register(&module); }
