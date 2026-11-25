#include "render_quality.hpp"

namespace harmony_perf {
namespace {
thread_local RenderQuality g_quality{};
}  // namespace

const RenderQuality& current_render_quality() { return g_quality; }

void set_render_quality(const RenderQuality& quality) { g_quality = quality; }

}  // namespace harmony_perf
