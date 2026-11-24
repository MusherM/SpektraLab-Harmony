import { PhotoPickerComponent, PickerController, PickerOptions, PickerColorMode, SelectMode } from '@ohos.file.PhotoPickerComponent';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppLog } from '../common/AppLog';

@Component
export struct FormatPhotoPicker {
  onCancel: () => void = () => {};
  onConfirm: (uri: string) => void = () => {};
  @State private controller: PickerController = new PickerController();
  private options: PickerOptions = new PickerOptions();
  @State private format: string = '全部';
  @State private uri: string = '';
  @State private ready: boolean = false;
  @State private updating: boolean = false;
  @State private message: string = '';
  @State private showFormatHelp: boolean = false;
  private requestedFormat: string = '全部';
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    this.options.selectMode = SelectMode.MULTI_SELECT;
    this.options.maxSelectNumber = 1;
    this.options.checkBoxColor = '#FFEFBD70';
    this.options.checkboxTextColor = '#FFEFBD70';
    this.options.backgroundColor = '#FF171819';
    this.options.uiComponentColorMode = PickerColorMode.DARK;
    this.options.photoBrowserBackgroundColorMode = PickerColorMode.DARK;
    this.options.preferredCompatibleMode = photoAccessHelper.PreferredCompatibleMode.CURRENT;
    this.options.singleSelectionMode = photoAccessHelper.SingleSelectionMode.SELECT_MODE;
    this.options.isPhotoTakingSupported = false;
  }

  aboutToDisappear(): void { this.active = false; }

  private async filter(format: string): Promise<void> {
    if (!this.ready || format === this.requestedFormat) return;
    this.requestedFormat = format;
    if (this.updating) return;
    this.updating = true;
    this.message = '';
    try {
      while (this.active && this.requestedFormat !== this.format) {
        const next = this.requestedFormat;
        await this.controller.updatePickerOptions({
          mimeTypeFilter: { mimeTypeArray: next === '全部' ? ['image/*'] :
            ['image/x-adobe-dng', 'image/x-canon-cr2', 'image/x-canon-cr3',
              'image/x-nikon-nef', 'image/x-nikon-nrw', 'image/x-sony-arw',
              'image/x-fuji-raf', 'image/x-panasonic-rw2', 'image/x-olympus-orf', 'image/x-pentax-pef'] },
          preselectedUris: []
        });
        if (!this.active) return;
        this.uri = '';
        this.format = next;
      }
    } catch (err) {
      if (!this.active) return;
      this.requestedFormat = this.format;
      AppLog.failure('photo filter', err as BusinessError);
      this.message = '切换格式失败，请重试';
    } finally { this.updating = false; }
  }

  build() {
    Column() {
      Row() {
        Button('取消').backgroundColor(Color.Transparent).fontColor('#ECEAE5').onClick(this.onCancel)
        Text('选择原图').fontSize(18).fontColor('#F2ECE5').layoutWeight(1).textAlign(TextAlign.Center)
        Button('使用照片').backgroundColor('#EFBD70').fontColor('#171819')
          .enabled(this.uri.length > 0 && !this.updating).onClick(() => this.onConfirm(this.uri))
      }.width('100%').height(54).padding({left: 10, right: 10})
      Row({space: 10}) {
        ForEach(['全部', 'RAW'], (format: string) => {
          Button(format).backgroundColor(this.format === format ? '#EFBD70' : '#302F30')
            .fontColor(this.format === format ? '#171819' : '#ECEAE5')
            .enabled(this.ready).onClick(() => this.filter(format))
        })
        Blank().layoutWeight(1)
        Button({type: ButtonType.Circle}) {
          Text('?').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#A6A3A0')
            .width(22).height(22).textAlign(TextAlign.Center)
            .border({width: 1.5, color: '#85827F'}).borderRadius(11)
        }.width(40).height(40).backgroundColor(Color.Transparent)
          .accessibilityText('图像格式说明')
          .onClick(() => { this.showFormatHelp = !this.showFormatHelp; })
          .bindPopup(this.showFormatHelp, {
            message: '支持 JPEG、PNG、HEIF 及主流 RAW 格式。RAW 保留了更多拍摄时的原始信息，能为色彩、明暗和细节处理提供更大空间，建议优先选择。',
            placement: Placement.Bottom,
            enableArrow: true,
            popupColor: '#FF353436',
            backgroundBlurStyle: BlurStyle.NONE,
            messageOptions: {textColor: '#F2ECE5'},
            width: 300,
            onStateChange: (event) => { this.showFormatHelp = event.isVisible; }
          })
      }.width('100%').padding({left: 14, right: 14, bottom: 10})
      if (this.message) { Text(this.message).fontColor('#ECEAE5').padding(8) }
      PhotoPickerComponent({
        pickerOptions: this.options,
        pickerController: this.controller,
        onPickerControllerReady: () => { this.ready = true; },
        onSelect: (uri: string) => { this.uri = uri; },
        onDeselect: (uri: string) => { if (this.uri === uri) this.uri = ''; }
      }).width('100%').layoutWeight(1)
    }.width('100%').height('100%').backgroundColor('#171819')
  }
}
