import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const source = readFileSync(new URL('../entry/src/main/ets/common/ExportAttempt.ets', import.meta.url), 'utf8');
const { ExportAttempt } = await import('data:text/javascript;base64,' +
  Buffer.from(stripTypeScriptTypes(source)).toString('base64'));

const cancelled = new ExportAttempt();
assert.equal(cancelled.requestConfirmation(), true);
assert.equal(cancelled.requestConfirmation(), false);
let entered = false;
const result = cancelled.beginCommit().then(value => {
  entered = true;
  return value;
});
await Promise.resolve();
assert.equal(entered, false);
cancelled.resolveConfirmation(true);
assert.equal(await result, false);
assert.equal(cancelled.committing, false);

const kept = new ExportAttempt();
assert.equal(kept.requestConfirmation(), true);
const continued = kept.beginCommit();
kept.resolveConfirmation(false);
assert.equal(await continued, true);
assert.equal(kept.committing, true);
assert.equal(kept.requestConfirmation(), false);

const next = new ExportAttempt();
assert.equal(await next.beginCommit(), true);
assert.equal(cancelled.cancelled, true);

console.log('PASS: export confirmation, cancellation and commit boundary');
