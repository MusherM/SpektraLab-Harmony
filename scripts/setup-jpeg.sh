#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
deps=${1:-"$root/.build/deps"}
mkdir -p "$deps"
deps=$(cd "$deps" && pwd)
version=3.2.1
archive="$deps/libjpeg-turbo-$version.tar.gz"
source="$deps/libjpeg-turbo-$version"
sha=6f5819c51649bce2571a23b1b0cd41eae2f57fc3f8908c7ec9e7047efb65ca13
if [[ ! -f "$archive" ]]; then
    curl -fL --connect-timeout 20 --max-time 300 \
        "https://codeload.github.com/libjpeg-turbo/libjpeg-turbo/tar.gz/refs/tags/$version" -o "$archive.partial"
    [[ $(shasum -a 256 "$archive.partial" | cut -d' ' -f1) == "$sha" ]]
    mv "$archive.partial" "$archive"
fi
[[ $(shasum -a 256 "$archive" | cut -d' ' -f1) == "$sha" ]]
if [[ ! -d "$source" ]]; then tar -xzf "$archive" -C "$deps"; fi
uv run --no-project python - "$archive" "$deps" <<'PY'
import hashlib, pathlib, sys, tarfile
with tarfile.open(sys.argv[1]) as archive:
    expected = set()
    for member in archive.getmembers():
        if member.isfile():
            path = pathlib.Path(sys.argv[2]) / member.name
            expected.add(path)
            if not path.is_file() or hashlib.sha256(path.read_bytes()).digest() != hashlib.sha256(archive.extractfile(member).read()).digest():
                sys.exit(f"libjpeg-turbo source mismatch: {path}")
    source = pathlib.Path(sys.argv[2]) / archive.getmembers()[0].name.split('/')[0]
    if {p for p in source.rglob('*') if p.is_file()} != expected:
        sys.exit('Unexpected files in libjpeg-turbo source')
PY
echo "$source"
