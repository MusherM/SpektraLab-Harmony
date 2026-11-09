#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
build=${BUILD_DIR:-"$root/.build/native"}
raw="$root/entry/src/main/resources/rawfile"
libs="$root/entry/libs/arm64-v8a"
mkdir -p "$raw" "$libs"
mkdir -p "$raw/licenses/LibRaw"
engine_source=$(sed -n 's/^SPEKTRALAB_SOURCE_DIR:PATH=//p' "$build/CMakeCache.txt")
cp "$engine_source/license/"{LICENSE,SPEKTRAFILM_LICENSE.txt} "$raw/licenses/"
cp "$build/engine/third-party/LibRaw/"{COPYRIGHT,LICENSE.LGPL} "$raw/licenses/LibRaw/"
jpeg_source=$(sed -n 's/^SPEKTRALAB_JPEG_SOURCE:PATH=//p' "$build/CMakeCache.txt")
mkdir -p "$raw/licenses/libjpeg-turbo"
cp "$jpeg_source/"{LICENSE.md,README.ijg} "$raw/licenses/libjpeg-turbo/"
cp "$build/libspektralab.so" "$libs/"
rsync -a --delete "$build/engine/resources/" "$raw/engine/"
(cd "$raw" && find engine -type f | LC_ALL=C sort) > "$raw/engine-files.txt"
jq -n -f "$root/scripts/stock-catalog.jq" "$raw"/engine/profiles/*.json > "$raw/stocks.json"
