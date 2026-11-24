import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const source = readFileSync(new URL('../entry/src/main/ets/common/MaterialPagerRules.ets', import.meta.url), 'utf8');
const { MATERIAL_PAGER_INSET, materialDotWindowStart, materialDotSize, materialDotX, materialDotPageAt,
  materialPagerWidth, materialExpandedPagerWidth, materialExpandedPagePosition, materialFanPlacement } =
  await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source)).toString('base64'));

for (let count = 2; count <= 7; count++) {
  const width = materialPagerWidth(count);
  assert.ok(width > materialPagerWidth(count - 1));
  assert.ok(materialDotX(0, count, 0, width) >= 12);
  assert.ok(materialDotX(count - 1, count, 0, width) <= width - 12);
}
for (const count of [8, 10, 26, 42]) assert.equal(materialPagerWidth(count), materialPagerWidth(7));
assert.equal(materialExpandedPagePosition(100, 147, 0, 294, 1), 0);

for (const viewport of [280, 342, 440]) {
  const width = materialExpandedPagerWidth(viewport);
  const margin = (viewport - width) / 2;
  const first = margin + MATERIAL_PAGER_INSET;
  const last = viewport - first;
  assert.equal(margin, 24);
  assert.ok(width > materialPagerWidth(42));
  for (const count of [2, 10, 26, 42]) {
    for (const startIndex of [0, Math.floor(count / 2), count - 1]) {
      for (const startX of [viewport / 2 - 60, viewport / 2, viewport / 2 + 60]) {
        const position = (x) => materialExpandedPagePosition(x, startX, startIndex, viewport, count);
        assert.equal(position(first), 0);
        assert.equal(position(last), count - 1);
        assert.equal(position(startX), startIndex);
        assert.equal(position((first + startX) / 2), startIndex / 2);
        assert.equal(position((last + startX) / 2), (startIndex + count - 1) / 2);
        const reached = new Set();
        for (let x = first; x <= last; x++) reached.add(Math.round(position(x)));
        assert.deepEqual([...reached], Array.from({ length: count }, (_, index) => index));
      }
    }
  }
}

for (const [index, first, shrinksLeft, shrinksRight] of [
  [0, 0, false, true],
  [12, 9, true, true],
  [25, 19, true, false],
]) {
  const width = materialPagerWidth(26);
  assert.equal(materialDotWindowStart(26, index), first);
  assert.equal(materialDotSize(first, first, 7, 26), shrinksLeft ? 3 : 6);
  assert.equal(materialDotSize(first + 1, first, 7, 26), shrinksLeft ? 4.5 : 6);
  assert.equal(materialDotSize(first + 5, first, 7, 26), shrinksRight ? 4.5 : 6);
  assert.equal(materialDotSize(first + 6, first, 7, 26), shrinksRight ? 3 : 6);
  for (let slot = 0; slot < 7; slot++) {
    const page = first + slot;
    assert.equal(materialDotPageAt(materialDotX(page, 26, index, width), width, 26, index), page);
  }
}
assert.equal(materialDotX(0, 1, 0, materialPagerWidth(1)), materialPagerWidth(1) / 2);
assert.equal(materialDotPageAt(10, materialPagerWidth(1), 1, 0), 0);

const current = materialFanPlacement(0, 73, true);
const neighbor = materialFanPlacement(1, 73, false);
const far = materialFanPlacement(2, 73, false);
assert.ok(current.scale > neighbor.scale && neighbor.scale > far.scale);
assert.ok(current.y < neighbor.y && neighbor.y < far.y);
assert.ok(current.order > neighbor.order && neighbor.order > far.order);
assert.equal(current.blur, 0);
assert.equal(neighbor.blur, 0);
assert.ok(far.blur > 0);
assert.equal(materialFanPlacement(-2, 73, false).x, -far.x);
assert.equal(materialFanPlacement(-2, 73, false).angle, -far.angle);

console.log('PASS: complete material range, raised selection and focal depth');
