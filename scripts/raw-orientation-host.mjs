import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const [rulesPath, action, width, height, ...paths] = process.argv.slice(2);
const source = stripTypeScriptTypes(readFileSync(rulesPath, 'utf8'));
const rules = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
if (action === 'preview') {
  const file = readFileSync(paths[0]);
  const jpeg = rules.huaweiPreview((offset, length) => {
    if (offset < 0 || length < 0 || offset + length > file.length) throw new RangeError('DNG preview is truncated');
    return file.buffer.slice(file.byteOffset + offset, file.byteOffset + offset + length);
  }, Number(width), Number(height));
  if (jpeg) process.stdout.write(Buffer.concat([Buffer.from([rules.SAMPLE_SIDE]), Buffer.from(jpeg)]));
} else if (action === 'infer') {
  const [preview, raw] = paths.map(path => readFileSync(path));
  if (preview.length !== rules.SAMPLE_SIDE ** 2 * 4 || raw.length !== Number(width) * Number(height) * 4) {
    throw new Error('Orientation sample dimensions do not match');
  }
  process.stdout.write(String(rules.inferHuaweiRotation(preview, raw, Number(width), Number(height))));
} else {
  throw new Error('Unknown RAW orientation action');
}
