import { AppLog } from '../common/AppLog';
import { UIAbility } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { window } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  async onWindowStageCreate(stage: window.WindowStage): Promise<void> {
    AppLog.start(this.context.filesDir);
    try {
      const settings = preferences.getPreferencesSync(this.context, {name: 'settings'});
      const format = settings.getSync('exportFormat', 'JPEG') as string;
      AppStorage.setOrCreate('exportFormat', ['JPEG', 'PNG', 'HEIF'].includes(format) ? format : 'JPEG');
    } catch (_) { AppStorage.setOrCreate('exportFormat', 'JPEG'); }
    const main = stage.getMainWindowSync();
    try {
      await main.setWindowLayoutFullScreen(true);
      const safeInsets = (): void => {
        const system = main.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        const gesture = main.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        AppStorage.setOrCreate('darkroomTop', system.topRect.height);
        AppStorage.setOrCreate('darkroomBottom', Math.max(gesture.bottomRect.height, system.bottomRect.height));
        AppStorage.setOrCreate('darkroomLeft', system.leftRect.width);
        AppStorage.setOrCreate('darkroomRight', system.rightRect.width);
      };
      safeInsets();
      main.on('avoidAreaChange', safeInsets);
      await main.setWindowSystemBarProperties({ statusBarColor: '#171819', statusBarContentColor: '#EEEAE5',
        navigationBarColor: '#201F20', navigationBarContentColor: '#EEEAE5' });
    } finally {
      await stage.loadContent('pages/Index');
    }
  }
}
