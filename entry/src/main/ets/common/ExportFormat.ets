export function exportMime(format: string, supported: string[]): string {
  const mime = format === 'PNG' ? 'image/png' : format === 'HEIF' ?
    (supported.includes('image/heic') ? 'image/heic' : 'image/heif') : 'image/jpeg';
  if (!supported.includes(mime)) throw new Error('当前设备不支持 ' + format + ' 编码');
  return mime;
}

export function exportExtension(mime: string): string {
  return mime === 'image/png' ? 'png' : mime === 'image/jpeg' ? 'jpg' : 'heic';
}
