import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';

const SAMPLE_SIDE = 32;

export function orientedPixelMap(rgba: ArrayBuffer, width: number, height: number, rotation: number): image.PixelMap {
  const map = image.createPixelMapSync(rgba, { size: { width, height }, editable: rotation !== 0,
    srcPixelFormat: image.PixelMapFormat.RGBA_8888, pixelFormat: image.PixelMapFormat.RGBA_8888 });
  try {
    if (rotation) map.rotateSync(rotation);
    return map;
  } catch (err) {
    map.release();
    throw new Error((err as BusinessError).message ?? String(err));
  }
}

function readAt(fd: number, offset: number, length: number): ArrayBuffer {
  const buffer = new ArrayBuffer(length);
  if (fs.readSync(fd, buffer, { offset, length }) !== length) throw new Error('DNG preview is truncated');
  return buffer;
}

// Some Huawei DNGs bake the camera orientation into the primary JPEG preview
// and mark it as upright, while their RAW subimage remains in sensor coordinates.
function huaweiPreview(fd: number, width: number, height: number): ArrayBuffer | undefined {
  const header = new DataView(readAt(fd, 0, 8));
  const order = header.getUint16(0);
  const little = order === 0x4949;
  if ((!little && order !== 0x4d4d) || header.getUint16(2, little) !== 42) return undefined;
  const offset = header.getUint32(4, little);
  const count = new DataView(readAt(fd, offset, 2)).getUint16(0, little);
  if (!count || count > 512) return undefined;
  const entries = new DataView(readAt(fd, offset + 2, count * 12));
  const tags = new Map<number, number>();
  let huawei = false;
  let dng = false;
  for (let i = 0; i < count * 12; i += 12) {
    const tag = entries.getUint16(i, little);
    const type = entries.getUint16(i + 2, little);
    const length = entries.getUint32(i + 4, little);
    const value = entries.getUint32(i + 8, little);
    if (tag === 271 && type === 2 && length === 7) {
      const make = new Uint8Array(readAt(fd, value, length));
      huawei = String.fromCharCode(make[0], make[1], make[2], make[3], make[4], make[5]) === 'HUAWEI' && make[6] === 0;
    }
    if (tag === 50706 && type === 1 && length === 4) dng = true;
    if (length === 1 && (type === 3 || type === 4)) {
      tags.set(tag, type === 3 ? entries.getUint16(i + 8, little) : value);
    }
  }
  if (!huawei || !dng || tags.get(254) !== 1 || tags.get(259) !== 7 || tags.get(274) !== 1) return undefined;
  const previewWidth = tags.get(256) ?? 0;
  const previewHeight = tags.get(257) ?? 0;
  if (!previewWidth || !previewHeight || tags.get(278) !== previewHeight ||
    (previewWidth - previewHeight) * (width - height) >= 0 ||
    Math.abs(previewWidth * width - previewHeight * height) > previewHeight * height * 0.02) return undefined;
  const start = tags.get(273) ?? 0;
  const length = tags.get(279) ?? 0;
  if (start < 8 || length < 4 || length > 16 * 1024 * 1024) return undefined;
  const bytes = readAt(fd, start, length);
  return new DataView(bytes).getUint16(0) === 0xffd8 ? bytes : undefined;
}

function luminance(data: Uint8Array, index: number): number {
  return 0.2126 * data[index] + 0.7152 * data[index + 1] + 0.0722 * data[index + 2];
}

function agreement(preview: Uint8Array, raw: Uint8Array, width: number, height: number,
  clockwise: boolean): number {
  let sumA = 0, sumB = 0, sumAA = 0, sumBB = 0, sumAB = 0;
  for (let y = 0; y < SAMPLE_SIDE; y++) {
    for (let x = 0; x < SAMPLE_SIDE; x++) {
      const sx = Math.floor((y + 0.5) * width / SAMPLE_SIDE);
      const sy = Math.floor((x + 0.5) * height / SAMPLE_SIDE);
      const rx = clockwise ? sx : width - 1 - sx;
      const ry = clockwise ? height - 1 - sy : sy;
      const a = luminance(preview, (y * SAMPLE_SIDE + x) * 4);
      const b = luminance(raw, (ry * width + rx) * 4);
      sumA += a;
      sumB += b;
      sumAA += a * a;
      sumBB += b * b;
      sumAB += a * b;
    }
  }
  const count = SAMPLE_SIDE * SAMPLE_SIDE;
  const varianceA = sumAA - sumA * sumA / count;
  const varianceB = sumBB - sumB * sumB / count;
  if (varianceA < count * 4 || varianceB < count * 4) return 0;
  return (sumAB - sumA * sumB / count) / Math.sqrt(varianceA * varianceB);
}

export async function rawPreviewRotation(fd: number, display: ArrayBuffer, width: number,
  height: number): Promise<number> {
  try {
    const jpeg = huaweiPreview(fd, width, height);
    if (!jpeg) return 0;
    const source = image.createImageSource(jpeg);
    try {
      const map = await source.createPixelMap({ desiredSize: { width: SAMPLE_SIDE, height: SAMPLE_SIDE },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
      try {
        const info = await map.getImageInfo();
        if (info.size.width !== SAMPLE_SIDE || info.size.height !== SAMPLE_SIDE) return 0;
        const bytes = new ArrayBuffer(SAMPLE_SIDE * SAMPLE_SIDE * 4);
        await map.readPixelsToBuffer(bytes);
        const preview = new Uint8Array(bytes);
        const raw = new Uint8Array(display);
        const clockwise = agreement(preview, raw, width, height, true);
        const counterclockwise = agreement(preview, raw, width, height, false);
        if (Math.max(clockwise, counterclockwise) < 0.45 || Math.abs(clockwise - counterclockwise) < 0.12) return 0;
        return clockwise > counterclockwise ? 90 : 270;
      } finally { await map.release(); }
    } finally { await source.release(); }
  } catch (_) { return 0; }
}
