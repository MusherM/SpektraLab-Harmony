import { common, wantConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppLog } from '../common/AppLog';

import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';

@Entry
@Component
struct Feedback {
  @StorageProp('darkroomTop') private topInset: number = 0;
  @StorageProp('darkroomBottom') private bottomInset: number = 0;
  @StorageProp('darkroomLeft') private leftInset: number = 0;
  @StorageProp('darkroomRight') private rightInset: number = 0;
  @State private description: string = '';
  @State private steps: string = '';
  @State private screenshot: string = '';
  @State private picking: boolean = false;
  @State private message: string = '';
  @State private opening: boolean = false;

  private async pickScreenshot(): Promise<void> {
    this.picking = true;
    this.message = '';
    try {
      const result = await new photoAccessHelper.PhotoViewPicker().select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE, maxSelectNumber: 1
      });
      if (result.photoUris.length) this.screenshot = result.photoUris[0];
    } catch (err) {
      AppLog.failure('feedback picker', err as BusinessError);
      this.message = '无法选择截图，请重试';
    } finally { this.picking = false; }
  }

  private async copyScreenshot(cacheDir: string, uri: string): Promise<string> {
    const name = new fileUri.FileUri(uri).name;
    const extension = /\.([a-zA-Z0-9]{1,8})$/.exec(name);
    const path = cacheDir + '/SpektraLab-shot-' + Date.now() + (extension ? '.' + extension[1] : '');
    const source = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      await fs.copyFile(source.fd, path);
      const size = fs.statSync(source.fd).size;
      if (!size || fs.statSync(path).size !== size) throw new Error('截图复制不完整');
    } finally { fs.closeSync(source); }
    return fileUri.getUriFromPath(path);
  }

  private async feedback(): Promise<void> {
    if (this.opening || this.picking || !this.description.trim()) return;
    this.opening = true;
    this.message = '';
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    let ready = false;
    try {
      const attachments = [encodeURI(AppLog.snapshot(ctx))];
      if (this.screenshot) attachments.push(encodeURI(await this.copyScreenshot(ctx.cacheDir, this.screenshot)));
      const steps = this.steps.trim();
      const body = '问题描述\n' + this.description.trim() + (steps ? '\n\n复现步骤\n' + steps : '');
      ready = true;
      await ctx.startAbilityByType('mail', {
        email: ['musher@foxmail.com'],
        subject: encodeURI('SpektraLab 问题反馈'),
        body: encodeURI(body),
        'ability.params.stream': attachments,
        'ability.want.params.uriPermissionFlag': wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
      }, { onError: (code: number) => {
        AppLog.record('mail error code=' + code);
        this.message = '无法打开邮件应用，请确认已安装并启用邮件应用';
      } });
    } catch (err) {
      AppLog.record((ready ? 'mail' : 'snapshot') + ' error code=' + (err as BusinessError).code);
      this.message = ready ? '无法打开邮件应用，请确认已安装并启用邮件应用' : '无法准备反馈附件，请重试';
    } finally { this.opening = false; }
  }

  build() {
    Column() {
      Row({space: 16}) {
        Button('返回').backgroundColor('#303032').onClick(() => this.getUIContext().getRouter().back())
        Text('反馈问题').fontSize(22).fontWeight(FontWeight.Bold).fontColor('#F1EDE7')
      }.width('100%').height(56)
      Scroll() {
        Column({space: 12}) {
          Text('问题描述').fontSize(18).fontColor('#F1EDE7')
          TextArea({text: this.description, placeholder: '遇到了什么问题？你原本期待什么结果？'})
            .height(96).backgroundColor('#303032').fontColor('#F1EDE7').placeholderColor('#BFBAB4')
            .onChange((value: string) => { this.description = value; })
          Text('复现步骤（选填）').fontSize(18).fontColor('#F1EDE7')
          TextArea({text: this.steps, placeholder: '请按顺序写下操作，例如：导入 RAW → 选择胶片 → 点击保存。'})
            .height(90).backgroundColor('#303032').fontColor('#F1EDE7').placeholderColor('#BFBAB4')
            .onChange((value: string) => { this.steps = value; })
          Text('截图（选填）').fontSize(18).fontColor('#F1EDE7')
          if (this.screenshot) {
            Image(this.screenshot).width(100).height(96).objectFit(ImageFit.Contain).accessibilityText('已选截图')
          }
          Row({space: 12}) {
            Button(this.screenshot ? '更换截图' : '添加截图').backgroundColor('#303032').onClick(() => this.pickScreenshot())
            if (this.screenshot) {
              Button('移除截图').backgroundColor('#303032').onClick(() => { this.screenshot = ''; })
            }
          }.enabled(!this.opening && !this.picking)
          Text('提交后将打开邮件应用，并附上最近的运行日志。').fontSize(14).fontColor('#CECAC4')
          if (this.message) { Text(this.message).fontColor('#EFBD70') }
          Button('提交', {type: ButtonType.Normal}).width('100%').borderRadius(10).backgroundColor('#EFBD70')
            .fontColor('#32271D').enabled(!!this.description.trim() && !this.opening && !this.picking)
            .onClick(() => this.feedback())
        }.alignItems(HorizontalAlign.Start).width('100%').padding({top: 18, bottom: 18})
      }.layoutWeight(1).align(Alignment.TopStart)
    }.width('100%').height('100%').backgroundColor('#171819')
      .padding({top: this.topInset + 'px', bottom: this.bottomInset + 'px',
        left: 16 + this.getUIContext().px2vp(this.leftInset), right: 16 + this.getUIContext().px2vp(this.rightInset)})
  }
}
