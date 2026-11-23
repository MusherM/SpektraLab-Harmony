import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const source = readFileSync(new URL('../entry/src/main/ets/common/RawOrientationRules.ets', import.meta.url), 'utf8');
const { huaweiPreview, inferHuaweiRotation, SAMPLE_SIDE } = await import(
  'data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source)).toString('base64'));

const camera = new ArrayBuffer(256);
const bytes = new Uint8Array(camera);
const view = new DataView(camera);
view.setUint16(0, 0x4949);
view.setUint16(2, 42, true);
view.setUint32(4, 8, true);
const tags = [
  [254, 4, 1, 1], [256, 4, 1, 48], [257, 4, 1, 64], [259, 3, 1, 7], [271, 2, 7, 180],
  [273, 4, 1, 200], [274, 3, 1, 1], [278, 4, 1, 64], [279, 4, 1, 4], [50706, 1, 4, 1]
];
view.setUint16(8, tags.length, true);
tags.forEach(([tag, type, length, value], index) => {
  const offset = 10 + index * 12;
  view.setUint16(offset, tag, true);
  view.setUint16(offset + 2, type, true);
  view.setUint32(offset + 4, length, true);
  view.setUint32(offset + 8, value, true);
});
bytes.set(Buffer.from('HUAWEI\0'), 180);
const jpeg = [255, 216, 255, 217];
bytes.set(jpeg, 200);
const read = (offset, length) => camera.slice(offset, offset + length);
assert.deepEqual([...new Uint8Array(huaweiPreview(read, 64, 48))], jpeg);
assert.equal(huaweiPreview(read, 48, 64), undefined);
bytes[180] = 88;
assert.equal(huaweiPreview(read, 64, 48), undefined);

const width = 64;
const height = 48;
const raw = new Uint8Array(width * height * 4);
for (let y = 0; y < height; y++) {
  for (let x = 0; x < width; x++) {
    const value = (x < 24 && y < 17 ? 195 : 30) + (x > 47 && y < 33 ? 40 : 0) + (y > 31 ? 15 : 0);
    raw.fill(value, (y * width + x) * 4, (y * width + x) * 4 + 4);
  }
}

function rotatedSample(clockwise) {
  const rotated = new Uint8Array(raw.length);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const from = (y * width + x) * 4;
      const to = clockwise ? (x * height + (height - 1 - y)) * 4 : ((width - 1 - x) * height + y) * 4;
      rotated.set(raw.subarray(from, from + 4), to);
    }
  }
  const sample = new Uint8Array(SAMPLE_SIDE ** 2 * 4);
  for (let y = 0; y < SAMPLE_SIDE; y++) {
    for (let x = 0; x < SAMPLE_SIDE; x++) {
      const from = (Math.floor((y + 0.5) * width / SAMPLE_SIDE) * height +
        Math.floor((x + 0.5) * height / SAMPLE_SIDE)) * 4;
      sample.set(rotated.subarray(from, from + 4), (y * SAMPLE_SIDE + x) * 4);
    }
  }
  return sample;
}

assert.equal(inferHuaweiRotation(rotatedSample(true), raw, width, height), 90);
assert.equal(inferHuaweiRotation(rotatedSample(false), raw, width, height), 270);
assert.equal(inferHuaweiRotation(new Uint8Array(SAMPLE_SIDE ** 2 * 4), raw, width, height), 0);
console.log('PASS: Huawei DNG metadata, clockwise and counterclockwise compensation, and low-contrast fallback');
