import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const source = readFileSync(new URL('../entry/src/main/ets/common/UpdateRules.ets', import.meta.url), 'utf8');
const { automaticUpdateAllowed, UPDATE_SNOOZE_MS } = await import('data:text/javascript;base64,' +
  Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const later = Date.UTC(2026, 10, 17, 10);
const deadline = later + UPDATE_SNOOZE_MS;
assert.equal(UPDATE_SNOOZE_MS, 604800000);
assert.equal(automaticUpdateAllowed(0, later), true);
assert.equal(automaticUpdateAllowed(deadline, later), false);
assert.equal(automaticUpdateAllowed(deadline, later + 6 * 86400000), false);
assert.equal(automaticUpdateAllowed(deadline, deadline - 1), false);
assert.equal(automaticUpdateAllowed(deadline, deadline), true);
assert.equal(automaticUpdateAllowed(deadline, deadline + 1), true);
assert.equal(automaticUpdateAllowed(Number.NaN, later), true);
console.log('PASS: first check, seven-day suppression, exact expiry and invalid stored deadline');

const notesSource = readFileSync(new URL('../entry/src/main/ets/common/ReleaseNotes.ets', import.meta.url), 'utf8');
const { RELEASE_NOTES } = await import('data:text/javascript;base64,' +
  Buffer.from(stripTypeScriptTypes(notesSource)).toString('base64'));
const { app } = JSON.parse(readFileSync(new URL('../AppScope/app.json5', import.meta.url), 'utf8'));
const release = readFileSync(new URL(`../dev/releases/${app.versionName}.md`, import.meta.url), 'utf8');
const expectedNotes = [...release.matchAll(/^- \*\*(.+?)\*\*：(.+)$/gm)]
  .map((match) => ({ title: match[1], text: match[2] }));
assert.ok(expectedNotes.length > 0);
assert.deepEqual(RELEASE_NOTES, expectedNotes);
console.log(`PASS: displayed release notes match version ${app.versionName}`);
