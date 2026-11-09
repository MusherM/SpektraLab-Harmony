export function horizontalAdjustment(offsetX: number, offsetY: number): boolean {
  return Math.abs(offsetX) > Math.abs(offsetY) * 1.3;
}

export class VersionTapSequence {
  private count: number = 0;
  private lastTap: number = 0;

  reset(): void { this.count = 0; this.lastTap = 0; }

  tap(now: number): boolean {
    this.count = this.count > 0 && now - this.lastTap <= 1400 && now >= this.lastTap ? this.count + 1 : 1;
    this.lastTap = now;
    if (this.count < 5) return false;
    this.reset();
    return true;
  }
}
