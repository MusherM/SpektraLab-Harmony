#include "../native/raw_decode.hpp"
#include <bit>
#include <cstdint>
#include <exception>
#include <iostream>
#include <stdexcept>
#include <thread>

namespace {
struct Fingerprint {
    uint32_t width, height;
    uint64_t hash;
    bool operator==(const Fingerprint&) const = default;
};

Fingerprint decode(const std::string& path) {
    auto raw = harmony_raw::decode(path);
    if (!raw.width || !raw.height || raw.rgb.size() != size_t(raw.width) * raw.height * 3)
        throw std::runtime_error("Invalid decoded dimensions");
    uint64_t hash = 14695981039346656037ull;
    for (float value : raw.rgb) {
        hash ^= std::bit_cast<uint32_t>(value);
        hash *= 1099511628211ull;
    }
    return {raw.width, raw.height, hash};
}
}

int main(int argc, char** argv) {
    if (argc != 2) return 2;
    try {
        const std::string path = argv[1];
        Fingerprint expected{};
        for (int i = 0; i < 16; ++i) {
            Fingerprint actual{};
            std::exception_ptr error;
            // Each caller exits, matching task-pool worker retirement.
            std::thread caller([&] {
                try {
                    if (i == 0 || i == 8) {
                        bool rejected = false;
                        try { harmony_raw::decode(path + ".missing"); }
                        catch (const std::exception&) { rejected = true; }
                        if (!rejected) throw std::runtime_error("Missing input was accepted");
                    }
                    actual = decode(path);
                } catch (...) { error = std::current_exception(); }
            });
            caller.join();
            if (error) std::rethrow_exception(error);
            if (i == 0) expected = actual;
            if (actual != expected) throw std::runtime_error("Decoded pixels changed");
            std::cout << "PASS retired caller " << i + 1 << " hash=" << actual.hash << std::endl;
        }
        Fingerprint results[2]{};
        std::exception_ptr errors[2];
        std::thread callers[2];
        for (int i = 0; i < 2; ++i) callers[i] = std::thread([&, i] {
            try { results[i] = decode(path); }
            catch (...) { errors[i] = std::current_exception(); }
        });
        for (auto& caller : callers) caller.join();
        for (int i = 0; i < 2; ++i) {
            if (errors[i]) std::rethrow_exception(errors[i]);
            if (results[i] != expected) throw std::runtime_error("Concurrent result changed");
        }
        std::cout << "PASS 18 decodes, 2 rejected inputs, caller retirement and concurrent callers" << std::endl;
    } catch (const std::exception& error) {
        std::cerr << error.what() << std::endl;
        return 1;
    }
}
