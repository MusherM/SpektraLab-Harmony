#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <vector>

namespace srgb_meter {
// Match skimage rescale(order=0) on float RGB: Gaussian antialiasing,
// mirrored edges, then nearest-neighbour sampling at pixel centres.
struct Samples {
    std::vector<int> indices;
    std::vector<double> weights;
};

inline std::vector<Samples> sampleAxis(int size, int count) {
    const double scale = double(size) / count;
    const double sigma = (scale - 1) / 2;
    const int radius = int(4 * sigma + 0.5);
    std::vector<Samples> axis(count);
    for (int i = 0; i < count; ++i) {
        const int centre = int((i + 0.5) * scale);
        double sum = 0;
        for (int d = -radius; d <= radius; ++d) {
            int j = centre + d;
            if (size > 1) {
                const int period = 2 * (size - 1);
                j = ((j % period) + period) % period;
                j = std::min(j, period - j);
            }
            const double weight = d == 0 ? 1.0 : std::exp(-0.5 * d * d / (sigma * sigma));
            axis[i].indices.push_back(j);
            axis[i].weights.push_back(weight);
            sum += weight;
        }
        for (double& weight : axis[i].weights) weight /= sum;
    }
    return axis;
}

inline double linear(double v) {
    return v <= 0.04045 ? v / 12.92 : std::pow((v + 0.055) / 1.055, 2.4);
}

inline double gain(const uint8_t* rgba, int w, int h) {
    const double scale = std::min(1.0, 256.0 / std::max(w, h));
    const int sw = std::max(1, int(std::nearbyint(w * scale)));
    const int sh = std::max(1, int(std::nearbyint(h * scale)));
    const auto xs = sampleAxis(w, sw), ys = sampleAxis(h, sh);
    std::vector<std::array<double, 3>> rows(size_t(sw) * h);
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < sw; ++x) {
            auto& rgb = rows[size_t(y) * sw + x];
            for (size_t k = 0; k < xs[x].indices.size(); ++k) {
                const auto* pixel = rgba + 4 * (size_t(y) * w + xs[x].indices[k]);
                for (int c = 0; c < 3; ++c) rgb[c] += xs[x].weights[k] * pixel[c] / 255.0;
            }
        }
    }
    double sum = 0, weights = 0;
    for (int y = 0; y < sh; ++y) {
        for (int x = 0; x < sw; ++x) {
            double rgb[3]{};
            for (size_t k = 0; k < ys[y].indices.size(); ++k) {
                const auto& row = rows[size_t(ys[y].indices[k]) * sw + x];
                for (int c = 0; c < 3; ++c) rgb[c] += ys[y].weights[k] * row[c];
            }
            const double dx = (x - sw * .5) / std::max(sw, sh);
            const double dy = (y - sh * .5) / std::max(sw, sh);
            const double weight = std::exp(-(dx * dx + dy * dy) / .08);
            sum += weight * (.2126 * linear(rgb[0]) + .7152 * linear(rgb[1]) + .0722 * linear(rgb[2]));
            weights += weight;
        }
    }
    return sum > 0 ? .184 * weights / sum : 1.0;
}
}
