import { image } from '@kit.ImageKit';
import { straightPhotoPixels } from './PhotoPixels';
import { orientedPixelMap } from './RawOrientation';

export interface PhotoGeometry {
  angle: number;
  ratio: string;
  left: number;
  top: number;
  right: number;
  bottom: number;
}

export function fullPhoto(): PhotoGeometry {
  return { angle: 0, ratio: 'free', left: 0, top: 0, right: 1, bottom: 1 };
}

export function hasCrop(geometry: PhotoGeometry): boolean {
  return geometry.ratio.includes(':') || geometry.left > 0 || geometry.top > 0 ||
    geometry.right < 1 || geometry.bottom < 1;
}

export function turnPhoto(g: PhotoGeometry, clockwise: boolean): PhotoGeometry {
  const parts = g.ratio.split(':');
  const ratio = parts.length === 2 ? parts[1] + ':' + parts[0] : g.ratio;
  if (clockwise) {
    return { angle: (g.angle + 90) % 360, ratio, left: 1 - g.bottom, top: g.left, right: 1 - g.top, bottom: g.right };
  }
  return { angle: (g.angle + 270) % 360, ratio, left: g.top, top: 1 - g.right, right: g.bottom, bottom: 1 - g.left };
}

export function lockedRatio(ratio: string, imageAspect: number): number {
  if (ratio === 'free') return 0;
  if (ratio === 'original') return 1;
  const parts = ratio.split(':');
  return Number(parts[0]) / Number(parts[1]) / imageAspect;
}

export function selectRatio(g: PhotoGeometry, ratio: string, imageAspect: number): PhotoGeometry {
  const next: PhotoGeometry = {
    angle: g.angle, ratio, left: g.left, top: g.top, right: g.right, bottom: g.bottom
  };
  if (ratio === g.ratio || ratio === 'free') return next;
  const aspect = lockedRatio(ratio, imageAspect);
  const area = (g.right - g.left) * (g.bottom - g.top);
  const height = Math.min(1, 1 / aspect, Math.sqrt(area / aspect));
  const width = height * aspect;
  next.left = Math.max(0, Math.min(1 - width, (g.left + g.right - width) / 2));
  next.top = Math.max(0, Math.min(1 - height, (g.top + g.bottom - height) / 2));
  next.right = Math.min(1, next.left + width);
  next.bottom = Math.min(1, next.top + height);
  return next;
}

function commonDivisor(a: number, b: number): number {
  while (b !== 0) {
    const remainder = a % b;
    a = b;
    b = remainder;
  }
  return a;
}

export function cropRegion(g: PhotoGeometry, width: number, height: number): image.Region {
  const x = Math.min(width - 1, Math.round(g.left * width));
  const y = Math.min(height - 1, Math.round(g.top * height));
  const right = Math.max(x + 1, Math.round(g.right * width));
  const bottom = Math.max(y + 1, Math.round(g.bottom * height));
  const cropWidth = right - x;
  const cropHeight = bottom - y;
  const parts = g.ratio.split(':');
  const original = g.ratio === 'original';
  if (original || parts.length === 2) {
    const divisor = original ? commonDivisor(width, height) : 1;
    const unitWidth = original ? width / divisor : Number(parts[0]);
    const unitHeight = original ? height / divisor : Number(parts[1]);
    const units = Math.floor(Math.min(cropWidth / unitWidth, cropHeight / unitHeight));
    const exactWidth = unitWidth * units;
    const exactHeight = unitHeight * units;
    // Keep rounded bounds when matching the source ratio would trim more than four pixels.
    if (units >= 1 && (!original || Math.max(cropWidth - exactWidth, cropHeight - exactHeight) <= 4)) {
      return {
        x: x + Math.floor((cropWidth - exactWidth) / 2),
        y: y + Math.floor((cropHeight - exactHeight) / 2),
        size: { width: exactWidth, height: exactHeight }
      };
    }
  }
  return { x, y, size: { width: cropWidth, height: cropHeight } };
}

export function geometryMap(rgba: ArrayBuffer, width: number, height: number, orientation: number,
  geometry: PhotoGeometry): image.PixelMap {
  const crop = hasCrop(geometry);
  const map = orientedPixelMap(rgba, width, height, (orientation + geometry.angle) % 360, crop);
  try {
    if (crop) {
      const size = map.getImageInfoSync().size;
      const region = cropRegion(geometry, size.width, size.height);
      if (region.size.width !== size.width || region.size.height !== size.height) map.cropSync(region);
    }
    return map;
  } catch (err) {
    map.release();
    throw new Error(String(err));
  }
}

export function editedPhoto(photo: image.PixelMap, geometry: PhotoGeometry): image.PixelMap | undefined {
  if (!geometry.angle && !hasCrop(geometry)) return undefined;
  const info = photo.getImageInfoSync();
  const rgba = new ArrayBuffer(info.size.width * info.size.height * 4);
  photo.readPixelsToBufferSync(rgba);
  straightPhotoPixels(rgba, info.alphaType === image.AlphaType.PREMUL);
  return geometryMap(rgba, info.size.width, info.size.height, 0, geometry);
}
