import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const source = readFileSync(new URL('../entry/src/main/ets/common/HomeGalleryRules.ets', import.meta.url), 'utf8');
const { homeDisplayCount, homePageCount, homeCardScale } = await import('data:text/javascript;base64,' +
  Buffer.from(stripTypeScriptTypes(source)).toString('base64'));

for (const [width, count] of [[390, 1], [719, 1], [720, 2], [1034, 2], [1439, 2], [1440, 3], [1920, 3]]) {
  assert.equal(homeDisplayCount(width, 5), count);
  const pages = homePageCount(5, count);
  assert.equal(pages - 1 + count, 5, 'last viewport ends at the last recipe');
}
assert.equal(homeDisplayCount(1920, 2), 2);
assert.equal(homePageCount(2, 2), 1);
assert.equal(Math.min(4, homePageCount(5, 2) - 1), 3, 'widening on the last card keeps the final pair visible');
for (const count of [1, 2, 3]) {
  for (let position = 0; position < count; position++) assert.equal(homeCardScale(position, count), 1);
  assert.equal(homeCardScale(-1, count), 0.955);
  assert.equal(homeCardScale(count, count), 0.955);
}
console.log('PASS: width breakpoints, last viewport, resize clamping and equal scaling for visible cards');
