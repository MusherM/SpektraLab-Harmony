import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const source = readFileSync(new URL('../entry/src/main/ets/common/PhotoPixels.ets', import.meta.url), 'utf8');
const { straightPhotoPixels } = await import('data:text/javascript;base64,' +
  Buffer.from(stripTypeScriptTypes(source)).toString('base64'));

// Reconstructing the preview must preserve each decoded premultiplied channel.
for (let alpha = 1; alpha <= 255; ++alpha) {
  for (let channel = 0; channel <= alpha; ++channel) {
    const pixels = new Uint8Array([channel, channel, channel, alpha]);
    straightPhotoPixels(pixels.buffer, true);
    assert.equal(Math.round(pixels[0] * alpha / 255), channel);
    assert.equal(pixels[3], alpha);
  }
}
const straight = new Uint8Array([200, 100, 50, 128, 0, 0, 0, 0]);
const original = straight.slice();
straightPhotoPixels(straight.buffer, false);
assert.deepEqual(straight, original);
straightPhotoPixels(new Uint8Array([0, 0, 0, 0]).buffer, true);
console.log('PASS: all 32,895 valid alpha/channel pairs preserve displayed brightness; straight pixels stay unchanged');
