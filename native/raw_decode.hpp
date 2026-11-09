#pragma once
#include "io/raw_decoder.hpp"

namespace harmony_raw {
spk::io::DecodedRaw decode(const std::string& path, std::string* warning = nullptr);
}
