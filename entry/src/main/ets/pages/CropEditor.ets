import { image } from '@kit.ImageKit';
import { EDITOR_CORNER_RADIUS } from '../common/EditorTheme';
import { fullPhoto, lockedRatio, PhotoGeometry, selectRatio, turnPhoto } from '../common/PhotoGeometry';

const ACCENT: string = '#EFBD70';
const POPUP_SURFACE: string = '#242323';

@Component
export struct CropEditor {
  photo?: image.PixelMap;
  sourceWidth: number = 1;
  sourceHeight: number = 1;
  @State geometry: PhotoGeometry = fullPhoto();
  onCancel: () => void = () => {};
  onApply: (geometry: PhotoGeometry) => void = () => {};
  @State private areaWidth: number = 0;
  @State private areaHeight: number = 0;
  @State private ratioOpen: boolean = false;
  private dragStart: PhotoGeometry = fullPhoto();
  private readonly ratioOptions: string[][] = [
    ['free', 'original', '1:1'],
    ['4:3', '3:2', '16:9'],
    ['3:4', '2:3', '9:16']
  ];

  private sideways(): boolean {
    return this.geometry.angle % 180 !== 0;
  }

  private fit(): number {
    const width = this.sideways() ? this.sourceHeight : this.sourceWidth;
    const height = this.sideways() ? this.sourceWidth : this.sourceHeight;
    return Math.max(0, Math.min((this.areaWidth - 24) / width, (this.areaHeight - 24) / height));
  }

  private imageWidth(): number {
    return (this.sideways() ? this.sourceHeight : this.sourceWidth) * this.fit();
  }

  private imageHeight(): number {
    return (this.sideways() ? this.sourceWidth : this.sourceHeight) * this.fit();
  }

  private drag(event: GestureEvent, horizontal: number, vertical: number): void {
    const start = this.dragStart;
    const dx = event.offsetX / this.imageWidth();
    const dy = event.offsetY / this.imageHeight();
    const minX = Math.min(0.5, 48 / this.imageWidth());
    const minY = Math.min(0.5, 48 / this.imageHeight());
    const next: PhotoGeometry = {
      angle: start.angle, ratio: start.ratio, left: start.left, top: start.top, right: start.right, bottom: start.bottom
    };
    if (horizontal === 0 && vertical === 0) {
      const x = Math.max(-start.left, Math.min(1 - start.right, dx));
      const y = Math.max(-start.top, Math.min(1 - start.bottom, dy));
      next.left += x;
      next.right += x;
      next.top += y;
      next.bottom += y;
    } else if (start.ratio !== 'free') {
      const imageAspect = this.imageWidth() / this.imageHeight();
      const aspect = lockedRatio(start.ratio, imageAspect);
      const pixelAspect = aspect * imageAspect;
      const anchorX = horizontal < 0 ? start.right : start.left;
      const anchorY = vertical < 0 ? start.bottom : start.top;
      const availableX = horizontal < 0 ? anchorX : 1 - anchorX;
      const availableY = vertical < 0 ? anchorY : 1 - anchorY;
      const maxHeight = Math.min(availableY, availableX / aspect);
      const minHeight = Math.min(maxHeight, Math.max(minY, minX / aspect), start.bottom - start.top);
      const deltaY = (horizontal * event.offsetX * pixelAspect + vertical * event.offsetY) /
        ((1 + pixelAspect * pixelAspect) * this.imageHeight());
      const height = Math.max(minHeight, Math.min(maxHeight, start.bottom - start.top + deltaY));
      const width = height * aspect;
      next.left = horizontal < 0 ? Math.max(0, anchorX - width) : anchorX;
      next.right = horizontal > 0 ? Math.min(1, anchorX + width) : anchorX;
      next.top = vertical < 0 ? Math.max(0, anchorY - height) : anchorY;
      next.bottom = vertical > 0 ? Math.min(1, anchorY + height) : anchorY;
    } else {
      next.left = horizontal < 0 ? Math.max(0, Math.min(start.right - minX, start.left + dx)) : start.left;
      next.right = horizontal > 0 ? Math.min(1, Math.max(start.left + minX, start.right + dx)) : start.right;
      next.top = vertical < 0 ? Math.max(0, Math.min(start.bottom - minY, start.top + dy)) : start.top;
      next.bottom = vertical > 0 ? Math.min(1, Math.max(start.top + minY, start.bottom + dy)) : start.bottom;
    }
    this.geometry = next;
  }

  private ratioLabel(ratio: string): string {
    if (ratio === 'free') return '自由';
    if (ratio === 'original') return '原始比例';
    return ratio;
  }

  @Builder
  ratioMenu() {
    Column({ space: 4 }) {
      ForEach(this.ratioOptions, (options: string[]) => {
        Row({ space: 4 }) {
          ForEach(options, (ratio: string) => {
            Button(this.ratioLabel(ratio), { type: ButtonType.Normal })
              .height(44).layoutWeight(1).padding(0).borderRadius(EDITOR_CORNER_RADIUS).fontSize(14)
              .fontColor(this.geometry.ratio === ratio ? '#FFDA9E' : '#F2ECE5')
              .backgroundColor(this.geometry.ratio === ratio ? '#54432E' : Color.Transparent)
              .accessibilityText(this.ratioLabel(ratio) + (this.geometry.ratio === ratio ? '，已选中' : ''))
              .onClick(() => {
                const imageAspect = this.sideways() ? this.sourceHeight / this.sourceWidth :
                  this.sourceWidth / this.sourceHeight;
                this.geometry = selectRatio(this.geometry, ratio, imageAspect);
                this.ratioOpen = false;
              })
          })
        }.width('100%')
      })
    }.width('100%').padding(8)
      .border({ width: 1, color: '#403D39', radius: EDITOR_CORNER_RADIUS })
      .backgroundColor(POPUP_SURFACE).clip(true)
  }

  @Builder
  rotateButton(clockwise: boolean) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 5 }) {
        SymbolGlyph(clockwise ? $r('sys.symbol.arrow_clockwise') : $r('sys.symbol.arrow_counterclockwise'))
          .fontSize(23).fontColor([ACCENT])
        Text(clockwise ? '右转' : '左转').fontSize(13).fontColor('#F2ECE5')
      }
    }.width(58).height(54).padding(0).borderRadius(EDITOR_CORNER_RADIUS).backgroundColor(Color.Transparent)
      .accessibilityText(clockwise ? '右转 90°' : '左转 90°')
      .onClick(() => { this.geometry = turnPhoto(this.geometry, clockwise); })
  }

  @Builder
  toolDock() {
    Row({ space: 12 }) {
      this.rotateButton(false)
      Button({ type: ButtonType.Normal }) {
        Row({ space: 9 }) {
          Text(this.geometry.ratio === 'original' ? '原始比例' : '比例  ' + this.ratioLabel(this.geometry.ratio))
            .fontSize(14).maxLines(1).fontColor('#F2ECE5')
          Image($r('app.media.chevron')).width(13).height(13).rotate({ angle: this.ratioOpen ? 270 : 90 })
        }
      }.width(132).height(44).padding(0)
        .border({ width: 1, color: '#62605D', radius: EDITOR_CORNER_RADIUS }).backgroundColor(Color.Transparent)
        .accessibilityText('裁切比例，' + this.ratioLabel(this.geometry.ratio))
        .onClick(() => { this.ratioOpen = !this.ratioOpen; })
        .bindPopup(this.ratioOpen, {
          builder: this.ratioMenu,
          placement: Placement.Top,
          width: Math.min(this.areaWidth - 28, 288),
          popupColor: POPUP_SURFACE,
          radius: EDITOR_CORNER_RADIUS,
          backgroundBlurStyle: BlurStyle.NONE,
          enableArrow: false,
          autoCancel: true,
          onStateChange: (event) => { this.ratioOpen = event.isVisible; }
        })
      this.rotateButton(true)
    }.height(54).width('100%').justifyContent(FlexAlign.Center)
  }

  @Builder
  handle(horizontal: number, vertical: number) {
    Stack() {
      Row()
        .width(16).height(16)
        .border({ color: '#F8F6F4', width: {
          left: horizontal < 0 ? 2.5 : 0, right: horizontal > 0 ? 2.5 : 0,
          top: vertical < 0 ? 2.5 : 0, bottom: vertical > 0 ? 2.5 : 0
        } })
        .position({ x: horizontal < 0 ? 22 : 6, y: vertical < 0 ? 22 : 6 })
    }.width(44).height(44)
      .position({
        x: (horizontal < 0 ? this.geometry.left : this.geometry.right) * this.imageWidth() - 22,
        y: (vertical < 0 ? this.geometry.top : this.geometry.bottom) * this.imageHeight() - 22
      })
      .gesture(PanGesture({ distance: 0 }).onActionStart(() => { this.dragStart = this.geometry; })
        .onActionUpdate((event: GestureEvent) => this.drag(event, horizontal, vertical)))
  }

  @Builder
  cropCanvas() {
    Stack({ alignContent: Alignment.TopStart }) {
      Image(this.photo).width(this.sourceWidth * this.fit()).height(this.sourceHeight * this.fit())
        .objectFit(ImageFit.Fill).rotate({ angle: this.geometry.angle })
        .position({ x: (this.imageWidth() - this.sourceWidth * this.fit()) / 2,
          y: (this.imageHeight() - this.sourceHeight * this.fit()) / 2 })
        .hitTestBehavior(HitTestMode.None)
      Row().width(this.imageWidth()).height(this.geometry.top * this.imageHeight())
        .backgroundColor('#70000000').hitTestBehavior(HitTestMode.None)
      Row().width(this.imageWidth()).height((1 - this.geometry.bottom) * this.imageHeight())
        .position({ x: 0, y: this.geometry.bottom * this.imageHeight() })
        .backgroundColor('#70000000').hitTestBehavior(HitTestMode.None)
      Row().width(this.geometry.left * this.imageWidth()).height((this.geometry.bottom - this.geometry.top) * this.imageHeight())
        .position({ x: 0, y: this.geometry.top * this.imageHeight() })
        .backgroundColor('#70000000').hitTestBehavior(HitTestMode.None)
      Row().width((1 - this.geometry.right) * this.imageWidth()).height((this.geometry.bottom - this.geometry.top) * this.imageHeight())
        .position({ x: this.geometry.right * this.imageWidth(), y: this.geometry.top * this.imageHeight() })
        .backgroundColor('#70000000').hitTestBehavior(HitTestMode.None)
      Stack({ alignContent: Alignment.TopStart }) {
        ForEach([1, 2], (line: number) => {
          Row().width(1).height('100%').backgroundColor('#66FFFFFF')
            .position({ x: (line / 3 * 100) + '%', y: 0 }).hitTestBehavior(HitTestMode.None)
          Row().width('100%').height(1).backgroundColor('#66FFFFFF')
            .position({ x: 0, y: (line / 3 * 100) + '%' }).hitTestBehavior(HitTestMode.None)
        })
      }.width((this.geometry.right - this.geometry.left) * this.imageWidth())
        .height((this.geometry.bottom - this.geometry.top) * this.imageHeight())
        .position({ x: this.geometry.left * this.imageWidth(), y: this.geometry.top * this.imageHeight() })
        .border({ width: 1, color: '#E6FFFFFF' })
        .gesture(PanGesture({ distance: 0 }).onActionStart(() => { this.dragStart = this.geometry; })
          .onActionUpdate((event: GestureEvent) => this.drag(event, 0, 0)))
      this.handle(-1, -1)
      this.handle(1, -1)
      this.handle(-1, 1)
      this.handle(1, 1)
    }.width(this.imageWidth()).height(this.imageHeight())
  }

  build() {
    Column() {
      Row() {
        Button('取消', { type: ButtonType.Normal }).height(44).width(52).padding(0)
          .fontSize(15).fontColor('#F2ECE5').backgroundColor(Color.Transparent)
          .onClick(this.onCancel)
        Text('裁切').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#F2ECE5')
          .textAlign(TextAlign.Center).layoutWeight(1)
        Button('重置', { type: ButtonType.Normal }).height(44).width(52).padding(0)
          .fontSize(15).fontColor('#F2ECE5').backgroundColor(Color.Transparent)
          .onClick(() => { this.geometry = fullPhoto(); })
      }.width('100%').height(86).padding({ left: 13, right: 13, top: 14 })
      Stack() {
        if (this.fit() > 0) {
          this.cropCanvas()
        }
      }.width('100%').layoutWeight(1)
        .onAreaChange((_old, area) => { this.areaWidth = Number(area.width); this.areaHeight = Number(area.height); })
      Column({ space: 22 }) {
        this.toolDock()
        Button('应用', { type: ButtonType.Normal }).width('100%').constraintSize({ maxWidth: 520 })
          .height(46).borderRadius(EDITOR_CORNER_RADIUS).fontSize(17).fontWeight(FontWeight.Medium)
          .fontColor('#32271D').backgroundColor(ACCENT)
          .onClick(() => this.onApply(this.geometry))
      }.width('100%').padding({ left: 20, right: 20, top: 8, bottom: 19 })
    }.width('100%').height('100%').backgroundColor('#171819')
  }
}
