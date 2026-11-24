export const REVIEW_COOLDOWN_MS: number = 30 * 24 * 60 * 60 * 1000;
const REVIEW_EXPORTS_REQUIRED: number = 3;

export interface ReviewProgress {
  exportCount: number;
  firstExportDay: number;
  multipleExportDays: boolean;
  lastAttemptAt: number;
  lastAttemptVersion: number;
  alreadyReviewed: boolean;
}

export function recordReviewExport(progress: ReviewProgress, day: number): boolean {
  if (progress.alreadyReviewed) return false;
  if (progress.exportCount >= REVIEW_EXPORTS_REQUIRED && progress.multipleExportDays) return false;
  if (progress.exportCount === 0) progress.firstExportDay = day;
  progress.exportCount = Math.min(REVIEW_EXPORTS_REQUIRED, progress.exportCount + 1);
  progress.multipleExportDays = progress.multipleExportDays || day !== progress.firstExportDay;
  return true;
}

export function canRequestReview(progress: ReviewProgress, now: number, versionCode: number): boolean {
  return !progress.alreadyReviewed && progress.exportCount >= REVIEW_EXPORTS_REQUIRED && progress.multipleExportDays &&
    versionCode > progress.lastAttemptVersion &&
    (progress.lastAttemptAt === 0 || now - progress.lastAttemptAt >= REVIEW_COOLDOWN_MS);
}

export function isAlreadyReviewed(code: number): boolean {
  return code === 1021500007 || code === 1021500009;
}
