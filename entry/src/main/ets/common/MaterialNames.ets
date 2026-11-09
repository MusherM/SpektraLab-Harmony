export interface MaterialName {
  id: string;
  token: string;
  paper: boolean;
}

export interface MaterialPair {
  film: string;
  paper: string;
}

// Persisted filename tokens: keep existing values stable when display names change.
export const MATERIAL_NAMES: MaterialName[] = [
  { id: 'cinestill_800t', token: 'cinestill800t', paper: false },
  { id: 'fujifilm_c200', token: 'fujifilmC200', paper: false },
  { id: 'fujifilm_crystal_archive_typeii', token: 'fujifilmCrystalArchiveTypeii', paper: true },
  { id: 'fujifilm_neopan_acros_100_ii', token: 'fujifilmNeopanAcros100Ii', paper: false },
  { id: 'fujifilm_pro_400h', token: 'fujifilmPro400h', paper: false },
  { id: 'fujifilm_provia_100f', token: 'fujifilmProvia100f', paper: false },
  { id: 'fujifilm_velvia_100', token: 'fujifilmVelvia100', paper: false },
  { id: 'fujifilm_xtra_400', token: 'fujifilmXtra400', paper: false },
  { id: 'ilford_hp5_plus_400', token: 'ilfordHp5Plus400', paper: false },
  { id: 'ilford_multigrade_iv_rc', token: 'ilfordMultigradeIvRc', paper: true },
  { id: 'kodak_2383', token: 'kodakVision2383', paper: true },
  { id: 'kodak_2393', token: 'kodakVisionPremier2393', paper: true },
  { id: 'kodak_ektachrome_100', token: 'kodakEktachrome100', paper: false },
  { id: 'kodak_ektacolor_edge', token: 'ektacolorEdge', paper: true },
  { id: 'kodak_ektar_100', token: 'kodakEktar100', paper: false },
  { id: 'kodak_endura_premier', token: 'enduraPremier', paper: true },
  { id: 'kodak_gold_200', token: 'kodakGold200', paper: false },
  { id: 'kodak_kodachrome_64', token: 'kodakKodachrome64', paper: false },
  { id: 'kodak_portra_160', token: 'kodakPortra160', paper: false },
  { id: 'kodak_portra_400', token: 'kodakPortra400', paper: false },
  { id: 'kodak_portra_800', token: 'kodakPortra800', paper: false },
  { id: 'kodak_portra_800_push1', token: 'kodakPortra800Push1', paper: false },
  { id: 'kodak_portra_800_push2', token: 'kodakPortra800Push2', paper: false },
  { id: 'kodak_portra_endura', token: 'portraEndura', paper: true },
  { id: 'kodak_supra_endura', token: 'supraEndura', paper: true },
  { id: 'kodak_tmax_100', token: 'kodakTmax100', paper: false },
  { id: 'kodak_tri_x_400', token: 'kodakTriX400', paper: false },
  { id: 'kodak_ultra_endura', token: 'ultraEndura', paper: true },
  { id: 'kodak_ultramax_400', token: 'kodakUltramax400', paper: false },
  { id: 'kodak_verita_200d', token: 'kodakVerita200d', paper: false },
  { id: 'kodak_vision3_200t', token: 'kodakVision3200t', paper: false },
  { id: 'kodak_vision3_250d', token: 'kodakVision3250d', paper: false },
  { id: 'kodak_vision3_500t', token: 'kodakVision3500t', paper: false },
  { id: 'kodak_vision3_50d', token: 'kodakVision350d', paper: false }
];

export function materialPairFromFilename(filename: string): MaterialPair | undefined {
  const stem = filename.replace(/\.[^.]+$/, '');
  const parts = stem.split('_');
  if (parts.length < 3) return undefined;
  const film = MATERIAL_NAMES.find((item: MaterialName) => !item.paper && item.token === parts[parts.length - 2]);
  const paper = MATERIAL_NAMES.find((item: MaterialName) => item.paper && item.token === parts[parts.length - 1]);
  return film && paper ? { film: film.id, paper: paper.id } : undefined;
}

export function exportTitle(filename: string, filmId: string, paperId: string): string {
  const film = MATERIAL_NAMES.find((item: MaterialName) => !item.paper && item.id === filmId);
  const paper = MATERIAL_NAMES.find((item: MaterialName) => item.paper && item.id === paperId);
  if (!film || !paper) throw new Error('材料文件名映射缺失');
  let stem = filename.replace(/\.[^.]+$/, '');
  if (materialPairFromFilename(filename)) stem = stem.split('_').slice(0, -2).join('_');
  stem = stem.replace(/[\\/:*?"'`<>|{}\[\]\x00-\x1f]/g, '_').replace(/\.\.+/g, '_').trim();
  if (!stem) stem = 'photo';
  const suffix = '_' + film.token + '_' + paper.token;
  // Leave room for the extension within the media library's filename limit.
  let base = '';
  let bytes = 0;
  for (let i = 0; i < stem.length; i++) {
    const code = stem.charCodeAt(i);
    const surrogate = code >= 0xD800 && code <= 0xDBFF && i + 1 < stem.length;
    const length = surrogate ? 4 : code < 0x80 ? 1 : code < 0x800 ? 2 : 3;
    if (bytes + length > 240 - suffix.length) break;
    base += stem.charAt(i);
    if (surrogate) base += stem.charAt(++i);
    bytes += length;
  }
  return base + suffix;
}
