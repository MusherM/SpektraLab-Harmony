import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { MATERIAL_NAMES, exportTitle, materialPairFromFilename } from './material-filenames.mjs';

const stocks = JSON.parse(readFileSync(new URL('../entry/src/main/resources/rawfile/stocks.json', import.meta.url)));
assert.deepEqual(MATERIAL_NAMES.map(x => x.id).sort(), stocks.map(x => x.id).sort());
assert.equal(new Set(MATERIAL_NAMES.map(x => x.token)).size, stocks.length);
for (const stock of stocks) assert.equal(MATERIAL_NAMES.find(x => x.id === stock.id).paper, stock.paper);
const film = 'kodak_gold_200', paper = 'kodak_supra_endura';
assert.equal(exportTitle('pic.dng', film, paper), 'pic_kodakGold200_supraEndura');
assert.equal(exportTitle('海边_原图.CR3', film, paper), '海边_原图_kodakGold200_supraEndura');
assert.equal(exportTitle('pic_kodakPortra400_portraEndura.jpg', film, paper), 'pic_kodakGold200_supraEndura');
assert.equal(exportTitle('pic_kodakGold200_supraEndura.jpg', film, paper), 'pic_kodakGold200_supraEndura');
assert.equal(materialPairFromFilename('pic_unknown_supraEndura.jpg'), undefined);
assert.equal(materialPairFromFilename('pic_supraEndura_kodakGold200.jpg'), undefined);
assert.throws(() => exportTitle('pic.jpg', 'unknown', paper));
assert.ok(!/[\\/:*?"'`<>|{}\[\]]/.test(exportTitle('a:b?c[1].dng', film, paper)));
assert.ok(Buffer.byteLength(exportTitle('风景🌊'.repeat(100) + '.dng', film, paper) + '.jpeg') <= 245);
let pairs = 0;
for (const f of MATERIAL_NAMES.filter(x => !x.paper)) {
  for (const p of MATERIAL_NAMES.filter(x => x.paper)) {
    for (const extension of ['jpg', 'png', 'heic']) {
      const name = exportTitle('sample_01.NEF', f.id, p.id) + '.' + extension;
      assert.deepEqual(materialPairFromFilename(name), {film: f.id, paper: p.id});
    }
    pairs++;
  }
}
console.log(`PASS: ${stocks.length} materials, ${pairs} pairs × 3 formats, original names, replacement, invalid names and UTF-8 length`);
