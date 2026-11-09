import { bundleManager } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { VersionTapSequence } from '../common/InteractionRules';

const REPOSITORY = 'https://github.com/JamesQiu2005/SpektraLab';

@Entry
@Component
struct Settings {
  @StorageLink('exportFormat') private exportFormat: string = 'JPEG';
  @State private supportedFormats: string[] = [];
  @State private savingFormat: boolean = false;
  @State private message: string = '';
  @StorageProp('darkroomTop') private topInset: number = 0;
  @StorageProp('darkroomBottom') private bottomInset: number = 0;
  @StorageProp('darkroomLeft') private leftInset: number = 0;
  @StorageProp('darkroomRight') private rightInset: number = 0;
  private readonly versionName: string =
    bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).versionName;
  private versionTaps: VersionTapSequence = new VersionTapSequence();

  onPageHide(): void { this.versionTaps.reset(); }

  aboutToAppear(): void {
    const packer = image.createImagePacker();
    this.supportedFormats = packer.supportedFormats;
    packer.release();
  }

  private supported(format: string): boolean {
    if (format === 'HEIF') return this.supportedFormats.includes('image/heic') || this.supportedFormats.includes('image/heif');
    return this.supportedFormats.includes(format === 'PNG' ? 'image/png' : 'image/jpeg');
  }

  private async selectFormat(format: string): Promise<void> {
    if (this.savingFormat || this.exportFormat === format) return;
    this.savingFormat = true;
    this.message = '';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const settings = preferences.getPreferencesSync(context, {name: 'settings'});
      settings.putSync('exportFormat', format);
      await settings.flush();
      this.exportFormat = format;
    } catch (_) { this.message = '设置保存失败，请重试'; }
    finally { this.savingFormat = false; }
  }

  build() {
    Column() {
      Row({space: 16}) {
        Button('返回').backgroundColor('#303032').onClick(() => this.getUIContext().getRouter().back())
        Text('设置').fontSize(22).fontWeight(FontWeight.Bold).fontColor('#F1EDE7')
      }.width('100%').height(56)
      Scroll() {
        Column({space: 12}) {
          Text('输出格式').fontSize(18).fontWeight(FontWeight.Medium).fontColor('#F1EDE7')
          Row({space: 10}) {
            ForEach(['JPEG', 'PNG', 'HEIF'], (format: string) => {
              Button(format, {type: ButtonType.Normal})
                .layoutWeight(1).height(44).borderRadius(10)
                .backgroundColor(this.exportFormat === format ? '#EFBD70' : '#303032')
                .fontColor(this.exportFormat === format ? '#32271D' : '#ECEAE5')
                .enabled(this.supported(format) && !this.savingFormat)
                .onClick(() => { this.selectFormat(format); })
            })
          }.width('100%')
          if (this.message) { Text(this.message).fontSize(14).fontColor('#ECEAE5') }
          if (this.supportedFormats.length > 0 && !this.supported('HEIF')) {
            Text('当前设备不支持 HEIF 编码').fontSize(14).fontColor('#B8B5AF')
          }
          Divider().color('#454446').margin({top: 8, bottom: 8})
          Text('关于 SpektraLab').fontSize(18).fontWeight(FontWeight.Medium).fontColor('#F1EDE7')
          Text('版本 ' + this.versionName).fontSize(16).fontColor('#ECEAE5')
            .padding({top: 10, bottom: 10}).onClick(() => {
              if (this.versionTaps.tap(Date.now())) this.getUIContext().getRouter().pushUrl({url: 'pages/Credits'});
            })
          Divider().color('#454446').margin({top: 8, bottom: 8})
          Text('开源声明').fontSize(18).fontWeight(FontWeight.Medium).fontColor('#F1EDE7')
          Text('本应用基于开源项目 SpektraLab 开发。').fontSize(16).fontColor('#ECEAE5')
          Hyperlink(REPOSITORY, 'JamesQiu2005/SpektraLab').color('#EFBD70')
          Divider().color('#454446').margin({top: 8, bottom: 8})
          Button('反馈问题',{type: ButtonType.Normal}).borderRadius(10).backgroundColor('#EFBD70').fontColor('#32271D')
            .onClick(() => this.getUIContext().getRouter().pushUrl({url: 'pages/Feedback'}))
        }.alignItems(HorizontalAlign.Start).width('100%').padding({top: 18, bottom: 18})
      }.layoutWeight(1).align(Alignment.TopStart)
    }.width('100%').height('100%').backgroundColor('#171819')
      .padding({top: this.topInset + 'px', bottom: this.bottomInset + 'px',
        left: 16 + this.getUIContext().px2vp(this.leftInset), right: 16 + this.getUIContext().px2vp(this.rightInset)})
  }
}
