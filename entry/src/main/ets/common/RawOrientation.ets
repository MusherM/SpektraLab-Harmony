import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';

import { huaweiPreview, inferHuaweiRotation, SAMPLE_SIDE } from './RawOrientationRules';

export function orientedPixelMap(rgba: ArrayBuffer, width: number, height: number, rotation: number, editable: boolean = false): image.PixelMap {
  const map = image.createPixelMapSync(rgba, { size: { width, height }, editable: editable || rotation !== 0,
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

export async function rawPreviewRotation(fd: number, display: ArrayBuffer, width: number,
  height: number): Promise<number> {
  try {
    const jpeg = huaweiPreview((offset: number, length: number) => readAt(fd, offset, length), width, height);
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
        return inferHuaweiRotation(new Uint8Array(bytes), new Uint8Array(display), width, height);
      } finally { await map.release(); }
    } finally { await source.release(); }
  } catch (_) { return 0; }
}
