import { common } from '@kit.AbilityKit';
import { productViewManager } from '@kit.AppGalleryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppUpdateService } from '../common/AppUpdateService';
import { AppLog } from '../common/AppLog';
import { RELEASE_NOTES, ReleaseNote } from '../common/ReleaseNotes';

@CustomDialog
struct UpdatePrompt {
  controller: CustomDialogController;
  onLater: () => boolean = () => true;
  onStore: () => void = () => {};
  @State private error: string = '';

  build() {
    Column({space: 14}) {
      Text('发现新版本').fontSize(20).fontWeight(FontWeight.Medium).fontColor('#F2ECE5')
        .width('100%').textAlign(TextAlign.Center)
      Text('前往应用商店更新 SpektraLab。').fontSize(14).lineHeight(22).fontColor('#C8BEB2')
        .width('100%').textAlign(TextAlign.Center)
      if (this.error) { Text(this.error).fontSize(14).fontColor('#EFBD70').width('100%') }
      Row({space: 10}) {
        Button('稍后', {type: ButtonType.Normal})
          .width(96).height(46).borderRadius(12).fontSize(16)
          .backgroundColor('#343233').fontColor('#ECE5DC').id('update-later')
          .onClick(() => {
            if (this.onLater()) this.controller.close();
            else this.error = '提醒设置保存失败，请重试';
          })
        Button('前往应用商店', {type: ButtonType.Normal})
          .layoutWeight(1).height(46).borderRadius(12).fontSize(16)
          .backgroundColor('#EFBD70').fontColor('#32271D').id('update-store')
          .onClick(() => { this.onStore(); })
      }.width('100%').margin({top: 10})
    }.width(340).padding(22).borderRadius(16).backgroundColor('#242426')
      .border({width: 0.5, color: '#50473F'}).id('update-prompt')
  }
}

@CustomDialog
struct ReleaseNotesDialog {
  controller: CustomDialogController;
  @StorageProp('darkroomWindowHeight') private windowHeight: number = 1600;
  private readonly versionName: string = AppUpdateService.versionName();

  build() {
    Column({space: 16}) {
      Column({space: 6}) {
        Text('更新日志').fontSize(20).fontWeight(FontWeight.Medium).fontColor('#F2ECE5')
        Text(this.versionName).fontSize(15).fontColor('#C8BEB2')
      }.width('100%').alignItems(HorizontalAlign.Start)
      Divider().color('#454446').strokeWidth(0.5)
      Scroll() {
        Column({space: 20}) {
          ForEach(RELEASE_NOTES, (note: ReleaseNote) => {
            Column({space: 6}) {
              Text(note.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor('#F2ECE5').width('100%')
              Text(note.text).fontSize(15).lineHeight(24).fontColor('#C8BEB2').width('100%')
            }.width('100%').alignItems(HorizontalAlign.Start)
          }, (note: ReleaseNote) => note.title)
        }.width('100%').alignItems(HorizontalAlign.Start).padding({right: 12, bottom: 8})
      }.width('100%').constraintSize({maxHeight: Math.max(96, Math.min(360,
        this.getUIContext().px2vp(this.windowHeight) * 0.8 - 190))})
        .scrollBar(BarState.Auto).edgeEffect(EdgeEffect.None).id('release-notes-scroll')
      Button('知道了', {type: ButtonType.Normal})
        .width('100%').height(46).borderRadius(12).fontSize(16)
        .backgroundColor('#EFBD70').fontColor('#32271D').id('release-notes-close')
        .onClick(() => this.controller.close())
    }.width('88%').padding(22).borderRadius(16).backgroundColor('#242426')
      .border({width: 0.5, color: '#50473F'}).id('release-notes-dialog')
  }
}

@Component
export struct AppUpdates {
  controls: boolean = false;
  onFeedback: () => void = () => {};
  @Prop @Watch('automaticCheck') ready: boolean = false;
  @State private checking: boolean = false;
  @State private message: string = '';
  private active: boolean = false;
  private prompt: CustomDialogController = new CustomDialogController({
    builder: UpdatePrompt({onLater: () => this.later(), onStore: () => this.openStore()}),
    customStyle: true, alignment: DialogAlignment.Center, autoCancel: false, maskColor: '#99000000'
  });
  private notes: CustomDialogController = new CustomDialogController({
    builder: ReleaseNotesDialog(), customStyle: true, alignment: DialogAlignment.Center,
    autoCancel: true, maskColor: '#99000000'
  });

  aboutToAppear(): void { this.active = true; this.automaticCheck(); }

  aboutToDisappear(): void {
    this.active = false;
    this.prompt.close();
    this.notes.close();
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private automaticCheck(): void {
    if (this.controls || !this.active || !this.ready || AppUpdateService.automaticAttempted) return;
    AppUpdateService.automaticAttempted = true;
    this.check(false);
  }

  private async check(manual: boolean): Promise<void> {
    if (this.checking) return;
    this.checking = true;
    this.message = '';
    try {
      if (!manual && !AppUpdateService.automaticAllowed(this.context())) return;
      const available = await AppUpdateService.hasUpdate(this.context());
      const page = this.getUIContext().getRouter().getState().name;
      if (!this.active || (manual ? page !== 'Settings' : page !== 'Index' || !this.ready)) return;
      if (available) {
        this.prompt.open();
        AppLog.record('update prompt opened ' + (manual ? 'manual' : 'automatic'));
      } else if (manual) this.message = '当前已是最新版本';
    } catch (err) {
      AppLog.failure('update check', err as BusinessError);
      if (manual) this.message = '检查更新失败，请稍后重试';
    } finally { this.checking = false; }
  }

  private later(): boolean {
    try { AppUpdateService.defer(this.context()); return true; }
    catch (err) { AppLog.failure('update snooze', err as BusinessError); return false; }
  }

  private openStore(): void {
    try {
      productViewManager.loadProduct(this.context(), {parameters: {bundleName: AppUpdateService.bundleName()}}, {
        onAppear: () => {
          this.prompt.close();
          AppLog.record('update store opened');
        },
        onError: (err: BusinessError) => {
          AppLog.failure('update store', err);
          this.getUIContext().getPromptAction().showToast({message: '应用商店打开失败，请稍后重试'});
        }
      });
    } catch (err) {
      AppLog.failure('update store', err as BusinessError);
      this.getUIContext().getPromptAction().showToast({message: '应用商店打开失败，请稍后重试'});
    }
  }

  @Styles
  actionStyle() {
    .layoutWeight(1).height(48).borderRadius(10).padding({left: 4, right: 4})
    .backgroundColor('#303032')
  }

  build() {
    if (this.controls) {
      Column({space: 10}) {
        Row({space: 8}) {
          Button(this.checking ? '正在检查' : '检查更新', {type: ButtonType.Normal})
            .actionStyle().fontSize(14).fontWeight(FontWeight.Medium).fontColor('#F1EDE7')
            .enabled(!this.checking).id('check-updates').onClick(() => { this.check(true); })
          Button('更新日志', {type: ButtonType.Normal})
            .actionStyle().fontSize(14).fontWeight(FontWeight.Medium).fontColor('#F1EDE7')
            .id('show-release-notes').onClick(() => { this.notes.open(); })
          Button('反馈问题', {type: ButtonType.Normal})
            .actionStyle().fontSize(14).fontWeight(FontWeight.Medium).fontColor('#F1EDE7')
            .id('open-feedback').onClick(() => { this.onFeedback(); })
        }.width('100%').constraintSize({maxWidth: 480})
        if (this.message) { Text(this.message).fontSize(14).fontColor('#C8BEB2').width('100%') }
      }.width('100%').alignItems(HorizontalAlign.Start)
    }
  }
}
