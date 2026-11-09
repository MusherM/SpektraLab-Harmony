#include "raw_decode.hpp"
#include <libraw/libraw.h>
#include <algorithm>
#include <cmath>
#include <memory>
#include <stdexcept>

namespace harmony_raw {
namespace {
void check(int status, const char* stage) {
    if (status != LIBRAW_SUCCESS)
        throw std::runtime_error(std::string("RAW ") + stage + ": " + libraw_strerror(status));
}

// Legacy RAWs can omit as-shot WB (some cameras stored it in a companion file).
// Use LibRaw's camera daylight calibration only for this specific metadata failure.
spk::io::DecodedRaw daylight(const std::string& path) {
    auto raw = std::make_unique<LibRaw>(LIBRAW_OPTIONS_NO_DATAERR_CALLBACK);
    auto& p = raw->imgdata.params;
    p.user_qual = 3;
    p.output_color = 4;
    p.output_bps = 16;
    p.gamm[0] = p.gamm[1] = 1.0;
    p.no_auto_bright = 1;
    p.adjust_maximum_thr = 0;
    p.use_camera_wb = 0;
    p.use_auto_wb = 0;
    p.use_camera_matrix = 1;
    check(raw->open_file(path.c_str()), "open");
    check(raw->unpack(), "unpack");
    if (raw->error_count()) throw std::runtime_error("RAW unpack: corrupt data");
    const auto& source = raw->imgdata.rawdata.color;
    for (unsigned c = 0; c < 4; ++c) {
        float value = source.pre_mul[c];
        if (c == 3 && raw->imgdata.idata.colors == 3 && value == 0) value = source.pre_mul[1];
        if (!std::isfinite(value) || value <= 0)
            throw std::runtime_error("RAW metadata: daylight white balance is unavailable");
        p.user_mul[c] = value;
    }
    spk::io::DecodedRaw result;
    auto& metadata = result.metadata;
    metadata.libraw_version = LibRaw::version();
    metadata.libraw_capabilities = LibRaw::capabilities();
    metadata.make = raw->imgdata.idata.make;
    metadata.model = raw->imgdata.idata.model;
    if (const char* decoder = raw->unpack_function_name()) metadata.decoder_name = decoder;
    std::copy_n(source.cam_mul, 4, metadata.camera_whitebalance.begin());
    check(raw->dcraw_process(), "process");
    if (raw->error_count()) throw std::runtime_error("RAW process: corrupt data");
    int status = LIBRAW_SUCCESS;
    std::unique_ptr<libraw_processed_image_t, decltype(&LibRaw::dcraw_clear_mem)> image(
        raw->dcraw_make_mem_image(&status), LibRaw::dcraw_clear_mem);
    check(status, "output");
    if (!image || image->type != LIBRAW_IMAGE_BITMAP || image->bits != 16 ||
        image->colors != 3 || !image->width || !image->height ||
        image->data_size != size_t(image->width) * image->height * 6)
        throw std::runtime_error("RAW output: invalid daylight bitmap");
    result.width = image->width;
    result.height = image->height;
    const auto* values = reinterpret_cast<const uint16_t*>(image->data);
    result.rgb.resize(size_t(result.width) * result.height * 3);
    std::transform(values, values + result.rgb.size(), result.rgb.begin(),
        [](uint16_t value) { return float(double(value) / 65535.0); });
    return result;
}
}

spk::io::DecodedRaw decode(const std::string& path, std::string* warning) {
    spk::io::RawDecodeThreadScope threads;
    if (warning) warning->clear();
    {
        auto probe = std::make_unique<LibRaw>(LIBRAW_OPTIONS_NO_DATAERR_CALLBACK);
        check(probe->open_file(path.c_str()), "open");
        const auto offset = probe->get_internal_data_pointer()->unpacker_data.data_offset;
        // Some truncated DNGs retain valid metadata but decode to an empty black frame.
        if (offset > 0 && static_cast<uint64_t>(offset) >= std::filesystem::file_size(path))
            throw std::runtime_error("RAW source is truncated before image data");
    }
    spk::io::DecodedRaw result;
    std::string error;
    if (spk::io::decode_raw_compatible(path, result, error)) return result;
    if (error != "RAW metadata: valid camera/as-shot RGB white balance is required")
        throw std::runtime_error(error);
    result = daylight(path);
    if (warning) *warning = "未读取到拍摄白平衡，已使用日光白平衡";
    return result;
}
}
