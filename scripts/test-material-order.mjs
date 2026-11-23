import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const source = readFileSync(new URL('../entry/src/main/ets/common/MaterialOrder.ets', import.meta.url), 'utf8');
const { materialOrder, moveVisibleMaterial } = await import('data:text/javascript;base64,' +
  Buffer.from(stripTypeScriptTypes(source)).toString('base64'));

assert.deepEqual(materialOrder(['', 'gold', 'portra', 'gold', 'ektar'], []), ['gold', 'portra', 'ektar']);
assert.deepEqual(materialOrder(['gold', 'portra', 'ektar', 'vision'], ['ektar', 'obsolete', 'ektar', 'gold']),
  ['ektar', 'gold', 'portra', 'vision']);

const order = ['endura', 'multigrade', 'vision', 'gallery', 'supra'];
const color = ['endura', 'vision', 'supra'];
assert.deepEqual(moveVisibleMaterial(order, color, 2, 0), ['supra', 'multigrade', 'endura', 'gallery', 'vision']);
assert.deepEqual(moveVisibleMaterial(order, color, 0, 2), ['vision', 'multigrade', 'supra', 'gallery', 'endura']);
assert.equal(moveVisibleMaterial(order, color, 0, 3), order);
assert.equal(moveVisibleMaterial(order, color, 1, 1), order);
console.log('PASS: shared material order, saved order migration and drag with hidden papers');
