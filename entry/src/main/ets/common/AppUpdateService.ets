import { common, bundleManager } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { updateManager } from '@kit.AppGalleryKit';
import { automaticUpdateAllowed, UPDATE_SNOOZE_MS } from './UpdateRules';
import { AppLog } from './AppLog';

const DEFERRED_UNTIL: string = 'updateDeferredUntil';

export class AppUpdateService {
  static automaticAttempted: boolean = false;

  static automaticAllowed(context: common.UIAbilityContext): boolean {
    const settings = preferences.getPreferencesSync(context, {name: 'settings'});
    const until = settings.getSync(DEFERRED_UNTIL, 0) as number;
    const allowed = automaticUpdateAllowed(until, Date.now());
    if (!allowed) AppLog.record('update automatic snoozed until=' + until);
    return allowed;
  }

  static defer(context: common.UIAbilityContext): void {
    const settings = preferences.getPreferencesSync(context, {name: 'settings'});
    const until = Date.now() + UPDATE_SNOOZE_MS;
    settings.putSync(DEFERRED_UNTIL, until);
    settings.flushSync();
    AppLog.record('update snoozed until=' + until);
  }

  static async hasUpdate(context: common.UIAbilityContext): Promise<boolean> {
    if (AppStorage.get<boolean>('updatePreviewAvailable') === true) {
      AppLog.record('update check debug result=available');
      return true;
    }
    const result = await updateManager.checkAppUpdate(context);
    AppLog.record('update check result=' + result.updateAvailable);
    return result.updateAvailable === updateManager.UpdateAvailableCode.LATER_VERSION_EXIST;
  }

  static bundleName(): string {
    return bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).name;
  }

  static versionName(): string {
    return bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).versionName;
  }
}
