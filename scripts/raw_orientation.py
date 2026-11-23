"""Use LibRaw and the app's shared ArkTS direction rules to check real RAW files."""
import argparse
import hashlib
from io import BytesIO
import json
from pathlib import Path
import struct
import subprocess
import tempfile
from urllib.parse import quote
from urllib.request import Request, urlopen

from PIL import Image, ImageOps, ImageStat
import rawpy

SCRIPTS = Path(__file__).resolve().parent
RULES = 'entry/src/main/ets/common/RawOrientationRules.ets'
HOST = SCRIPTS / 'raw-orientation-host.mjs'
LIBRAW_VERSION = (0, 22, 2)
MIN_SCORE = 0.60
MIN_MARGIN = 0.08


def sha256(path):
    with Path(path).open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def run(*command, text=False):
    return subprocess.check_output(command, text=text, timeout=90)


def require_libraw():
    if rawpy.libraw_version != LIBRAW_VERSION:
        raise ValueError(f'Expected LibRaw {LIBRAW_VERSION}, got {rawpy.libraw_version}')


def pixels(image):
    box = tuple(round(value * limit) for value, limit in
                zip((.14, .14, .86, .86), image.size * 2))
    raster = ImageOps.grayscale(image.crop(box)).resize((88, 88), Image.Resampling.BILINEAR)
    values = raster.get_flattened_data()
    mean = ImageStat.Stat(raster).mean[0]
    length = sum((value - mean) ** 2 for value in values) ** .5
    if length < 1:
        raise ValueError('方向判定需要有明暗差异的画面')
    return [(value - mean) / length for value in values]


def scores(actual, reference):
    expected = pixels(reference)
    copies = {0: actual, 90: actual.transpose(Image.Transpose.ROTATE_90),
              180: actual.transpose(Image.Transpose.ROTATE_180),
              270: actual.transpose(Image.Transpose.ROTATE_270)}
    ranking = sorted(((sum(a * b for a, b in zip(expected, pixels(rotated))), angle)
                      for angle, rotated in copies.items()), reverse=True)
    score, angle = ranking[0]
    margin = score - ranking[1][0]
    aspect, expected_aspect = actual.width / actual.height, reference.width / reference.height
    if angle or score < MIN_SCORE or margin < MIN_MARGIN or abs(aspect / expected_aspect - 1) > .08:
        raise ValueError(f'最佳旋转角 {angle}°，相似度 {score:.3f}，领先 {margin:.3f}，'
                         f'画幅 {actual.width}×{actual.height}，参考 {reference.width}×{reference.height}')
    return min(score, 1), margin


def verify_case(case, working, reference, rules, output, node):
    # LibRaw handles camera metadata. Use a reduced-size image because the
    # remaining test concerns orientation rather than demosaicing fidelity.
    with rawpy.imread(str(working)) as source:
        raw = Image.fromarray(source.postprocess(half_size=True, use_camera_wb=True))
    width, height = map(str, raw.size)
    command = (node, '--no-warnings', str(HOST), str(rules))
    embedded = run(*command, 'preview', width, height, str(working))
    rotation = 0
    if embedded:
        sample_side, jpeg = embedded[0], embedded[1:]
        with tempfile.TemporaryDirectory(prefix='spek-raw-match-', dir='/tmp') as directory:
            preview_path = Path(directory) / 'preview.rgba'
            raw_path = Path(directory) / 'sensor.rgba'
            with Image.open(BytesIO(jpeg)) as photo:
                preview_path.write_bytes(photo.resize((sample_side, sample_side), Image.Resampling.BILINEAR)
                                         .convert('RGBA').tobytes())
            raw_path.write_bytes(raw.convert('RGBA').tobytes())
            rotation = int(run(*command, 'infer', width, height, str(preview_path), str(raw_path)))
    expected_rotation = case.get('huawei_rotation', 0)
    if rotation != expected_rotation:
        raise ValueError(f'App 方向算法返回 {rotation}°，该样片预期 {expected_rotation}°')
    actual = raw.rotate(-rotation, expand=True) if rotation else raw
    actual.thumbnail((640, 640))
    score, margin = scores(actual, reference)
    picture = output / f"{case['id']}-oriented.png"
    actual.save(picture)
    print(f"{case['id']} 通过，补偿 {rotation}°，相似度 {score:.3f}", flush=True)
    return {'id': case['id'], 'input_sha256': case['input_sha256'], 'rotation': rotation,
            'score': round(score, 6), 'margin': round(margin, 6), 'size': list(actual.size),
            'sha256': sha256(picture)}



def write_oriented_fixture(data, orientation, path):
    order = {b'II': '<', b'MM': '>'}.get(data[:2])
    if order is None:
        raise ValueError('Expected a TIFF-based RAW fixture')
    data = bytearray(data)
    offset, = struct.unpack_from(order + 'I', data, 4)
    count, = struct.unpack_from(order + 'H', data, offset)
    for entry in range(offset + 2, offset + 2 + 12 * count, 12):
        if struct.unpack_from(order + 'HHI', data, entry) == (274, 3, 1):
            value, = struct.unpack_from(order + 'H', data, entry + 8)
            if value != 1:
                raise ValueError('Expected the fixture source to be upright')
            struct.pack_into(order + 'H', data, entry + 8, orientation)
            path.write_bytes(data)
            return
    raise ValueError('RAW fixture has no EXIF orientation tag')


def source_file(case, directory):
    path = directory / case['file']
    if not path.is_file():
        url = quote(case['source_url'], safe=":/?&=()%+")
        request = Request(url, headers={'User-Agent': 'SpektraLab-Harmony CI'})
        with urlopen(request, timeout=60) as response:
            body = response.read(48 * 1024 * 1024)
        if hashlib.sha256(body).hexdigest() != case['source_sha256']:
            raise ValueError(f'{path.name}: downloaded SHA-256 does not match')
        path.write_bytes(body)
    if sha256(path) != case['source_sha256']:
        raise ValueError(f'{path.name}: fixture SHA-256 does not match')
    return path


def public_case(case, fixtures, rules, output, node):
    original = source_file(case, fixtures)
    data = original.read_bytes()
    working = original
    orientation = case.get('exif_orientation', 1)
    if orientation != 1:
        working = output / original.name
        write_oriented_fixture(data, orientation, working)
    if sha256(working) != case['input_sha256']:
        raise ValueError(f'{working.name}: test input SHA-256 does not match')
    # The camera JPEG is an independent reference for LibRaw's orientation.
    # Fixed offsets identify each JPEG within the hash-pinned source file.
    with Image.open(BytesIO(data[case['reference_jpeg_offset']:])) as photo:
        reference = photo.convert('RGB')
    if orientation != 1:
        reference = reference.transpose({3: Image.Transpose.ROTATE_180,
                                         6: Image.Transpose.ROTATE_270}[orientation])
    reference.thumbnail((640, 640))
    return verify_case(case, working, reference, rules, output, node)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixtures', type=Path, required=True)
    parser.add_argument('--node', default='node')
    args = parser.parse_args()
    require_libraw()
    args.fixtures.mkdir(parents=True, exist_ok=True)
    cases = json.loads((SCRIPTS / 'fixtures/raw-orientation.json').read_text())
    with tempfile.TemporaryDirectory(prefix='spek-raw-ci-') as directory:
        for case in cases:
            public_case(case, args.fixtures, SCRIPTS.parent / RULES, Path(directory), args.node)


if __name__ == '__main__':
    main()
