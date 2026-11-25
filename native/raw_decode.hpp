#pragma once
#include "io/raw_decoder.hpp"
#include <cstddef>
#include <cstdint>
#include <string>

namespace harmony_raw {
struct DecodeOptions {
    int user_qual = 3;   // 3 = AHD / X-Trans 3-pass (default lossless), 2 = PPG / X-Trans 1-pass, 0 = Linear
    bool half_size = false;
};

spk::io::DecodedRaw decode(const std::string& path, std::string* warning = nullptr);
spk::io::DecodedRaw decode(const std::string& path, const DecodeOptions& options, std::string* warning = nullptr);
spk::io::DecodedRaw decode_buffer(const uint8_t* data, size_t size, std::string* warning = nullptr);
spk::io::DecodedRaw decode_buffer(const uint8_t* data, size_t size, const DecodeOptions& options, std::string* warning = nullptr);
}
