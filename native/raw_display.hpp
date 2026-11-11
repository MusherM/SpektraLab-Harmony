#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <array>
#include <vector>

namespace harmony_raw {
inline std::array<double, 3> display_linear(const float* rgb) {
#pragma clang fp contract(off)
    const double r = rgb[0], g = rgb[1], b = rgb[2];
    return {2.0341*r - 0.7273*g - 0.3068*b,
        -0.2288*r + 1.2317*g - 0.0029*b,
        -0.0086*r - 0.1533*g + 1.1619*b};
}

// Estimate display white from each channel's 99th percentile to compensate
// sensor headroom, without altering the linear film input.
inline double display_gain(const std::vector<float>& rgb) {
    constexpr size_t bins = 65536;
    std::vector<std::array<size_t, 3>> histogram(bins);
    size_t count = 0;
    for (size_t i = 0; i + 2 < rgb.size(); i += 3) {
        const auto linear = display_linear(rgb.data() + i);
        if (!std::isfinite(linear[0]) || !std::isfinite(linear[1]) || !std::isfinite(linear[2])) continue;
        for (size_t c = 0; c < 3; ++c)
            ++histogram[size_t(std::clamp(linear[c], 0.0, 1.0) * (bins - 1))][c];
        ++count;
    }
    if (!count) return 1.0;
    size_t white = 0;
    const size_t tail = count / 100;
    for (size_t c = 0; c < 3; ++c) {
        size_t total = 0;
        for (size_t b = bins - 1; b > 0; --b) {
            total += histogram[b][c];
            if (total > tail) { white = std::max(white, b); break; }
        }
    }
    // Keep black frames black and limit amplification of near-black noise.
    return white ? std::clamp(double(bins - 1) / white, 1.0, 16.0) : 1.0;
}

// Match the editor's double-precision ProPhoto D50 to sRGB D65 conversion.
inline void display_pixel(const float* rgb, uint8_t* rgba, double gain = 1.0) {
#pragma clang fp contract(off)
    const auto linear = display_linear(rgb);
    for (unsigned c = 0; c < 3; ++c) {
        const double v = std::isfinite(linear[c]) ? linear[c] * gain : 0.0;
        const double encoded = v <= 0.0031308 ? 12.92*v : 1.055*std::pow(v, 1/2.4)-0.055;
        rgba[c] = static_cast<uint8_t>(std::floor(255 * std::min(1.0, std::max(0.0, encoded)) + 0.5));
    }
    rgba[3] = 255;
}
}
