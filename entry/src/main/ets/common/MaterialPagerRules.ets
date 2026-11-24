export interface FanPlacement {
  x: number;
  y: number;
  angle: number;
  scale: number;
  opacity: number;
  blur: number;
  order: number;
}

export const MATERIAL_PAGER_INSET: number = 12;
export const MATERIAL_PAGER_VISIBLE_DOTS: number = 7;
export const MATERIAL_PAGER_ACTIVE_WIDTH: number = 17;
const MATERIAL_PAGER_DOT_GAP: number = 9;
const MATERIAL_PAGER_SIDE_MARGIN: number = 24;

export function materialPagerWidth(count: number): number {
  const visible = Math.max(1, Math.min(count, MATERIAL_PAGER_VISIBLE_DOTS));
  return Math.max(40, 24 + MATERIAL_PAGER_ACTIVE_WIDTH + (visible - 1) * (6 + MATERIAL_PAGER_DOT_GAP));
}

export function materialExpandedPagerWidth(availableWidth: number): number {
  return Math.max(0, availableWidth - 2 * MATERIAL_PAGER_SIDE_MARGIN);
}

export function materialExpandedPagePosition(x: number, startX: number, startIndex: number,
  availableWidth: number, count: number): number {
  const width = materialExpandedPagerWidth(availableWidth);
  const first = (availableWidth - width) / 2 + MATERIAL_PAGER_INSET;
  const last = availableWidth - first;
  if (count <= 1) return 0;
  if (x === startX || last <= first) return startIndex;
  if (x <= first) return 0;
  if (x >= last) return count - 1;
  // Keep the grabbed position anchored, with a separate scale on either side.
  if (x < startX) return startIndex * (x - first) / (startX - first);
  return startIndex + (count - 1 - startIndex) * (x - startX) / (last - startX);
}

export function materialDotWindowStart(count: number, index: number): number {
  const visible = Math.min(count, MATERIAL_PAGER_VISIBLE_DOTS);
  return Math.max(0, Math.min(count - visible, index - Math.floor(visible / 2)));
}

export function materialDotSize(page: number, first: number, visible: number, count: number): number {
  const last = first + visible - 1;
  const left = first > 0 ? page - first : visible;
  const right = last + 1 < count ? last - page : visible;
  const edge = Math.min(left, right);
  return edge === 0 ? 3 : edge === 1 ? 4.5 : 6;
}

function materialMarkerWidth(page: number, first: number, visible: number, count: number, index: number): number {
  return page === index ? MATERIAL_PAGER_ACTIVE_WIDTH : materialDotSize(page, first, visible, count);
}

export function materialDotX(page: number, count: number, index: number, width: number): number {
  const visible = Math.min(count, MATERIAL_PAGER_VISIBLE_DOTS);
  const first = materialDotWindowStart(count, index);
  let lineWidth = MATERIAL_PAGER_DOT_GAP * (visible - 1);
  let left = (page - first) * MATERIAL_PAGER_DOT_GAP;
  for (let dot = first; dot < first + visible; dot++) {
    const size = materialMarkerWidth(dot, first, visible, count, index);
    lineWidth += size;
    if (dot < page) left += size;
    if (dot === page) left += size / 2;
  }
  return (width - lineWidth) / 2 + left;
}

export function materialDotPageAt(x: number, width: number, count: number, index: number): number {
  const visible = Math.min(count, MATERIAL_PAGER_VISIBLE_DOTS);
  const first = materialDotWindowStart(count, index);
  let nearest = index;
  let distance = Number.POSITIVE_INFINITY;
  for (let page = first; page < first + visible; page++) {
    const offset = Math.abs(x - materialDotX(page, count, index, width));
    if (offset < distance) {
      nearest = page;
      distance = offset;
    }
  }
  return nearest;
}

export function materialFanPlacement(offset: number, pitch: number, selected: boolean): FanPlacement {
  const distance = Math.abs(offset);
  const foreground = 1 - Math.min(1, distance);
  const depth = Math.min(1.35, Math.max(0, distance - 1));
  return {
    x: offset * pitch / (1 + 0.23 * Math.max(0, distance - 1)),
    y: 15 - 27 * foreground + 8 * depth,
    angle: Math.min(28, Math.max(-28, offset * 12)),
    scale: 0.85 + 0.23 * foreground - 0.16 * depth,
    opacity: 1 - depth * 0.43,
    blur: selected || depth < 0.05 ? 0 : depth * 2.2,
    order: 1000 - Math.round(distance * 100) + (selected ? 300 : 0)
  };
}
