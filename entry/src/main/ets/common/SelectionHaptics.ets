import { vibrator } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppLog } from './AppLog';

export class SelectionHaptics {
  private soft: boolean = false;

  prepare(surface: string): void {
    vibrator.isSupportEffect(vibrator.HapticFeedback.EFFECT_SOFT).then((supported: boolean) => {
      this.soft = supported;
    }).catch((error: BusinessError) => AppLog.failure(surface + ' haptic capability', error));
  }

  async pulse(surface: string, index: number, source: string): Promise<void> {
    AppLog.record(surface + ' selection index=' + index + ' source=' + source);
    try {
      if (this.soft) {
        await vibrator.startVibration({type: 'preset', effectId: vibrator.HapticFeedback.EFFECT_SOFT, count: 1},
          {usage: 'touch'});
      } else {
        await vibrator.startVibration({type: 'time', duration: 12}, {usage: 'touch'});
      }
      AppLog.record(surface + ' selection index=' + index + ' haptic accepted');
    } catch (error) {
      AppLog.failure(surface + ' haptic', error as BusinessError);
    }
  }
}
