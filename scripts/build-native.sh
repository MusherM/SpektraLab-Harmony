#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
: "${SPEKTRALAB_SOURCE_DIR:?Set to a clean checkout of JamesQiu2005/SpektraLab at 445e314}"
: "${GLSLANG:?Set to a host glslang executable (tested with 16.0.0)}"
sdk=${OHOS_NATIVE_SDK:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native}
build=${BUILD_DIR:-"$root/.build/native"}
rev=445e314e28b9b455d2457471fadaffd28c07270b
[[ $(git -C "$SPEKTRALAB_SOURCE_DIR" rev-parse HEAD) == "$rev" ]]
git -C "$SPEKTRALAB_SOURCE_DIR" diff --quiet HEAD --
[[ -x "$GLSLANG" ]]
raw_source=$(bash "$SPEKTRALAB_SOURCE_DIR/engine/setup-libraw.sh" "${SPEKTRALAB_DEPS_DIR:-$root/.build/deps}" | tail -1)
jpeg_source=$(bash "$root/scripts/setup-jpeg.sh" "${SPEKTRALAB_DEPS_DIR:-$root/.build/deps}" | tail -1)
cm="$sdk/build-tools/cmake/bin/cmake"
"$cm" -S "$root/native" -B "$build" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$sdk/build/cmake/ohos.toolchain.cmake" \
  -DOHOS_ARCH=arm64-v8a -DOHOS_STL=c++_static -DCMAKE_BUILD_TYPE=Release \
  -DSPEKTRALAB_BUILD_NATIVE_RAW=ON -DSPEKTRALAB_LIBRAW_OPENMP=ON -DSPEKTRALAB_LIBRAW_SOURCE="$raw_source" \
  -DOpenMP_CXX_FLAGS=-fopenmp -DOpenMP_CXX_LIB_NAMES=omp \
  -DOpenMP_omp_LIBRARY="$sdk/llvm/lib/aarch64-linux-ohos/libomp.a" \
  -DSPEKTRALAB_JPEG_SOURCE="$jpeg_source" \
  -DSPEKTRALAB_SOURCE_DIR="$SPEKTRALAB_SOURCE_DIR" \
  -DSPEKTRALAB_VULKAN_HEADERS="$sdk/sysroot/usr/include" -DSPEKTRALAB_GLSLANG="$GLSLANG"
"$cm" --build "$build" --target spektra_render_fixture spektralab
test -s "$build/libspektralab.so"
test -s "$build/engine/resources/spektrafilm_constants.bin"
