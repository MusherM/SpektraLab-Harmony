#pragma once
#include <cstdint>

namespace harmony_perf {

struct RenderQuality {
    int mixture_scale = 1;       // 1 = exact full-res, 2 = Tier B half-res blur mixture
    bool iir_f32 = false;        // false = exact double-float IIR, true = float32 IIR (used with mixture_scale >= 2)
    uint32_t print_lut_size = 0; // 0 = exact spectral print+scan, 65 = dynamic GPU-baked 65^3 3D LUT
};

const RenderQuality& current_render_quality();
void set_render_quality(const RenderQuality& quality);

inline RenderQuality exact_quality() { return {1, false, 0u}; }
inline RenderQuality fast_quality() { return {2, true, 65u}; }

class ScopedRenderQuality {
public:
    explicit ScopedRenderQuality(const RenderQuality& next) : prev_(current_render_quality()) {
        set_render_quality(next);
    }
    ~ScopedRenderQuality() { set_render_quality(prev_); }
    ScopedRenderQuality(const ScopedRenderQuality&) = delete;
    ScopedRenderQuality& operator=(const ScopedRenderQuality&) = delete;

private:
    RenderQuality prev_;
};

}  // namespace harmony_perf
