import type { PhotoGeometry } from './PhotoGeometry';

export function centeredBorderFraming(bounds: PhotoGeometry, aperture: number, fullAspect: number): PhotoGeometry {
  const aspect = aperture / fullAspect;
  const height = Math.min(bounds.bottom - bounds.top, (bounds.right - bounds.left) / aspect);
  const width = height * aspect;
  const left = (bounds.left + bounds.right - width) / 2;
  const top = (bounds.top + bounds.bottom - height) / 2;
  return {angle: bounds.angle, ratio: aperture + ':1', left, top, right: left + width, bottom: top + height};
}

export interface BorderFraming extends PhotoGeometry {
  baseAspect: number;
}

export function framingForWindow(framing: BorderFraming, aperture: number, referenceAperture: number,
  fullAspect: number): PhotoGeometry {
  if (aperture === referenceAperture) return framing;
  const aspect = aperture / fullAspect;
  const referenceHeight = Math.min(1, framing.baseAspect / referenceAperture);
  const windowHeight = Math.min(1, framing.baseAspect / aperture);
  const height = Math.min(1, 1 / aspect,
    (framing.bottom - framing.top) * windowHeight / referenceHeight);
  const width = height * aspect;
  const left = Math.max(0, Math.min(1 - width, (framing.left + framing.right - width) / 2));
  const top = Math.max(0, Math.min(1 - height, (framing.top + framing.bottom - height) / 2));
  return {angle: framing.angle, ratio: aperture + ':1', left, top, right: left + width, bottom: top + height};
}

export function resizeBorderFraming(start: PhotoGeometry, scale: number, minWidth: number, minHeight: number): PhotoGeometry {
  const width = start.right - start.left;
  const height = start.bottom - start.top;
  const maxScale = Math.min(1 / width, 1 / height);
  const minScale = Math.min(1, Math.max(minWidth / width, minHeight / height));
  const size = Math.max(minScale, Math.min(maxScale, scale));
  const w = Math.min(1, width * size);
  const h = Math.min(1, height * size);
  const left = Math.max(0, Math.min(1 - w, (start.left + start.right - w) / 2));
  const top = Math.max(0, Math.min(1 - h, (start.top + start.bottom - h) / 2));
  return {angle: start.angle, ratio: start.ratio, left, top, right: left + w, bottom: top + h};
}

export function framingInSource(framing: PhotoGeometry): PhotoGeometry {
  const g = framing;
  if (g.angle === 90) {
    return {angle: 0, ratio: 'free', left: g.top, top: 1 - g.right, right: g.bottom, bottom: 1 - g.left};
  }
  if (g.angle === 180) {
    return {angle: 0, ratio: 'free', left: 1 - g.right, top: 1 - g.bottom, right: 1 - g.left, bottom: 1 - g.top};
  }
  if (g.angle === 270) {
    return {angle: 0, ratio: 'free', left: 1 - g.bottom, top: g.left, right: 1 - g.top, bottom: g.right};
  }
  return g;
}
