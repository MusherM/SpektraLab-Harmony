#include "raw_decode.hpp"
#include <libraw/libraw.h>
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstring>
#include <deque>
#include <filesystem>
#include <future>
#include <limits>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <thread>
#ifdef _OPENMP
#include <omp.h>
#endif

namespace harmony_raw {
namespace {
using Clock = std::chrono::steady_clock;

double elapsed_ms(Clock::time_point t0) {
    return std::chrono::duration<double, std::milli>(Clock::now() - t0).count();
}

void check(int status, const char* stage) {
    if (status != LIBRAW_SUCCESS)
        throw std::runtime_error(std::string("RAW ") + stage + ": " + libraw_strerror(status));
}

const std::array<float, 65536>& u16_to_f32_lut() {
    static const std::array<float, 65536> lut = [] {
        std::array<float, 65536> table{};
        for (size_t i = 0; i < 65536; ++i) table[i] = static_cast<float>(static_cast<double>(i) / 65535.0);
        return table;
    }();
    return lut;
}

// Compute LibRaw's exact flip_index(row, col) matching LibRaw::flip_index after
// S.iheight = S.height; S.iwidth = S.width; if (S.flip & 4) swap(S.height, S.width).
int64_t libraw_flip_index(int row, int col, int flip, int iheight, int iwidth) {
    if (flip & 4) std::swap(row, col);
    if (flip & 2) row = iheight - 1 - row;
    if (flip & 1) col = iwidth - 1 - col;
    return int64_t(row) * int64_t(iwidth) + int64_t(col);
}

// Bit-exact direct parallel conversion from LibRaw's processed imgdata.image to
// oriented float32 RGB, avoiding dcraw_make_mem_image's 100-150 MB allocation
// and two sequential single-threaded passes.
bool convert_direct_parallel(LibRaw& raw, spk::io::DecodedRaw& out) {
    const auto& data = raw.imgdata;
    const auto& O = data.params;
    const auto& S = data.sizes;
    const auto& IO = raw.get_internal_data_pointer()->internal_output_params;
    // Fast path requires standard 16-bit 3-channel linear output without Fuji 45-deg
    // rotation or non-square pixel stretching (which copy_mem_image handles only after
    // dcraw_process, or if progress flags didn't already run fuji_rotate).
    if (!data.image || data.idata.colors != 3 || O.output_bps != 16 ||
        !O.no_auto_bright || O.gamm[0] != 1.0 || O.gamm[1] != 1.0 || O.bright != 1.0f ||
        (IO.fuji_width != 0 && O.use_fuji_rotate) ||
        S.pixel_aspect < 0.995 || S.pixel_aspect > 1.005) {
        return false;
    }
    const int src_w = S.width;
    const int src_h = S.height;
    if (src_w <= 0 || src_h <= 0) return false;
    const int out_w = (S.flip & 4) ? src_h : src_w;
    const int out_h = (S.flip & 4) ? src_w : src_h;
    const int64_t soff0 = libraw_flip_index(0, 0, S.flip, src_h, src_w);
    const int64_t cstep = libraw_flip_index(0, 1, S.flip, src_h, src_w) - soff0;
    const int64_t rstep_row = libraw_flip_index(1, 0, S.flip, src_h, src_w) - soff0;

    // Verify linear stride invariant matches LibRaw::copy_mem_image.
    if (out_h > 1 && out_w > 1) {
        const int64_t check_end = libraw_flip_index(out_h - 1, out_w - 1, S.flip, src_h, src_w);
        if (check_end != soff0 + int64_t(out_h - 1) * rstep_row + int64_t(out_w - 1) * cstep) {
            return false;
        }
    }

    const auto& lut = u16_to_f32_lut();
    out.width = uint32_t(out_w);
    out.height = uint32_t(out_h);
    out.rgb.resize(size_t(out_w) * size_t(out_h) * 3u);
    const auto* img = data.image;
    float* dst = out.rgb.data();

#pragma omp parallel for schedule(static)
    for (int row = 0; row < out_h; ++row) {
        int64_t soff = soff0 + int64_t(row) * rstep_row;
        float* row_dst = dst + size_t(row) * size_t(out_w) * 3u;
        if (cstep == 1) {
            for (int col = 0; col < out_w; ++col) {
                const uint16_t* px = img[soff + col];
                row_dst[3 * col + 0] = lut[px[0]];
                row_dst[3 * col + 1] = lut[px[1]];
                row_dst[3 * col + 2] = lut[px[2]];
            }
        } else {
            for (int col = 0; col < out_w; ++col, soff += cstep) {
                const uint16_t* px = img[soff];
                row_dst[3 * col + 0] = lut[px[0]];
                row_dst[3 * col + 1] = lut[px[1]];
                row_dst[3 * col + 2] = lut[px[2]];
            }
        }
    }
    return true;
}

void convert_fallback(LibRaw& raw, spk::io::DecodedRaw& result) {
    int status = LIBRAW_SUCCESS;
    std::unique_ptr<libraw_processed_image_t, decltype(&LibRaw::dcraw_clear_mem)> image(
        raw.dcraw_make_mem_image(&status), LibRaw::dcraw_clear_mem);
    check(status, "output");
    if (!image || image->type != LIBRAW_IMAGE_BITMAP || image->bits != 16 ||
        image->colors != 3 || !image->width || !image->height ||
        image->data_size != size_t(image->width) * image->height * 6)
        throw std::runtime_error("RAW output: invalid 16-bit bitmap");
    result.width = image->width;
    result.height = image->height;
    const size_t samples = size_t(result.width) * result.height * 3u;
    const auto* values = reinterpret_cast<const uint16_t*>(image->data);
    const auto& lut = u16_to_f32_lut();
    result.rgb.resize(samples);
    float* dst = result.rgb.data();
#pragma omp parallel for schedule(static)
    for (size_t i = 0; i < samples; ++i) dst[i] = lut[values[i]];
}

class ObservingLibRaw final : public LibRaw {
public:
    ObservingLibRaw() : LibRaw(LIBRAW_OPTIONS_NO_DATAERR_CALLBACK) {}
    std::array<float, 12> matrix{};
protected:
    void convert_to_rgb_loop(float out_cam[3][4]) override {
        if (!libraw_internal_data.internal_output_params.raw_color && imgdata.idata.colors == 3)
            for (unsigned row = 0; row < 3; ++row)
                for (unsigned col = 0; col < 4; ++col)
                    matrix[row * 4 + col] = out_cam[row][col];
        LibRaw::convert_to_rgb_loop(out_cam);
    }
};

void configure_params(libraw_output_params_t& params, const DecodeOptions& options) {
    params.user_qual = options.user_qual;
    params.half_size = options.half_size ? 1 : 0;
    params.four_color_rgb = 0;
    params.output_color = 4;
    params.output_bps = 16;
    params.gamm[0] = params.gamm[1] = 1.0;
    params.no_auto_bright = 1;
    params.no_auto_scale = 0;
    params.adjust_maximum_thr = 0.0f;
    params.bright = 1.0f;
    params.use_camera_wb = 1;
    params.use_auto_wb = 0;
    params.use_camera_matrix = 1;
    std::fill(std::begin(params.user_mul), std::end(params.user_mul), 0.0f);
    params.user_black = -1;
    std::fill(std::begin(params.user_cblack), std::end(params.user_cblack), -1000001);
    params.user_sat = -1;
    params.user_flip = -1;
    params.highlight = 0;
    params.exp_correc = 0;
    params.exp_shift = 1.0f;
    params.exp_preser = 0.0f;
    params.threshold = 0.0f;
    params.med_passes = 0;
    params.fbdd_noiserd = 0;
    params.dcb_iterations = 0;
    params.dcb_enhance_fl = 0;
    params.no_interpolation = 0;
    params.output_profile = nullptr;
    params.camera_profile = nullptr;
}

spk::io::DecodedRaw decode_opened(std::unique_ptr<ObservingLibRaw> raw, uint64_t source_size,
                                  const DecodeOptions& options, std::string* warning,
                                  Clock::time_point total_start, double open_ms) {
    if (warning) warning->clear();
    const auto offset = raw->get_internal_data_pointer()->unpacker_data.data_offset;
    if (offset > 0 && static_cast<uint64_t>(offset) >= source_size)
        throw std::runtime_error("RAW source is truncated before image data");

    const char* decoder_fn = raw->unpack_function_name();
    if (decoder_fn && std::strstr(decoder_fn, "nikon_he_load_raw") != nullptr) {
        const auto& model = raw->imgdata.idata.model;
        throw std::runtime_error("RAW unpack (" +
            std::string(std::begin(model), std::find(std::begin(model), std::end(model), '\0')) +
            "): Nikon HE/HE* compression is not supported by bundled LibRaw " + LibRaw::version());
    }

    auto t_unpack = Clock::now();
    check(raw->unpack(), "unpack");
    const double unpack_ms = elapsed_ms(t_unpack);
    if (raw->error_count() != 0) throw std::runtime_error("RAW unpack: decoder reported corrupt data");

    spk::io::DecodedRaw result;
    result.timings.openmp_enabled = spk::io::raw_openmp_enabled();
    result.timings.workers = spk::io::raw_worker_limit();
    result.timings.open_ms = open_ms;
    result.timings.unpack_ms = unpack_ms;

    const auto& data = raw->imgdata;
    const auto& source_color = data.rawdata.color;
    const auto& sizes = data.sizes;
    bool valid_camera_wb = true;
    for (unsigned c = 0; c < 4; ++c) {
        const float wb = source_color.cam_mul[c];
        if (!std::isfinite(wb) || (c < 3 && wb <= 0.00001f)) {
            valid_camera_wb = false;
            break;
        }
        result.metadata.camera_whitebalance[c] = wb;
        const uint64_t black = uint64_t(source_color.black) + source_color.cblack[c];
        if (black > std::numeric_limits<uint32_t>::max())
            throw std::runtime_error("RAW metadata: black level overflow");
        result.metadata.black_level_per_channel[c] = static_cast<uint32_t>(black);
        result.metadata.camera_white_level_per_channel[c] = source_color.linear_max[c];
    }

    bool daylight_fallback = false;
    if (!valid_camera_wb) {
        // Legacy RAWs can omit as-shot WB; use LibRaw's camera daylight calibration.
        raw->imgdata.params.use_camera_wb = 0;
        raw->imgdata.params.use_auto_wb = 0;
        for (unsigned c = 0; c < 4; ++c) {
            float value = source_color.pre_mul[c];
            if (c == 3 && data.idata.colors == 3 && value == 0) value = source_color.pre_mul[1];
            if (!std::isfinite(value) || value <= 0)
                throw std::runtime_error("RAW metadata: daylight white balance is unavailable");
            raw->imgdata.params.user_mul[c] = value;
        }
        std::copy_n(source_color.cam_mul, 4, result.metadata.camera_whitebalance.begin());
        daylight_fallback = true;
    }

    result.metadata.libraw_version = LibRaw::version();
    result.metadata.libraw_capabilities = LibRaw::capabilities();
    result.metadata.make.assign(data.idata.make,
        std::find(std::begin(data.idata.make), std::end(data.idata.make), '\0'));
    result.metadata.model.assign(data.idata.model,
        std::find(std::begin(data.idata.model), std::end(data.idata.model), '\0'));
    if (decoder_fn) result.metadata.decoder_name = decoder_fn;
    result.metadata.sizes_before_postprocess = {
        sizes.raw_width, sizes.raw_height, sizes.width, sizes.height,
        sizes.iwidth, sizes.iheight, sizes.top_margin, sizes.left_margin,
        sizes.pixel_aspect};
    result.metadata.raw_flip = sizes.flip;
    result.metadata.colour_channels = data.idata.colors;
    for (unsigned r = 0; r < 3; ++r)
        for (unsigned c = 0; c < 3; ++c)
            result.metadata.camera_from_xyz[r * 3 + c] = source_color.cam_xyz[r][c];
    result.metadata.as_shot_wb_applied = source_color.as_shot_wb_applied != 0;
    result.metadata.black = source_color.black;
    result.metadata.white_level = source_color.maximum;

    if (options.half_size && std::max(sizes.width, sizes.height) < 3200) {
        raw->imgdata.params.half_size = 0;
    }
    auto t_proc = Clock::now();
    check(raw->dcraw_process(), "process");
    result.timings.process_ms = elapsed_ms(t_proc);
    if (raw->error_count() != 0) throw std::runtime_error("RAW process: decoder reported corrupt data");

    const auto& color = raw->imgdata.color;
    result.metadata.process_warnings = raw->imgdata.process_warnings;
    if (!daylight_fallback && (result.metadata.process_warnings & LIBRAW_WARN_BAD_CAMERA_WB))
        throw std::runtime_error("RAW process: LibRaw rejected camera/as-shot white balance");
    std::copy(std::begin(color.pre_mul), std::end(color.pre_mul),
              result.metadata.post_scale_pre_mul.begin());
    for (unsigned c = 0; c < 4; ++c) {
        if (!std::isfinite(color.pre_mul[c]) || color.pre_mul[c] <= 0.0f)
            throw std::runtime_error("RAW process: invalid applied white-balance multiplier");
    }
    for (unsigned r = 0; r < 3; ++r)
        for (unsigned c = 0; c < 4; ++c)
            result.metadata.rgb_cam[r * 4 + c] = color.rgb_cam[r][c];
    result.metadata.postprocess_black = color.black;
    result.metadata.postprocess_maximum = color.maximum;
    result.metadata.camera_to_output = raw->matrix;

    auto t_conv = Clock::now();
    if (!convert_direct_parallel(*raw, result)) {
        convert_fallback(*raw, result);
    }
    raw.reset();
    result.timings.convert_ms = elapsed_ms(t_conv);
    result.timings.total_ms = elapsed_ms(total_start);
    if (daylight_fallback && warning) *warning = "未读取到拍摄白平衡，已使用日光白平衡";
    (void)options;
    return result;
}

spk::io::DecodedRaw decode_path_on_worker(const std::string& path, const DecodeOptions& options, std::string* warning) {
    spk::io::RawDecodeThreadScope threads;
    const auto total_start = Clock::now();
    auto raw = std::make_unique<ObservingLibRaw>();
    configure_params(raw->imgdata.params, options);
    auto t_open = Clock::now();
    check(raw->open_file(path.c_str()), "open");
    const double open_ms = elapsed_ms(t_open);
    const uint64_t fsize = std::filesystem::file_size(path);
    return decode_opened(std::move(raw), fsize, options, warning, total_start, open_ms);
}

spk::io::DecodedRaw decode_buf_on_worker(const uint8_t* data, size_t size, const DecodeOptions& options, std::string* warning) {
    spk::io::RawDecodeThreadScope threads;
    const auto total_start = Clock::now();
    auto raw = std::make_unique<ObservingLibRaw>();
    configure_params(raw->imgdata.params, options);
    auto t_open = Clock::now();
    check(raw->open_buffer(data, size), "open");
    const double open_ms = elapsed_ms(t_open);
    return decode_opened(std::move(raw), uint64_t(size), options, warning, total_start, open_ms);
}

struct DecodeResult {
    spk::io::DecodedRaw raw;
    std::string warning;
};

// With this SDK, retiring the first OpenMP caller clears runtime state and
// later LibRaw critical sections fail. Keep that caller alive across tasks.
class DecodeWorker {
public:
    DecodeWorker() : thread_([this] { loop(); }) {}
    ~DecodeWorker() {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            stopping_ = true;
        }
        ready_.notify_one();
        thread_.join();
    }

    DecodeResult run_path(const std::string& path, const DecodeOptions& options) {
        std::packaged_task<DecodeResult()> task([path, options] {
            DecodeResult result;
            result.raw = decode_path_on_worker(path, options, &result.warning);
            return result;
        });
        return submit(std::move(task));
    }

    DecodeResult run_buffer(const uint8_t* data, size_t size, const DecodeOptions& options) {
        std::packaged_task<DecodeResult()> task([data, size, options] {
            DecodeResult result;
            result.raw = decode_buf_on_worker(data, size, options, &result.warning);
            return result;
        });
        return submit(std::move(task));
    }

private:
    DecodeResult submit(std::packaged_task<DecodeResult()> task) {
        auto result = task.get_future();
        {
            std::lock_guard<std::mutex> lock(mutex_);
            tasks_.push_back(std::move(task));
        }
        ready_.notify_one();
        return result.get();
    }

    void loop() {
        for (;;) {
            std::packaged_task<DecodeResult()> task;
            {
                std::unique_lock<std::mutex> lock(mutex_);
                ready_.wait(lock, [this] { return stopping_ || !tasks_.empty(); });
                if (tasks_.empty()) return;
                task = std::move(tasks_.front());
                tasks_.pop_front();
            }
            task();
        }
    }

    std::mutex mutex_;
    std::condition_variable ready_;
    std::deque<std::packaged_task<DecodeResult()>> tasks_;
    bool stopping_ = false;
    std::thread thread_;
};

DecodeWorker& worker() {
    static DecodeWorker instance;
    return instance;
}
}  // namespace

spk::io::DecodedRaw decode(const std::string& path, const DecodeOptions& options, std::string* warning) {
    if (warning) warning->clear();
    auto result = worker().run_path(path, options);
    if (warning) *warning = std::move(result.warning);
    return std::move(result.raw);
}

spk::io::DecodedRaw decode(const std::string& path, std::string* warning) {
    return decode(path, DecodeOptions{}, warning);
}

spk::io::DecodedRaw decode_buffer(const uint8_t* data, size_t size, const DecodeOptions& options, std::string* warning) {
    if (warning) warning->clear();
    auto result = worker().run_buffer(data, size, options);
    if (warning) *warning = std::move(result.warning);
    return std::move(result.raw);
}

spk::io::DecodedRaw decode_buffer(const uint8_t* data, size_t size, std::string* warning) {
    return decode_buffer(data, size, DecodeOptions{}, warning);
}
}
