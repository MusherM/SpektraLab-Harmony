export const UPDATE_SNOOZE_MS: number = 7 * 24 * 60 * 60 * 1000;

export function automaticUpdateAllowed(deferredUntil: number, now: number): boolean {
  return !Number.isFinite(deferredUntil) || deferredUntil <= now;
}
