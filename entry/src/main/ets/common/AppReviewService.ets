import { bundleManager, common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { commentManager } from '@kit.AppGalleryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppLog } from './AppLog';
import { canRequestReview, isAlreadyReviewed, recordReviewExport, ReviewProgress } from './ReviewRules';

const REVIEW_PROGRESS: string = 'ratingProgress';

export class AppReviewService {
  private static load(settings: preferences.Preferences): ReviewProgress {
    const data = settings.getSync(REVIEW_PROGRESS, '') as string;
    if (data) return JSON.parse(data) as ReviewProgress;
    return {exportCount: 0, firstExportDay: 0, multipleExportDays: false, lastAttemptAt: 0, lastAttemptVersion: 0,
      alreadyReviewed: false};
  }

  private static persist(settings: preferences.Preferences, progress: ReviewProgress): void {
    settings.putSync(REVIEW_PROGRESS, JSON.stringify(progress));
    settings.flushSync();
  }

  static recordExport(context: common.UIAbilityContext): void {
    try {
      const settings = preferences.getPreferencesSync(context, {name: 'appReview'});
      const progress = AppReviewService.load(settings);
      const now = new Date();
      const day = now.getFullYear() * 10000 + (now.getMonth() + 1) * 100 + now.getDate();
      if (recordReviewExport(progress, day)) AppReviewService.persist(settings, progress);
    } catch (error) {
      AppLog.failure('review export progress', error as BusinessError);
    }
  }

  static async requestIfEligible(context: common.UIAbilityContext): Promise<void> {
    try {
      const settings = preferences.getPreferencesSync(context, {name: 'appReview'});
      const progress = AppReviewService.load(settings);
      const version = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).versionCode;
      const now = Date.now();
      if (!canRequestReview(progress, now, version)) return;
      progress.lastAttemptAt = now;
      progress.lastAttemptVersion = version;
      AppReviewService.persist(settings, progress);
      try {
        await commentManager.showCommentDialog(context);
        AppLog.record('AppGallery review dialog requested');
      } catch (error) {
        const failure = error as BusinessError;
        if (isAlreadyReviewed(failure.code)) {
          progress.alreadyReviewed = true;
          AppReviewService.persist(settings, progress);
        }
        AppLog.failure('AppGallery review dialog', failure);
      }
    } catch (error) {
      AppLog.failure('review prompt progress', error as BusinessError);
    }
  }
}
