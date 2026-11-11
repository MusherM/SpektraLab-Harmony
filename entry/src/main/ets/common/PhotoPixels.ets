// PixelMap decoding returns premultiplied channels; buffer construction expects
// straight channels and applies premultiplication for display itself.
export function straightPhotoPixels(buffer: ArrayBuffer, premultiplied: boolean): void {
  if (!premultiplied) return;
  const rgba = new Uint8Array(buffer);
  for (let i = 0; i < rgba.length; i += 4) {
    const alpha = rgba[i + 3];
    if (alpha === 0 || alpha === 255) continue;
    for (let c = 0; c < 3; ++c) {
      rgba[i + c] = Math.min(255, Math.round(rgba[i + c] * 255 / alpha));
    }
  }
}
