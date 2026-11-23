import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppLog } from '../common/AppLog';
import { EDITOR_CORNER_RADIUS } from '../common/EditorTheme';
import { PhotoGeometry } from '../common/PhotoGeometry';
import { composeBorder, FrameBorder, loadBorderOverlay } from './FrameBorders';

@Component
export struct FrameBorderCard {
  preset: FrameBorder = {id: '', name: '', width: 0, height: 0, windows: []};
  getSource: () => image.PixelMap | undefined = () => undefined;
  getFraming: () => PhotoGeometry | undefined = () => undefined;
  getFilm: () => string = () => '';
  @Prop @Watch('refresh') sourceRevision: number = 0;
  @Prop selected: boolean = false;
  @Prop cardWidth: number = 100;
  onSelect: () => void = () => {};
  @State private thumbnail?: image.PixelMap = undefined;
  private visible: boolean = false;
  private revision: number = 0;

  aboutToAppear(): void {
    this.visible = true;
    this.refresh();
  }

  aboutToDisappear(): void {
    this.visible = false;
    this.revision++;
    this.thumbnail?.release();
    this.thumbnail = undefined;
  }

  private async refresh(): Promise<void> {
    if (!this.visible) return;
    const revision = ++this.revision;
    let overlay: image.PixelMap | undefined;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      overlay = await loadBorderOverlay(context.resourceManager, this.preset, 256);
      const source = this.getSource();
      if (!source || revision !== this.revision) return;
      const next = composeBorder(source, this.preset, overlay, this.getFilm(), 256, this.getFraming());
      const old = this.thumbnail;
      this.thumbnail = next;
      old?.release();
    } catch (err) {
      if (revision === this.revision) AppLog.failure('border thumbnail ' + this.preset.id, err as BusinessError);
    } finally { overlay?.release(); }
  }

  build() {
    Column({space: 5}) {
        Stack({alignContent: Alignment.TopEnd}) {
          if (this.thumbnail) {
            Image(this.thumbnail).width('100%').height('100%').objectFit(ImageFit.Contain)
              .draggable(false).accessibilityLevel('no')
          }
          if (this.selected) {
            Text('✓').fontSize(11).fontWeight(FontWeight.Bold).fontColor('#292016')
              .textAlign(TextAlign.Center).width(16).height(16).borderRadius(8).backgroundColor('#F1C077')
              .margin(3).accessibilityLevel('no')
          }
        }.width('100%').height(Math.round(this.cardWidth * 0.74)).backgroundColor('#151111')
          .borderRadius(4).clip(true)
        Text(this.preset.name).fontSize(11).lineHeight(14).width('100%').height(42)
          .textAlign(TextAlign.Start).fontColor(this.selected ? '#FFE0AF' : '#E5E0D8')
          .padding({left: 2, right: 2}).wordBreak(WordBreak.BREAK_ALL)
    }.id('border-card-' + (this.preset.id || 'none')).width(this.cardWidth).padding(4)
      .backgroundColor(this.selected ? '#3A3025' : '#292829').borderRadius(EDITOR_CORNER_RADIUS)
      .border({width: this.selected ? 1.5 : 1, color: this.selected ? '#EFBD70' : '#3A3735', radius: EDITOR_CORNER_RADIUS})
      .accessibilityRole(AccessibilityRoleType.BUTTON)
      .accessibilityText(this.preset.name + (this.selected ? '，已选中' : ''))
      .onClick(() => this.onSelect())
  }
}
