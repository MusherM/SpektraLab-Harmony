#include <napi/native_api.h>
#include <spektrafilm/spk_engine.h>
#include <cstdint>
#include <array>
#include <fcntl.h>
#include <unistd.h>
#include <cerrno>
#include <system_error>
#include "raw_decode.hpp"
#include "raw_display.hpp"
#include "srgb_meter.hpp"
#include <algorithm>
#include <cmath>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>
#include <mutex>
#include <sys/stat.h>
#include <chrono>

// Called from the editor worker with tightly packed, opaque sRGB RGBA8888 pixels.
namespace {
// N-API workers share this library; serialize engine and cache access.
std::mutex resourcesMutex;
using Engine = std::unique_ptr<spk_engine, decltype(&spk_engine_destroy)>;
Engine cachedEngine(nullptr, spk_engine_destroy);
std::string enginePath;
std::shared_ptr<spk::io::DecodedRaw> cachedRaw;
struct stat rawIdentity{};
std::string rawWarning;
constexpr size_t rawCacheLimit = 256u * 1024 * 1024;

spk_engine* acquireEngine(const std::string& path) {
    if (!cachedEngine || enginePath != path) {
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

napi_value finishRender(napi_env env, spk_engine* engine, spk_session* session, uint32_t w, uint32_t h) {
    if (!session) throw std::runtime_error(spk_last_error(engine));
    Output result;
    if (spk_render(session, "full", &result.value) != SPK_OK)
        throw std::runtime_error(spk_last_error(engine));
    const auto& frame = result.value;
    if (!frame.rgba16 || frame.width != w || frame.height != h || frame.row_stride_px < w)
        throw std::runtime_error("Unexpected render dimensions");
    void* destination = nullptr;
    napi_value buffer{};
    if (napi_create_arraybuffer(env, size_t(w) * h * 4, &destination, &buffer) != napi_ok)
        throw std::runtime_error("Cannot allocate output pixels");
    for (size_t y = 0; y < h; ++y) {
        auto row = frame.rgba16 + y * frame.row_stride_px * 4;
        auto out = static_cast<uint8_t*>(destination) + y * w * 4;
        for (size_t k = 0; k < size_t(w) * 4; ++k) out[k] = (row[k] + 128u) / 257u;
    }
    return buffer;
}

template<bool Linear>
napi_value render(napi_env env, napi_callback_info info) {
    std::lock_guard<std::mutex> lock(resourcesMutex);
    try {
        napi_value args[5]{};
        size_t count = 5;
        if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok || count != 5)
            throw std::runtime_error("Expected resources, pixels, width, height and parameter JSON");
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
        std::unique_ptr<spk_session, decltype(&spk_session_release)> session(nullptr, spk_session_release);
        if constexpr (Linear) {
            const spk_image input{static_cast<float*>(raw), w, h, 3};
            session.reset(spk_open(engine, &input, params.c_str(), nullptr));
        } else {
            auto pixels = static_cast<const uint8_t*>(raw);
            const double gain = srgb_meter::gain(pixels, w, h);
            std::vector<float> rgb(bytes / 4 * 3);
            for (size_t i = 0; i < bytes / 4; ++i)
                for (size_t c = 0; c < 3; ++c) rgb[i * 3 + c] = pixels[i * 4 + c] * gain / 255.0;
            const spk_image input{rgb.data(), w, h, 3};
            session.reset(spk_open(engine, &input, params.c_str(), nullptr));
        }
        return finishRender(env, engine, session.get(), w, h);
    } catch (const std::exception& error) {
        cachedEngine.reset();
        napi_throw_error(env, nullptr, error.what());
        return nullptr;
    }
}

class RawSourceFile {
public:
    RawSourceFile(int source, const std::string& cacheDir) {
        std::string pattern = cacheDir + "/spektralab-raw-XXXXXX";
        std::vector<char> name(pattern.begin(), pattern.end());
        name.push_back('\0');
        int destination = mkstemp(name.data());
        if (destination < 0) throw std::system_error(errno, std::generic_category(), "RAW cache");
        path_ = name.data();
        try {
            std::array<char, 65536> buffer;
            off_t offset = 0;
            for (;;) {
                ssize_t count = pread(source, buffer.data(), buffer.size(), offset);
                if (count < 0 && errno == EINTR) continue;
                if (count < 0) throw std::system_error(errno, std::generic_category(), "RAW read");
                if (count == 0) break;
                ssize_t written = 0;
                while (written < count) {
                    ssize_t part = write(destination, buffer.data() + written, count - written);
                    if (part < 0 && errno == EINTR) continue;
                    if (part <= 0) throw std::system_error(part < 0 ? errno : EIO,
                        std::generic_category(), "RAW cache write");
                    written += part;
                }
                offset += count;
            }
            if (offset == 0) throw std::runtime_error("RAW source is empty");
        } catch (...) {
            close(destination);
            unlink(path_.c_str());
            throw;
        }
        close(destination);
    }
    ~RawSourceFile() { unlink(path_.c_str()); }
    RawSourceFile(const RawSourceFile&) = delete;
    RawSourceFile& operator=(const RawSourceFile&) = delete;
    const std::string& path() const { return path_; }
private:
    std::string path_;
};

std::shared_ptr<spk::io::DecodedRaw> readRaw(int fd, const std::string& cacheDir, std::string* warning = nullptr) {
    struct stat identity{};
    if (fstat(fd, &identity) != 0) throw std::system_error(errno, std::generic_category(), "RAW identity");
    if (cachedRaw && sameSource(identity, rawIdentity)) {
        if (warning) *warning = rawWarning;
        return cachedRaw;
    }
    cachedRaw.reset();
    rawWarning.clear();
    // Gallery grants descriptor access; reopening its procfs link can be denied.
    RawSourceFile source(fd, cacheDir);
    std::string decodedWarning;
    auto raw = std::make_shared<spk::io::DecodedRaw>(harmony_raw::decode(source.path(), &decodedWarning));
    struct stat after{};
    if (fstat(fd, &after) != 0 || !sameSource(identity, after))
        throw std::runtime_error("RAW source changed while decoding");
    if (raw->rgb.size() <= rawCacheLimit / sizeof(float)) {
        cachedRaw = raw;
        rawIdentity = identity;
        rawWarning = decodedWarning;
    }
    if (warning) *warning = decodedWarning;
    return raw;
}

napi_value renderRaw(napi_env env, napi_callback_info info) {
    std::lock_guard<std::mutex> lock(resourcesMutex);
    try {
        napi_value args[4]{};
        size_t count = 4;
        int fd = -1;
        if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok ||
            count != 4 || napi_get_value_int32(env, args[1], &fd) != napi_ok || fd < 0)
            throw std::runtime_error("Expected resources, RAW file descriptor and parameter JSON");
        const auto path = readText(env, args[0]);
        const auto params = readText(env, args[2]);
        auto engine = acquireEngine(path);
        std::unique_ptr<spk_session, decltype(&spk_session_release)> session(nullptr, spk_session_release);
        uint32_t width, height;
        {
            auto raw = readRaw(fd, readText(env, args[3]));
            width = raw->width;
            height = raw->height;
            const spk_image input{raw->rgb.data(), width, height, 3};
            session.reset(spk_open(engine, &input, params.c_str(), nullptr));
        }
        napi_value result{}, w{}, h{};
        auto pixels = finishRender(env, engine, session.get(), width, height);
        if (napi_create_object(env, &result) != napi_ok ||
            napi_create_uint32(env, width, &w) != napi_ok || napi_create_uint32(env, height, &h) != napi_ok ||
            napi_set_named_property(env, result, "pixels", pixels) != napi_ok ||
            napi_set_named_property(env, result, "width", w) != napi_ok ||
            napi_set_named_property(env, result, "height", h) != napi_ok)
            throw std::runtime_error("Cannot return RAW print");
        return result;
    } catch (const std::exception& error) {
        cachedEngine.reset();
        napi_throw_error(env, nullptr, error.what());
        return nullptr;
    }
}

// The caller holds the picker file descriptor open until decoding returns.
napi_value decodeRaw(napi_env env, napi_callback_info info) {
    std::lock_guard<std::mutex> lock(resourcesMutex);
    try {
        napi_value args[2]{};
        size_t count = 2;
        int fd = -1;
        if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok ||
            count != 2 || napi_get_value_int32(env, args[0], &fd) != napi_ok || fd < 0)
            throw std::runtime_error("Expected RAW file descriptor");
        std::string warning;
        const auto decodeStarted = std::chrono::steady_clock::now();
        auto raw = readRaw(fd, readText(env, args[1]), &warning);
        const auto displayStarted = std::chrono::steady_clock::now();
        const double displayGain = harmony_raw::display_gain(raw->rgb);
        std::string rawInfo = raw->metadata.libraw_version + " | " +
            raw->metadata.make + " " + raw->metadata.model + " | " + raw->metadata.decoder_name +
            " | " + std::to_string(raw->width) + "x" + std::to_string(raw->height) +
            (warning.empty() ? " | WB=as-shot" : " | WB=daylight fallback");
        const double scale = std::min(1.0, 2048.0 / std::max(raw->width, raw->height));
        const auto width = std::max(1L, std::lround(raw->width * scale));
        const auto height = std::max(1L, std::lround(raw->height * scale));
        napi_value buffer{}, display{}, result{}, w{}, h{}, infoText{}, warningText{};
        void* destination{};
        void* displayDestination{};
        if (napi_create_arraybuffer(env, width * height * 3 * sizeof(float), &destination, &buffer) != napi_ok)
            throw std::runtime_error("Cannot allocate RAW preview");
        if (napi_create_arraybuffer(env, width * height * 4, &displayDestination, &display) != napi_ok)
            throw std::runtime_error("Cannot allocate RAW display");
        auto out = static_cast<float*>(destination);
        auto rgba = static_cast<uint8_t*>(displayDestination);
        for (long y = 0; y < height; ++y) {
            const size_t sy = (2 * y + 1) * raw->height / (2 * height);
            for (long x = 0; x < width; ++x) {
                const size_t sx = (2 * x + 1) * raw->width / (2 * width);
                std::copy_n(raw->rgb.data() + (sy * raw->width + sx) * 3, 3, out);
                harmony_raw::display_pixel(out, rgba, displayGain);
                out += 3;
                rgba += 4;
            }
        }
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
    } catch (const std::exception& error) {
        cachedEngine.reset();
        napi_throw_error(env, nullptr, error.what());
        return nullptr;
    }
}

napi_value clearResources(napi_env env, napi_callback_info info) {
    std::lock_guard<std::mutex> lock(resourcesMutex);
    napi_value arg{};
    size_t count = 1;
    bool releaseEngine = false;
    if (napi_get_cb_info(env, info, &count, &arg, nullptr, nullptr) != napi_ok || count != 1 ||
        napi_get_value_bool(env, arg, &releaseEngine) != napi_ok) {
        napi_throw_error(env, nullptr, "Expected releaseEngine flag");
        return nullptr;
    }
    cachedRaw.reset();
    rawWarning.clear();
    if (releaseEngine) { cachedEngine.reset(); enginePath.clear(); }
    napi_value result{};
    napi_get_undefined(env, &result);
    return result;
}

napi_value init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"render", nullptr, render<false>, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"renderLinear", nullptr, render<true>, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"renderRaw", nullptr, renderRaw, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"decodeRaw", nullptr, decodeRaw, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"clearResources", nullptr, clearResources, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    if (napi_define_properties(env, exports, 5, desc) != napi_ok) return nullptr;
    return exports;
}
napi_module module{1, 0, nullptr, init, "spektralab", nullptr, {}};
}
extern "C" __attribute__((constructor)) void registerSpektraLab() { napi_module_register(&module); }
