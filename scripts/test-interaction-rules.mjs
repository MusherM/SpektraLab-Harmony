import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const source = readFileSync(new URL('../entry/src/main/ets/common/InteractionRules.ets', import.meta.url), 'utf8');
const { horizontalAdjustment, VersionTapSequence } = await import('data:text/javascript;base64,' +
  Buffer.from(stripTypeScriptTypes(source)).toString('base64'));

assert.equal(horizontalAdjustment(15, -260), false);
assert.equal(horizontalAdjustment(15, 260), false);
assert.equal(horizontalAdjustment(30, 30), false);
assert.equal(horizontalAdjustment(0, 0), false);
assert.equal(horizontalAdjustment(80, 20), true);
assert.equal(horizontalAdjustment(-80, -20), true);
const taps = new VersionTapSequence();
for (let i = 0; i < 4; i++) assert.equal(taps.tap(1000 + i * 200), false);
assert.equal(taps.tap(1800), true);
assert.equal(taps.tap(2000), false);
taps.reset();
for (let i = 0; i < 4; i++) assert.equal(taps.tap(3000 + i * 200), false);
assert.equal(taps.tap(5100), false);
for (let i = 0; i < 3; i++) assert.equal(taps.tap(5300 + i * 200), false);
assert.equal(taps.tap(5900), true);
taps.tap(6100); taps.tap(6300); taps.reset();
assert.equal(taps.tap(6500), false);
console.log('PASS: vertical and diagonal gestures rejected; horizontal gestures accepted; five taps, timeout and reset');
