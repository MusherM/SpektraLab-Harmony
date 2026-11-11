#include "../native/raw_display.hpp"
#include <cassert>
#include <iostream>
#include <limits>

int main() {
    using namespace harmony_raw;
    std::vector<float> black(300, 0.0f);
    assert(display_gain(black) == 1.0);
    std::vector<float> gray(300, 0.25f);
    const auto original = gray;
    const double gain = display_gain(gray);
    assert(gain > 3.99 && gain < 4.01);
    assert(gray == original);
    uint8_t before[4], after[4];
    display_pixel(gray.data(), before);
    display_pixel(gray.data(), after, gain);
    assert(before[0] == 137 && after[0] == 255 && after[3] == 255);
    std::vector<float> white(300, 1.0f);
    assert(display_gain(white) == 1.0);
    std::vector<float> noise(300, 0.0001f);
    assert(display_gain(noise) == 16.0);
    // Isolated hot pixels must not prevent exposure restoration.
    gray[0] = gray[1] = gray[2] = 1.0f;
    assert(display_gain(gray) > 3.99);
    gray[0] = std::numeric_limits<float>::quiet_NaN();
    assert(std::isfinite(display_gain(gray)));
    display_pixel(gray.data(), after, gain);
    assert(after[0] == 0 && after[3] == 255);
    std::cout << "RAW display: black, midtone, white, noise, hot pixels, invalid pixels and input preservation passed\n";
}
