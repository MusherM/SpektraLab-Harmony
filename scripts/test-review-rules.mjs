import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const source = readFileSync(new URL('../entry/src/main/ets/common/ReviewRules.ets', import.meta.url), 'utf8');
const { REVIEW_COOLDOWN_MS, canRequestReview, isAlreadyReviewed, recordReviewExport } =
  await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source)).toString('base64'));

const now = 1_800_000_000_000;
const fresh = () => ({
  exportCount: 0, firstExportDay: 0, multipleExportDays: false, lastAttemptAt: 0, lastAttemptVersion: 0,
  alreadyReviewed: false,
});
const progress = fresh();
assert.equal(canRequestReview(progress, now, 13), false);
for (let i = 0; i < 5; i++) recordReviewExport(progress, 20261124);
assert.equal(progress.exportCount, 3);
assert.equal(canRequestReview(progress, now, 13), false);
assert.equal(recordReviewExport(progress, 20261125), true);
assert.equal(canRequestReview(progress, now, 13), true);
assert.equal(recordReviewExport(progress, 20261125), false);

const twoExports = fresh();
recordReviewExport(twoExports, 20261124);
recordReviewExport(twoExports, 20261125);
assert.equal(canRequestReview(twoExports, now, 13), false);

assert.equal(REVIEW_COOLDOWN_MS, 30 * 86400000);
progress.lastAttemptAt = now;
progress.lastAttemptVersion = 13;
assert.equal(canRequestReview(progress, now + REVIEW_COOLDOWN_MS - 1, 14), false);
assert.equal(canRequestReview(progress, now + REVIEW_COOLDOWN_MS, 14), true);
assert.equal(canRequestReview(progress, now + 2 * REVIEW_COOLDOWN_MS, 13), false);
assert.equal(canRequestReview(progress, now + 2 * REVIEW_COOLDOWN_MS, 12), false);
assert.equal(isAlreadyReviewed(1021500007), true);
assert.equal(isAlreadyReviewed(1021500009), true);
assert.equal(isAlreadyReviewed(1021500008), false);
assert.equal(isAlreadyReviewed(1021500006), false);
progress.alreadyReviewed = true;
assert.equal(canRequestReview(progress, now + 20 * REVIEW_COOLDOWN_MS, 30), false);

console.log('PASS: review eligibility, version gate, cooldown and prior review');
