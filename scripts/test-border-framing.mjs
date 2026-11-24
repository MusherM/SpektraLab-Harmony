import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const source = readFileSync(new URL('../entry/src/main/ets/common/BorderFraming.ets', import.meta.url), 'utf8');
const { centeredBorderFraming, framingForWindow, framingInSource, resizeBorderFraming } = await import('data:text/javascript;base64,' +
  Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const near = (actual, expected) => assert.ok(Math.abs(actual - expected) < 1e-10, `${actual} != ${expected}`);
const edges = rect => [rect.left, rect.top, rect.right, rect.bottom];
const checkEdges = (actual, expected) => edges(actual).forEach((value, i) => near(value, expected[i]));

const photo = { angle: 0, ratio: 'free', left: 0, top: 0, right: 1, bottom: 1 };
checkEdges(centeredBorderFraming(photo, 1, 2), [.25, 0, .75, 1]);
const ordinaryCrop = { ...photo, left: .1, top: .3, right: .7, bottom: .7 };
const framing = centeredBorderFraming(ordinaryCrop, 1, 2);
checkEdges(framing, [.3, .3, .5, .7]);
checkEdges(resizeBorderFraming(framing, 2, .05, .05), [.2, .1, .6, .9]);
checkEdges(resizeBorderFraming(framing, 10, .05, .05), [.15, 0, .65, 1]);
const minimum = resizeBorderFraming(framing, .01, .03, .05);
near(minimum.right - minimum.left, .03);
near(minimum.bottom - minimum.top, .06);
const offCenter = { ...photo, left: .04, top: .2, right: .44, bottom: .9 };
checkEdges(framingInSource({ ...offCenter, angle: 90 }), [.2, .56, .9, .96]);
checkEdges(framingInSource({ ...offCenter, angle: 180 }), [.56, .1, .96, .8]);
checkEdges(framingInSource({ ...offCenter, angle: 270 }), [.1, .04, .8, .44]);
// The first opening is the editor reference. A differently shaped opening preserves the zoom
// relative to the regular crop while filling its own aperture.
const squareSelection = { ...framing, baseAspect: 3 };
checkEdges(framingForWindow(squareSelection, 1, 1, 2), edges(framing));
checkEdges(framingForWindow(squareSelection, 4, 1, 2),
  edges(centeredBorderFraming(ordinaryCrop, 4, 2)));
const moved = { angle: 90, ratio: '1:1', left: .65, top: .62, right: .95, bottom: .98, baseAspect: 2 };
const second = framingForWindow(moved, 2, 1, 1.2);
near((second.right - second.left) / (second.bottom - second.top) * 1.2, 2);
near(second.right, 1);
near((second.top + second.bottom) / 2, .8);
assert.equal(second.angle, 90);
const wide = framingForWindow({ ...photo, left: .25, right: .75, baseAspect: 3 }, 5, 1, 2);
near(wide.right - wide.left, 1);
near((wide.right - wide.left) / (wide.bottom - wide.top) * 2, 5);
console.log('PASS: border framing, shared multi-opening zoom, bounds, and rotated source mapping');
