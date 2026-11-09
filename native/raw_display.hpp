#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>

namespace harmony_raw {
// Match the editor's double-precision ProPhoto D50 to sRGB D65 conversion.
inline void display_pixel(const float* rgb, uint8_t* rgba) {
#pragma clang fp contract(off)
    const double r = rgb[0], g = rgb[1], b = rgb[2];
    const double linear[] = {
        2.0341*r - 0.7273*g - 0.3068*b,
        -0.2288*r + 1.2317*g - 0.0029*b,
        -0.0086*r - 0.1533*g + 1.1619*b
    };
    for (unsigned c = 0; c < 3; ++c) {
        const double v = linear[c];
        const double encoded = v <= 0.0031308 ? 12.92*v : 1.055*std::pow(v, 1/2.4)-0.055;
        rgba[c] = static_cast<uint8_t>(std::floor(255 * std::min(1.0, std::max(0.0, encoded)) + 0.5));
    }
    rgba[3] = 255;
}
}
