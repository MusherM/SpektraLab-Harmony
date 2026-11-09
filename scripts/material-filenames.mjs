import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { pathToFileURL } from 'node:url';

const source = readFileSync(new URL('../entry/src/main/ets/common/MaterialNames.ets', import.meta.url), 'utf8');
export const { MATERIAL_NAMES, exportTitle, materialPairFromFilename } = await import(
  'data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source)).toString('base64'));

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  for (const filename of process.argv.slice(2)) {
    console.log(JSON.stringify({ filename, materials: materialPairFromFilename(filename) ?? null }));
  }
}
