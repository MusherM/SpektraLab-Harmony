import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const source = readFileSync(new URL('../entry/src/main/ets/common/ExportQuality.ets', import.meta.url), 'utf8');
const {
  EXPORT_QUALITY_OPTIONS,
  exportQualityDescription,
  exportQualityLabel,
  isFastExport,
  normalizeExportQuality,
} = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source)).toString('base64'));

assert.deepEqual(EXPORT_QUALITY_OPTIONS, ['HIGH', 'FAST']);
assert.equal(normalizeExportQuality('HIGH'), 'HIGH');
assert.equal(normalizeExportQuality('FAST'), 'FAST');
assert.equal(normalizeExportQuality('unknown'), 'HIGH');
assert.equal(normalizeExportQuality(''), 'HIGH');
assert.equal(isFastExport('HIGH'), false);
assert.equal(isFastExport('FAST'), true);
assert.equal(isFastExport('invalid'), false);
assert.equal(exportQualityLabel('HIGH'), '高质量');
assert.equal(exportQualityLabel('FAST'), '快速');
assert.ok(exportQualityDescription('HIGH').includes('无损'));
assert.ok(exportQualityDescription('FAST').includes('耗时'));

console.log('PASS: export quality normalization, labels, and descriptions');
