export function homeDisplayCount(width: number, total: number): number {
  return Math.min(total, width >= 1440 ? 3 : width >= 720 ? 2 : 1);
}

export function homePageCount(total: number, displayCount: number): number {
  return Math.max(1, total - displayCount + 1);
}

export function homeCardScale(position: number, displayCount: number): number {
  const distance = Math.max(0, -position, position - (displayCount - 1));
  return 1 - 0.045 * Math.min(1, distance);
}
