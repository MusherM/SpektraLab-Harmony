import { EDITOR_CORNER_RADIUS as CORNER_RADIUS } from '../common/EditorTheme';
import { CropEditor } from './CropEditor';
import { editedPhoto, fullPhoto, geometryMap, hasCrop, PhotoGeometry } from '../common/PhotoGeometry';
import { FormatPhotoPicker } from './FormatPhotoPicker';
import { HomeGallery, HomeRecipe } from './HomeGallery';
import { AppUpdates } from './AppUpdates';
import { exportTitle } from '../common/MaterialNames';
import { BorderFraming, centeredBorderFraming } from '../common/BorderFraming';
import { materialOrder, moveVisibleMaterial } from '../common/MaterialOrder';
import { preferences } from '@kit.ArkData';
import { horizontalAdjustment } from '../common/InteractionRules';
import { AppLog } from '../common/AppLog';
import { AppReviewService } from '../common/AppReviewService';
import { exportMime, exportExtension } from '../common/ExportFormat';
import { isFastExport, normalizeExportQuality } from '../common/ExportQuality';
import { straightPhotoPixels } from '../common/PhotoPixels';
import { rawPreviewRotation, orientedPixelMap } from '../common/RawOrientation';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { colorSpaceManager } from '@kit.ArkGraphics2D';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { taskpool, util } from '@kit.ArkTS';
import { availableFrameBorders, borderAperture, BUILT_IN_FRAME_BORDERS, composeBorder, FrameBorder, loadBorderOverlay, NO_FRAME } from './FrameBorders';
import { FrameBorderCard } from './FrameBorderCard';
import { ExportAttempt } from '../common/ExportAttempt';
import { MaterialPager } from './MaterialPager';
import { materialFanPlacement, FanPlacement } from '../common/MaterialPagerRules';
import nativeEngine, { RawFrame } from 'libspektralab.so';

import { curves, uiMaterial } from '@kit.ArkUI';

let resourceCleanup: Promise<void> = Promise.resolve();

const DEFAULT_FILM: string = 'kodak_portra_400';
const DEFAULT_PAPER: string = 'kodak_portra_endura';

const HANDLE_HEIGHT: number = 44;
const COLLAPSED_HEIGHT: number = HANDLE_HEIGHT + 12;
const BORDER_TAB: number = 2;
const ADJUST_TAB: number = 3;

interface MaterialPage {
  id: string;
  name: string;
  stock?: Stock;
  border?: FrameBorder;
}

@Component
struct DevelopingFilm {
  prominent: boolean = false;
  onSaveHelp: () => void = () => {};
  @Prop @Watch('resetSaveHelp') label: string = '正在冲印';
  @State private angle: number = 0;
  @State private helpVisible: boolean = false;
  private helpTimer: number = -1;

  aboutToAppear(): void { this.resetSaveHelp(); }

  aboutToDisappear(): void {
    if (this.helpTimer !== -1) clearTimeout(this.helpTimer);
    this.helpTimer = -1;
  }

  private resetSaveHelp(): void {
    if (this.helpTimer !== -1) clearTimeout(this.helpTimer);
    this.helpTimer = -1;
    this.helpVisible = false;
    if (this.label !== '正在保存') return;
    this.helpTimer = setTimeout(() => {
      this.helpTimer = -1;
      this.getUIContext().animateTo({duration: 280, curve: Curve.EaseOut}, () => {
        this.helpVisible = true;
      });
    }, 3000);
  }

  @Builder
  saveHelp() {
    Button({type: ButtonType.Circle}) {
      Text('?').fontSize(11).fontWeight(FontWeight.Medium).fontColor('#A6A3A0')
        .width(16).height(16).textAlign(TextAlign.Center)
        .border({width: 1, color: '#85827F'}).borderRadius(8)
    }.width(22).height(22).backgroundColor(Color.Transparent)
      .opacity(this.helpVisible ? 1 : 0).translate({x: this.helpVisible ? 1.5 : -4.5})
      .enabled(this.helpVisible).accessibilityLevel(this.helpVisible ? 'yes' : 'no')
      .accessibilityText('保存耗时说明')
      .id('save-help-button')
      .onClick(() => { this.onSaveHelp(); })
  }

  @Builder
  aperture() {
    Image($r('app.media.developing_aperture'))
      .width(this.prominent ? 48 : 22).height(this.prominent ? 48 : 22)
      .rotate({angle: this.angle})
      .onAppear(() => {
        this.getUIContext().animateTo({duration: 3600, iterations: -1, curve: Curve.Linear}, () => {
          this.angle = 360;
        })
      })
  }

  build() {
    if (this.prominent) {
      Column({space: 14}) {
        this.aperture()
        Text(this.label).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#E8DFD3')
      }
    } else {
      Row({space: 8}) {
        this.aperture()
        Text(this.label).fontSize(13).lineHeight(16).fontWeight(FontWeight.Medium).fontColor('#F3EBDF')
          .translate({x: this.label === '正在保存' ? (this.helpVisible ? 1.5 : (22 + 8) / 2) : 0})
        if (this.label === '正在保存') { this.saveHelp() }
      }.padding({left: 10, right: 14, top: 7, bottom: 7})
        .backgroundColor('#ED242323').borderRadius(20).border({width: 0.5, color: '#50D6B78D'})
    }
  }
}

interface Stock {
  id: string;
  name: string;
  paper: boolean;
  group: string;
  reversal: boolean;
  monochrome: boolean;
  targetPrint: string;
}
@Concurrent
function renderPixels(path: string, input: ArrayBuffer, width: number, height: number,
  params: string, linear: boolean, rotation: number, geometry: PhotoGeometry, operation: number,
  fastMode: boolean): image.PixelMap {
  const rgba = linear ? nativeEngine.renderLinear(path, input, width, height, params, operation, fastMode) :
    nativeEngine.render(path, input, width, height, params, operation, fastMode);
  return geometryMap(rgba, width, height, rotation, geometry);
}

@Concurrent
function frameExport(photo: image.PixelMap, border: FrameBorder, overlay: image.PixelMap | undefined,
  film: string, framing: BorderFraming | undefined): image.PixelMap {
  return composeBorder(photo, border, overlay, film, 0, framing);
}

@Concurrent
function clearNativeResources(releaseEngine: boolean): void { nativeEngine.clearResources(releaseEngine); }

@Concurrent
function decodeRaw(fd: number, cacheDir: string, operation: number): RawFrame {
  return nativeEngine.decodeRaw(fd, cacheDir, operation);
}

@Concurrent
function predecodeRaw(fd: number, cacheDir: string, operation: number, fastMode: boolean): boolean {
  return nativeEngine.predecodeRaw(fd, cacheDir, operation, fastMode);
}

@Concurrent
function renderRawPrint(path: string, fd: number, params: string, cacheDir: string, rotation: number,
  geometry: PhotoGeometry, operation: number, fastMode: boolean): image.PixelMap {
  const frame = nativeEngine.renderRaw(path, fd, params, cacheDir, operation, fastMode);
  return geometryMap(frame.pixels, frame.width, frame.height, rotation, geometry);
}

@CustomDialog
struct LeaveEditorDialog {
  controller: CustomDialogController;
  title: string = '放弃本次调整？';
  detail: string = '未保存的调整将丢失，原照片会保留。';
  confirmLabel: string = '放弃调整';
  keepLabel: string = '继续编辑';
  keep: () => void = () => {};
  discard: () => void = () => {};

  build() {
    Column({space: 12}) {
      Text(this.title).fontSize(20).fontWeight(FontWeight.Medium).fontColor('#F2ECE5')
      Text(this.detail).fontSize(14).fontColor('#C8BEB2')
      Row({space: 10}) {
        Button(this.confirmLabel, {type: ButtonType.Normal})
          .layoutWeight(1).height(44).borderRadius(CORNER_RADIUS).backgroundColor('#343233').fontColor('#ECE5DC')
          .onClick(() => { this.discard(); this.controller.close(); })
        Button(this.keepLabel, {type: ButtonType.Normal})
          .layoutWeight(1).height(44).borderRadius(CORNER_RADIUS).backgroundColor('#EFBD70').fontColor('#32271D')
          .defaultFocus(true).onClick(() => { this.keep(); this.controller.close(); })
      }.width('100%').margin({top: 10})
    }.width('88%').constraintSize({maxWidth: 360}).alignItems(HorizontalAlign.Start)
      .padding(22).borderRadius(16).backgroundColor('#242426').border({width: 0.5, color: '#50473F'})
  }
}

@Entry
@Component
struct Index {
  @StorageProp('exportFormat') private exportFormat: string = 'JPEG';
  @StorageProp('exportQuality') private exportQuality: string = 'HIGH';
  @StorageProp('darkroomTop') private topInset: number = 0;
  @StorageProp('darkroomBottom') private bottomInset: number = 0;
  @StorageProp('darkroomLeft') private leftInset: number = 0;
  @StorageProp('darkroomRight') private rightInset: number = 0;
  @State private films: Stock[] = [];
  @State private papers: Stock[] = [];
  @State private film: string = '';
  @State private paper: string = '';
  @State private preview: image.PixelMap | undefined = undefined;
  @State private busy: boolean = true;
  @State private message: string = '';
  @State private saveHelpOpen: boolean = false;
  private sourceUri: string = '';
  private sourceName: string = '';
  private pendingRecipe: HomeRecipe | undefined = undefined;
  @State private homeCardIndex: number = 0;
  private assets: string = '';
  private input: ArrayBuffer | undefined = undefined;
  private linear: boolean = false;
  private rawRotation: number = 0;
  private widthPx: number = 0;
  private heightPx: number = 0;

  private editorActive: boolean = false;
  private reviewTimer: number = -1;
  private predecodeTimer: number = -1;
  private predecodeOperation: number = 0;
  private predecodeRevision: number = 0;

  aboutToAppear(): void { this.editorActive = true; this.prepare(); }

  onPageShow(): void {
    if (this.editorActive && this.linear && this.sourceUri && !this.importing && !this.exportAttempt) {
      this.scheduleRawPredecode(200);
    }
  }

  onPageHide(): void { this.cancelReviewPrompt(); }

  aboutToDisappear(): void {
    this.editorActive = false;
    this.cancelReviewPrompt();
    this.cancelRawPredecode();
    this.stopImport();
    this.importRevision++;
    this.stopPreview(false);
    if (this.exportAttempt && !this.exportAttempt.committing) this.finishSaveConfirmation(true);
    this.resumeSaveAuthorization();
    this.releaseNativeResources();
  }

  private cancelRawPredecode(): void {
    if (this.predecodeTimer !== -1) {
      clearTimeout(this.predecodeTimer);
      this.predecodeTimer = -1;
    }
    this.predecodeRevision++;
    if (this.predecodeOperation) {
      nativeEngine.cancelOperation(this.predecodeOperation);
    }
  }

  private scheduleRawPredecode(delayMs: number = 350): void {
    this.cancelRawPredecode();
    if (!this.editorActive || !this.linear || !this.sourceUri || this.importing || this.exportAttempt) return;
    const revision = this.predecodeRevision;
    const uri = this.sourceUri;
    const quality = normalizeExportQuality(this.exportQuality);
    const fastExport = isFastExport(quality);
    this.predecodeTimer = setTimeout(() => {
      this.predecodeTimer = -1;
      if (revision !== this.predecodeRevision || !this.editorActive || !this.linear ||
        this.sourceUri !== uri || this.importing || this.exportAttempt) return;
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const cacheDir = ctx.cacheDir;
      const op = nativeEngine.beginOperation();
      this.predecodeOperation = op;
      const started = Date.now();
      let file: fs.File | undefined;
      try {
        file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
        const task = new taskpool.Task(predecodeRaw, file.fd, cacheDir, op, fastExport);
        void taskpool.execute(task, taskpool.Priority.LOW).then((ok: Object) => {
          if (ok === true && revision === this.predecodeRevision && this.sourceUri === uri) {
            AppLog.record('RAW predecode ready quality=' + quality + ' ms=' + (Date.now() - started));
          }
        }).catch(() => {
          // Ignore background pre-decode cancellations and errors; Save will decode if needed.
        }).finally(() => {
          try { if (file) fs.closeSync(file); } catch (_) {}
          nativeEngine.endOperation(op);
          if (this.predecodeOperation === op) this.predecodeOperation = 0;
        });
      } catch (_) {
        try { if (file) fs.closeSync(file); } catch (_) {}
        nativeEngine.endOperation(op);
        if (this.predecodeOperation === op) this.predecodeOperation = 0;
      }
    }, delayMs);
  }

  private releaseNativeResources(): void {
    if (this.busy || this.renderInFlight) return;
    resourceCleanup = resourceCleanup.then(async () => {
      await taskpool.execute(new taskpool.Task(clearNativeResources, true));
    }).catch((err: BusinessError) => {
      AppLog.failure('release resources', err);
    });
  }

  private async prepare(): Promise<void> {
    this.busy = true; this.message = '';
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const rm = ctx.resourceManager;
      const decoder = util.TextDecoder.create('utf-8');
      const stocks: Stock[] = JSON.parse(decoder.decodeWithStream(await rm.getRawFileContent('stocks.json'))) as Stock[];
      if (!this.editorActive) return;
      this.films = stocks.filter((s: Stock) => !s.paper).sort((a: Stock, b: Stock) => a.group.localeCompare(b.group));
      this.papers = stocks.filter((s: Stock) => s.paper);
      this.films.unshift({id: '', name: '未选中', paper: false, group: '', reversal: false,
        monochrome: false, targetPrint: DEFAULT_PAPER});
      this.papers.unshift({id: '', name: '未选中', paper: true, group: '', reversal: false,
        monochrome: false, targetPrint: DEFAULT_PAPER});
      this.loadMaterialOrder(ctx);
      const dir = ctx.filesDir + '/assets-v1';
      const readyPath = dir + '/ready';
      const stamp = decoder.decodeWithStream(await rm.getRawFileContent('engine-stamp.txt')).trim();
      let currentStamp = '';
      if (fs.accessSync(readyPath)) {
        try { currentStamp = fs.readTextSync(readyPath).trim(); } catch (_) { currentStamp = ''; }
      }
      if (!stamp || currentStamp !== stamp) {
        if (fs.accessSync(readyPath)) fs.unlinkSync(readyPath);
        const list = decoder.decodeWithStream(await rm.getRawFileContent('engine-files.txt')).trim().split('\n');
        for (const name of list) {
          const target = dir + '/' + name;
          const parent = target.substring(0, target.lastIndexOf('/'));
          if (!fs.accessSync(parent)) fs.mkdirSync(parent, true);
          const bytes = await rm.getRawFileContent(name);
          if (!this.editorActive) return;
          const file = fs.openSync(target, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
          try {
            if (fs.writeSync(file.fd, bytes.slice().buffer) !== bytes.byteLength) throw new Error('资源写入不完整');
          } finally { fs.closeSync(file); }
        }
        const marker = fs.openSync(readyPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
        try { fs.writeSync(marker.fd, stamp); } finally { fs.closeSync(marker); }
      }
      this.assets = dir + '/engine';
      AppLog.record('assets ready');
    } catch (err) { this.message = '材料库加载失败'; AppLog.failure('assets', err as BusinessError); console.error('SpektraLab assets: ' + String(err)); }
    finally { this.busy = false; }
  }

  @State private original?: image.PixelMap = undefined;
  @State private compare: boolean = false;
  @State private zoom: number = 1;
  @State private dx: number = 0;
  @State private dy: number = 0;
  @State private tab: number = 0;
  @State private panel: number = 1;
  @State private panelPosition: number = 1;
  @State private windowWidth: number = 0;
  @State private windowHeight: number = 780;
  private dragStart: number = 1;
  private readonly tabMaterial: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.THIN, interactive: true
  });

  private wide(): boolean {
    return this.windowWidth >= 600;
  }

  private libraryProgress(): number {
    return Math.max(0, Math.min(1, this.panelPosition - 1));
  }

  private compactHeight(): number {
    return Math.min(310, this.windowHeight * 0.45) + HANDLE_HEIGHT - 2;
  }

  private panelHeight(): number {
    const compact = this.compactHeight();
    return this.panelPosition <= 1 ? COLLAPSED_HEIGHT + (compact - COLLAPSED_HEIGHT) * this.panelPosition :
      compact + (this.windowHeight * 0.63 - compact) * (this.panelPosition - 1);
  }

  private snapPanel(target: number): void {
    if (target !== 1) this.hideFan();
    this.panel = target;
    this.updateMaterialOrderHint();
    this.getUIContext().animateTo({curve: curves.interpolatingSpring(0, 1, 245, 23)}, () => {
      this.panelPosition = target;
    });
  }
  @State private rendering: boolean = false;
  private renderInFlight: boolean = false;
  private previewOperation: number = 0;
  @State private matched: boolean = false;
  @State private values: number[] = [0, 1, 1, 1];
  private pinchStart: number = 1;
  private panX: number = 0;
  private panY: number = 0;
  @State private extentX: number = 0;
  @State private extentY: number = 0;
  private version: number = 0;
  private dirty: boolean = false;
  private retryFilm: string = '';
  private retryPaper: string = '';
  private retryValues: number[] = [];
  private goodFilm: string = this.film;
  private goodPaper: string = this.paper;
  private goodValues: number[] = [0, 1, 1, 1];
  private readonly labels: string[] = ['曝光', '颗粒', '光晕', '眩光'];
  private readonly limits: number[] = [3, 2, 4, 30];

  private filmProfile(id: string): Stock {
    return this.films.find((stock: Stock) => stock.id === id)!;
  }

  // Native full-resolution exports automatically enable 256-row striping above 26 MP.
  private params(film: string, paper: string, linear: boolean): string {
    return JSON.stringify({ product_defaults: true, film_stock: film, print_stock: paper, scan_film: this.filmProfile(film).reversal,
      exposure_compensation_ev: this.values[0], grain_active: true, grain_amount: this.values[1],
      halation_active: true, halation_amount: this.values[2], glare_active: true, glare_amount: this.values[3],
      auto_exposure: true, auto_exposure_method: 'balanced',
      input_color_space: linear ? 'ProPhoto RGB' : 'sRGB', input_cctf_decoding: !linear,
      output_color_space: 'sRGB', output_cctf_encoding: true,
      striped: false, strip_rows: 0 });
  }

  private async pixels(input: ArrayBuffer, w: number, h: number, linear: boolean,
    film: string, paper: string, operation: number): Promise<image.PixelMap> {
    const pixels = input.slice(0);
    const task = new taskpool.Task(renderPixels, this.assets, pixels, w, h,
      this.params(film, paper, linear), linear, this.rawRotation, fullPhoto(), operation, true);
    task.setTransferList([pixels]);
    return await taskpool.execute(task) as image.PixelMap;
  }

  private async readPhoto(fd: number, preview: boolean, cancelled: () => boolean): Promise<RawFrame> {
    const source = image.createImageSource(fd);
    try {
      const info = await source.getImageInfo();
      if (cancelled()) throw new Error('Photo decode cancelled');
      const scale = preview ? Math.min(1, 1600 / Math.max(info.size.width, info.size.height)) : 1;
      const size: image.Size = { width: Math.max(1, Math.round(info.size.width * scale)),
        height: Math.max(1, Math.round(info.size.height * scale)) };
      const map = await source.createPixelMap({ desiredSize: size, editable: true,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        desiredDynamicRange: image.DecodingDynamicRange.SDR });
      try {
        if (cancelled()) throw new Error('Photo decode cancelled');
        // Convert pixels before discarding the source's ICC/color-space metadata.
        await map.applyColorSpace(colorSpaceManager.create(colorSpaceManager.ColorSpace.SRGB));
        let orientation = '1';
        try { orientation = await source.getImageProperty(image.PropertyKey.ORIENTATION); } catch (_) {}
        if (cancelled()) throw new Error('Photo decode cancelled');
        const names = ['Top-left','Top-right','Bottom-right','Bottom-left','Left-top','Right-top','Right-bottom','Left-bottom'];
        const o = Number(orientation) || names.indexOf(orientation) + 1;
        if (o === 2 || o === 5 || o === 7) await map.flip(true, false);
        if (o === 4) await map.flip(false, true);
        if (o === 3) await map.rotate(180);
        if (o === 5 || o === 8) await map.rotate(270);
        if (o === 6 || o === 7) await map.rotate(90);
        const decoded = await map.getImageInfo();
        const actual = decoded.size;
        const buf = new ArrayBuffer(actual.width * actual.height * 4);
        await map.readPixelsToBuffer(buf);
        straightPhotoPixels(buf, decoded.alphaType === image.AlphaType.PREMUL);
        return { pixels: buf, width: actual.width, height: actual.height };
      } finally { await map.release(); }
    } finally { await source.release(); }
  }

  @State private importing: boolean = false;
  private importRevision: number = 0;
  private importOperation: number = 0;
  private exportAttempt?: ExportAttempt;
  @State private waitingForSaveGrant: boolean = false;
  private resumeSaveGrant?: () => void;
  private replacementUri: string = '';
  private replacementRecipe?: HomeRecipe;

  @State private borderId: string = '';
  @State private borderLoading: boolean = false;
  @State private borderListWidth: number = 336;
  private readonly borderStripScroller: Scroller = new Scroller();
  private readonly materialStripScroller: Scroller = new Scroller();
  @State private fanVisible: boolean = false;
  @State private fanPosition: number = 0;
  @State private fanPages: MaterialPage[] = [];
  @State private fanHeight: number = 170;
  private borderRequest: number = 0;
  private borderOverlay?: image.PixelMap;
  @State private borderSourceRevision: number = 0;
  private borders: FrameBorder[] = BUILT_IN_FRAME_BORDERS;
  @State private borderOrder: string[] = [];
  @State private showBorderOrderHint: boolean = false;
  private borderOrderHintSeen: boolean = false;
  @State private framed: image.PixelMap | undefined = undefined;

  @State private cropOpen: boolean = false;
  @State private framingOpen: boolean = false;
  private readonly borderFramings: Map<string, BorderFraming> = new Map<string, BorderFraming>();
  @State private croppedOriginal?: image.PixelMap = undefined;
  @State private croppedPreview?: image.PixelMap = undefined;
  private geometry: PhotoGeometry = fullPhoto();

  private hasGeometry(): boolean { return this.geometry.angle !== 0 || hasCrop(this.geometry); }

  private printMap(): image.PixelMap | undefined {
    return this.framed ?? this.borderBase();
  }

  private displayedPhoto(): image.PixelMap | undefined {
    return this.compare ? this.croppedOriginal ?? this.original : this.printMap();
  }

  private applyGeometry(next: PhotoGeometry): void {
    if (!this.original) return;
    const current = this.geometry;
    if (current.angle === next.angle && current.left === next.left && current.top === next.top &&
      current.right === next.right && current.bottom === next.bottom &&
      (current.ratio === next.ratio || !hasCrop(next))) {
      this.geometry = next;
      this.cropOpen = false;
      return;
    }
    let original: image.PixelMap | undefined;
    let preview: image.PixelMap | undefined;
    try {
      original = editedPhoto(this.original, next);
      if (this.preview) preview = editedPhoto(this.preview, next);
      this.replaceFrame(preview ?? this.preview ?? original ?? this.original, this.preview ?? this.original,
        this.goodFilm, false);
      this.borderFramings.clear();
      const oldOriginal = this.croppedOriginal;
      const oldPreview = this.croppedPreview;
      this.croppedOriginal = original;
      this.croppedPreview = preview;
      this.borderSourceRevision++;
      this.geometry = next;
      this.compare = false;
      this.resetZoom();
      this.dirty = true;
      this.cropOpen = false;
      this.message = '';
      oldOriginal?.release();
      oldPreview?.release();
      AppLog.record('composition applied ' + this.displayedWidth() + 'x' + this.displayedHeight());
    } catch (err) {
      original?.release();
      preview?.release();
      AppLog.failure('composition', err as BusinessError);
      this.cropOpen = false;
      this.message = '裁切或旋转失败，请重试';
    }
  }

  private resetGeometry(): void {
    this.cropOpen = false;
    this.framingOpen = false;
    this.geometry = fullPhoto();
    const croppedOriginal = this.croppedOriginal;
    const croppedPreview = this.croppedPreview;
    this.croppedOriginal = undefined;
    this.croppedPreview = undefined;
    croppedOriginal?.release();
    croppedPreview?.release();
  }

  private borderBase(): image.PixelMap | undefined {
    return this.croppedPreview ?? this.preview ?? this.croppedOriginal ?? this.original;
  }

  private currentBorder(): FrameBorder {
    return this.borders.find((border: FrameBorder) => border.id === this.borderId) ?? NO_FRAME;
  }

  private borderFilm(film: string): string {
    return this.filmProfile(film || DEFAULT_FILM).name;
  }

  private framingKey(border: FrameBorder, angle: number): string {
    return border.id + ':' + angle;
  }

  private framingFor(border: FrameBorder, angle: number = this.geometry.angle): BorderFraming | undefined {
    return this.borderFramings.get(this.framingKey(border, angle));
  }

  private canAdjustFraming(): boolean {
    const border = this.currentBorder();
    const size = this.borderBase()?.getImageInfoSync().size;
    if (!size || !border.windows.length) return false;
    return !!this.framingFor(border) || border.windows.some((_window: number[], index: number) => {
      const aperture = borderAperture(border, index);
      return Math.min(Math.abs(size.width - size.height * aperture),
        Math.abs(size.height - size.width / aperture)) > 1;
    });
  }

  private defaultFraming(): PhotoGeometry {
    const source = this.preview ?? this.original;
    const size = source!.getImageInfoSync().size;
    const aspect = this.geometry.angle % 180 === 0 ? size.width / size.height : size.height / size.width;
    return centeredBorderFraming(this.geometry, borderAperture(this.currentBorder()), aspect);
  }

  private setFramed(next: image.PixelMap | undefined): void {
    const old = this.framed;
    this.framed = next;
    old?.release();
  }

  private replaceFrame(photo: image.PixelMap, full: image.PixelMap, film: string,
    useSavedFraming: boolean = true): void {
    const border = this.currentBorder();
    const framing = useSavedFraming ? this.framingFor(border) : undefined;
    this.setFramed(border.id ? composeBorder(framing ? full : photo, border, this.borderOverlay,
      this.borderFilm(film), 0, framing) : undefined);
  }

  private applyBorderFraming(next: PhotoGeometry): void {
    const border = this.currentBorder();
    const photo = this.borderBase();
    const full = this.preview ?? this.original;
    if (!photo || !full || !borderAperture(border)) return;
    const initial = this.defaultFraming();
    const isDefault = Math.abs(next.left - initial.left) < 1e-6 && Math.abs(next.right - initial.right) < 1e-6 &&
      Math.abs(next.top - initial.top) < 1e-6 && Math.abs(next.bottom - initial.bottom) < 1e-6;
    const key = this.framingKey(border, this.geometry.angle);
    const size = photo.getImageInfoSync().size;
    const framing: BorderFraming = {angle: next.angle, ratio: next.ratio, left: next.left,
      top: next.top, right: next.right, bottom: next.bottom, baseAspect: size.width / size.height};
    try {
      this.setFramed(composeBorder(isDefault ? photo : full, border, this.borderOverlay,
        this.borderFilm(this.goodFilm), 0, isDefault ? undefined : framing));
      if (isDefault) this.borderFramings.delete(key);
      else this.borderFramings.set(key, framing);
      this.borderSourceRevision++;
      this.dirty = true;
      this.resetZoom();
      this.message = '';
      this.framingOpen = false;
      AppLog.record('border framing applied ' + border.id);
    } catch (err) {
      AppLog.failure('border framing', err as BusinessError);
      this.framingOpen = false;
      this.message = '边框取景应用失败，请重试';
    }
  }

  private resetBorder(): void {
    this.borderRequest++;
    this.borderLoading = false;
    this.borderId = '';
    this.borderFramings.clear();
    const framed = this.framed;
    this.framed = undefined;
    framed?.release();
    this.borderOverlay?.release();
    this.borderOverlay = undefined;
  }

  private async chooseBorder(border: FrameBorder): Promise<void> {
    if (this.busy || !this.original) return;
    if (!this.borderLoading && border.id === this.borderId) return;
    const request = ++this.borderRequest;
    this.borderLoading = true;
    let overlay: image.PixelMap | undefined;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      overlay = await loadBorderOverlay(context.resourceManager, border);
      const framing = this.framingFor(border);
      const photo = framing ? this.preview ?? this.original : this.borderBase();
      if (!photo || request !== this.borderRequest || !this.editorActive) return;
      const next = border.id ? composeBorder(photo, border, overlay, this.borderFilm(this.goodFilm), 0, framing) :
        undefined;
      const old = this.framed;
      const oldOverlay = this.borderOverlay;
      this.framed = next;
      this.borderOverlay = overlay;
      overlay = undefined;
      this.borderId = border.id;
      this.compare = false;
      this.resetZoom();
      this.dirty = true;
      if (!this.rendering) this.message = '';
      old?.release();
      oldOverlay?.release();
      AppLog.record('border selected ' + (border.id || 'none') + ' ' + this.displayedWidth() + 'x' + this.displayedHeight());
    } catch (err) {
      if (request === this.borderRequest) {
        AppLog.failure('border', err as BusinessError);
        this.message = '边框生成失败，请重试';
      }
    } finally {
      overlay?.release();
      if (request === this.borderRequest) this.borderLoading = false;
    }
  }

  @State private choosingPhoto: boolean = false;

  private choosePhoto(recipe?: HomeRecipe): void {
    if ((this.busy && !this.importing) || !this.assets) return;
    this.stopImport();
    this.pendingRecipe = recipe;
    this.choosingPhoto = true;
  }

  private cancelPhoto(): void {
    this.pendingRecipe = undefined;
    this.choosingPhoto = false;
  }

  private async confirmPhoto(uri: string): Promise<void> {
    const recipe = this.pendingRecipe;
    this.cancelPhoto();
    this.requestPhoto(uri, recipe);
  }

  private async chooseFile(): Promise<void> {
    if ((this.busy && !this.importing) || !this.assets) return;
    this.stopImport();
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      const uris = await new picker.DocumentViewPicker(context).select(options);
      if (this.editorActive && uris.length > 0) this.requestPhoto(uris[0]);
    } catch (err) {
      AppLog.failure('file picker', err as BusinessError);
      this.message = '无法打开文件选择器，请重试';
    }
  }

  private requestPhoto(uri: string, recipe?: HomeRecipe): void {
    if (this.original && (this.dirty || this.rendering || !this.matched || this.borderLoading)) {
      this.replacementUri = uri;
      this.replacementRecipe = recipe;
      this.replaceDialog.open();
    } else {
      this.open(uri, recipe);
    }
  }

  private finishReplacement(replace: boolean): void {
    const uri = this.replacementUri;
    const recipe = this.replacementRecipe;
    this.replacementUri = '';
    this.replacementRecipe = undefined;
    if (replace && uri) this.open(uri, recipe);
  }

  private currentImport(revision: number): boolean {
    return this.editorActive && revision === this.importRevision;
  }

  private stopImport(): void {
    if (!this.importing) return;
    nativeEngine.cancelOperation(this.importOperation);
    this.importRevision++;
    this.importing = false;
    this.busy = false;
    this.message = '';
    AppLog.record('import cancelled');
  }

  private async open(uri: string, recipe?: HomeRecipe): Promise<void> {
    if (this.busy || !this.assets) return;
    const revision = ++this.importRevision;
    this.stopPreview(true);
    this.borderRequest++;
    this.borderLoading = false;
    this.busy = true;
    this.importing = true;
    this.message = '';
    const operation = nativeEngine.beginOperation();
    this.importOperation = operation;
    let imported = false;
    let raw = false;
    try {
      if (recipe && (!this.films.some((stock: Stock) => stock.id === recipe.film) ||
        !this.papers.some((stock: Stock) => stock.id === recipe.paper))) {
        throw new Error('卡片材料不存在');
      }
      this.message = '正在导入';
      const name = new fileUri.FileUri(uri).name;
      const knownPhoto = /\.(jpe?g|png|heic|heif|webp|gif|bmp|avif)$/i.test(name);
      const knownRaw = /\.(dng|cr[23w]|nef|nrw|arw|srf|sr2|raf|rw2|orf|pef|ptx|3fr|fff|iiq|rwl|srw|x3f|mrw|mos|kdc|dcr|erf|mef|raw)$/i.test(name);
      this.cancelRawPredecode();
      await resourceCleanup;
      if (!this.currentImport(revision)) return;
      await taskpool.execute(new taskpool.Task(clearNativeResources, false));
      if (!this.currentImport(revision)) return;
      AppLog.record('import start');
      const cacheDir = (this.getUIContext().getHostContext() as common.UIAbilityContext).cacheDir;
      const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      let frame: RawFrame;
      let rotation = 0;
      try {
        if (knownPhoto) {
          frame = await this.readPhoto(file.fd, true, () => !this.currentImport(revision));
        } else {
          try {
            frame = await taskpool.execute(new taskpool.Task(decodeRaw, file.fd, cacheDir, operation)) as RawFrame;
            raw = true;
            AppLog.record('RAW decoded bytes=' + fs.statSync(file.fd).size + ' ' + (frame.rawInfo ?? ''));
          } catch (err) {
            if (!this.currentImport(revision)) return;
            if (knownRaw) throw new Error((err as BusinessError).message ?? String(err));
            frame = await this.readPhoto(file.fd, true, () => !this.currentImport(revision));
          }
        }
        if (!this.currentImport(revision)) return;
        if (raw && frame.displayPixels) {
          rotation = await rawPreviewRotation(file.fd, frame.displayPixels, frame.width, frame.height);
        }
      } finally { fs.closeSync(file); }
      if (!this.currentImport(revision)) return;
      const w = frame.width, h = frame.height;
      if (raw && !frame.displayPixels) throw new Error('RAW 预览数据缺失');
      const buf = frame.displayPixels ?? frame.pixels;
      const original = orientedPixelMap(buf, w, h, rotation);
      const oldOriginal = this.original;
      this.resetGeometry();
      this.resetBorder();
      this.clearMaterials();
      this.sourceUri = uri;
      this.sourceName = name;
      this.input = frame.pixels; this.linear = raw; this.widthPx = w; this.heightPx = h;
      this.rawRotation = rotation;
      this.original = original;
      this.updateMaterialOrderHint();
      this.borderSourceRevision++;
      AppLog.record((raw ? 'import RAW complete ' : 'import photo complete ') +
        (rotation ? h + 'x' + w + ' rotation=' + rotation : w + 'x' + h));
      this.compare = false; this.resetZoom(); this.dirty = false; this.matched = true;
      this.message = frame.warning ?? '';
      oldOriginal?.release();
      imported = true;
    } catch (err) {
      if (!this.currentImport(revision)) return;
      this.message = '无法处理这张照片，请选择其他照片';
      AppLog.failure('import', err as BusinessError); console.error('SpektraLab import: ' + String(err));
    } finally {
      nativeEngine.endOperation(operation);
      if (this.importOperation === operation) this.importOperation = 0;
      if (revision === this.importRevision) {
        this.importing = false; this.busy = false;
      }
      if (!this.editorActive) this.releaseNativeResources();
    }
    if (imported && recipe && this.editorActive) {
      this.film = recipe.film;
      this.paper = recipe.paper;
      if (!this.filmProfile(recipe.film).monochrome) this.lastColorPaper = recipe.paper;
      AppLog.record('home recipe ' + recipe.id + ' ' + recipe.film + ' ' + recipe.paper);
      await this.process();
    }
    if (imported && raw && this.editorActive && this.sourceUri === uri) {
      this.scheduleRawPredecode(350);
    }
  }

  private stopPreview(restore: boolean): void {
    const wasRendering = this.rendering;
    this.version++;
    nativeEngine.cancelOperation(this.previewOperation);
    this.rendering = false;
    if (!wasRendering) return;
    if (restore) {
      this.film = this.goodFilm;
      this.paper = this.goodPaper;
      this.values = this.goodValues.slice();
      this.matched = true;
    }
    if (this.message === '正在冲印') this.message = '';
    AppLog.record('render cancelled');
  }

  private async process(): Promise<void> {
    this.version++;
    nativeEngine.cancelOperation(this.previewOperation);
    if (!this.input || !this.hasMaterials()) return;
    this.matched = false;
    this.rendering = true;
    this.message = '正在冲印';
    if (this.renderInFlight) return;
    this.renderInFlight = true;
    while (this.editorActive && this.rendering && this.input && this.hasMaterials()) {
      const version = this.version;
      const sentValues = this.values.slice();
      const operation = nativeEngine.beginOperation();
      this.previewOperation = operation;
      AppLog.record('render ' + this.film + ' ' + this.paper);
      try {
        const next = await this.pixels(this.input, this.widthPx, this.heightPx, this.linear, this.film, this.paper, operation);
        if (version !== this.version) {
          await next.release();
          AppLog.record('render superseded');
          continue;
        }
        let cropped: image.PixelMap | undefined;
        try {
          cropped = editedPhoto(next, this.geometry);
          this.replaceFrame(cropped ?? next, next, this.film);
        } catch (err) {
          await cropped?.release();
          await next.release();
          throw new Error(String(err));
        }
        const old = this.preview, oldCropped = this.croppedPreview;
        this.preview = next; this.croppedPreview = cropped;
        old?.release(); oldCropped?.release();
        this.goodFilm = this.film; this.goodPaper = this.paper; this.goodValues = sentValues;
        this.borderSourceRevision++;
        AppLog.record('render complete');
        this.dirty = true; this.matched = sentValues.every((v: number, i: number) => v === this.values[i]); this.message = '';
      } catch (err) {
        if (version !== this.version) {
          AppLog.record('render superseded');
          continue;
        }
        this.retryFilm = this.film; this.retryPaper = this.paper; this.retryValues = this.values.slice();
        this.film = this.goodFilm; this.paper = this.goodPaper; this.values = this.goodValues.slice();
        this.matched = true; this.message = '冲印失败，请重试或更换材料';
        AppLog.failure('render', err as BusinessError); console.error('SpektraLab render: ' + String(err));
      } finally {
        nativeEngine.endOperation(operation);
        this.previewOperation = 0;
      }
      break;
    }
    this.renderInFlight = false;
    this.rendering = false;
    if (!this.input || !this.editorActive) this.releaseNativeResources();
  }

  @State private cardWidth: number = 108;
  private lastColorPaper: string = DEFAULT_PAPER;
  @State private filmOrder: string[] = [];
  @State private paperOrder: string[] = [];
  @State private showMaterialOrderHint: boolean = false;
  private materialOrderHintSeen: boolean = false;
  private materialSettings?: preferences.Preferences;

  private loadMaterialOrder(context: common.UIAbilityContext): void {
    const filmDefaults = ['kodak_gold_200', 'kodak_portra_400', 'cinestill_800t']
      .concat(this.films.map((stock: Stock) => stock.id));
    this.borders = availableFrameBorders(context.resourceManager);
    const borderDefaults = this.borders.map((border: FrameBorder) => border.id);
    this.borderOrder = borderDefaults.slice();
    const paperDefaults = [DEFAULT_PAPER].concat(this.papers.map((stock: Stock) => stock.id));
    this.filmOrder = materialOrder(filmDefaults, []);
    this.paperOrder = materialOrder(paperDefaults, []);
    try {
      const settings = preferences.getPreferencesSync(context, {name: 'settings'});
      this.materialSettings = settings;
      this.materialOrderHintSeen = settings.getSync('materialOrderHintSeen', false) === true;
      this.borderOrderHintSeen = settings.getSync('borderOrderHintSeen', false) === true;
      this.borderOrder = materialOrder(borderDefaults, settings.getSync('borderOrder', []) as string[]);
      this.filmOrder = materialOrder(filmDefaults, settings.getSync('filmOrder', []) as string[]);
      this.paperOrder = materialOrder(paperDefaults, settings.getSync('paperOrder', []) as string[]);
    } catch (err) { AppLog.failure('material order settings', err as BusinessError); }
  }

  private async saveMaterialPreference(key: string, value: string[] | boolean): Promise<void> {
    try {
      if (!this.materialSettings) return;
      this.materialSettings.putSync(key, value);
      await this.materialSettings.flush();
    } catch (err) { AppLog.failure('material order save', err as BusinessError); }
  }

  private updateMaterialOrderHint(): void {
    const expanded = !!this.original && (this.panel === 2 || this.wide());
    if (!expanded || this.tab !== BORDER_TAB) {
      this.showBorderOrderHint = false;
    } else if (!this.borderOrderHintSeen) {
      this.borderOrderHintSeen = true;
      this.showBorderOrderHint = true;
      this.saveMaterialPreference('borderOrderHintSeen', true);
    }
    if (!expanded || this.tab > 1) {
      this.showMaterialOrderHint = false;
    } else if (!this.materialOrderHintSeen) {
      this.materialOrderHintSeen = true;
      this.showMaterialOrderHint = true;
      this.saveMaterialPreference('materialOrderHintSeen', true);
    }
  }

  private orderedStocks(): Stock[] {
    const paper = this.tab === 1;
    const all = paper ? this.papers : this.films;
    const film = this.filmProfile(this.film);
    const ordered: Stock[] = [];
    for (const id of paper ? this.paperOrder : this.filmOrder) {
      const stock = all.find((item: Stock) => item.id === id);
      if (stock && (!paper || stock.monochrome === film.monochrome)) ordered.push(stock);
    }
    return ordered;
  }

  private moveStock(from: number, to: number): void {
    const paper = this.tab === 1;
    const current = paper ? this.paperOrder : this.filmOrder;
    const next = moveVisibleMaterial(current, this.orderedStocks().map((stock: Stock) => stock.id), from, to);
    if (next === current) return;
    if (paper) this.paperOrder = next;
    else this.filmOrder = next;
    this.saveMaterialPreference(paper ? 'paperOrder' : 'filmOrder', next);
  }
  private resetZoom(): void { this.zoom = 1; this.dx = 0; this.dy = 0; }
  private zoomTo(value: number): void {
    this.zoom = Math.max(1, Math.min(5, value));
    this.move(this.dx, this.dy);
  }
  private displayedWidth(): number {
    return this.displayedPhoto()?.getImageInfoSync().size.width ?? 1;
  }
  private displayedHeight(): number {
    return this.displayedPhoto()?.getImageInfoSync().size.height ?? 1;
  }
  private fittedScale(): number {
    if (!this.widthPx || !this.heightPx) return 0;
    const gutter = this.framed && !this.compare ? 16 : 0;
    return Math.min(Math.max(0, this.extentX - gutter) / this.displayedWidth(),
      Math.max(0, this.extentY - gutter) / this.displayedHeight());
  }
  private move(x: number, y: number): void {
    const scale = this.fittedScale();
    const maxX = Math.max(0, (this.displayedWidth() * scale * this.zoom - this.extentX) / 2);
    const maxY = Math.max(0, (this.displayedHeight() * scale * this.zoom - this.extentY) / 2);
    this.dx = Math.max(-maxX, Math.min(maxX, x)); this.dy = Math.max(-maxY, Math.min(maxY, y));
  }
  private changeTab(index: number): void {
    this.hideFan();
    this.tab = index;
    this.updateMaterialOrderHint();
  }
  private leaveDialog: CustomDialogController = new CustomDialogController({
    builder: LeaveEditorDialog({discard: () => this.closePhoto()}),
    customStyle: true, alignment: DialogAlignment.Center, autoCancel: true
  });
  private replaceDialog: CustomDialogController = new CustomDialogController({
    builder: LeaveEditorDialog({
      title: '替换当前照片？', detail: '新照片导入成功后，本次未保存的调整会丢失。',
      confirmLabel: '替换照片', discard: () => this.finishReplacement(true), keep: () => this.finishReplacement(false)
    }),
    customStyle: true, alignment: DialogAlignment.Center, autoCancel: true,
    cancel: () => this.finishReplacement(false)
  });
  private stopSaveDialog: CustomDialogController = new CustomDialogController({
    builder: LeaveEditorDialog({
      title: '取消本次保存？', detail: '当前调整会保留，可以稍后再保存。',
      confirmLabel: '取消保存', keepLabel: '继续保存',
      discard: () => this.finishSaveConfirmation(true), keep: () => this.finishSaveConfirmation(false)
    }),
    customStyle: true, alignment: DialogAlignment.Center, autoCancel: true,
    cancel: () => this.finishSaveConfirmation(false)
  });

  private finishSaveConfirmation(cancel: boolean): void {
    const attempt = this.exportAttempt;
    if (!attempt) return;
    attempt.resolveConfirmation(cancel);
    if (!cancel) return;
    nativeEngine.cancelOperation(attempt.nativeOperation);
    this.exportAttempt = undefined;
    this.busy = false;
    this.message = '';
    this.saveHelpOpen = false;
    this.resumeSaveAuthorization();
    AppLog.record('export cancelled');
  }

  private resumeSaveAuthorization(): void {
    const resume = this.resumeSaveGrant;
    this.resumeSaveGrant = undefined;
    this.waitingForSaveGrant = false;
    resume?.();
  }

  private async publishExport(ctx: common.UIAbilityContext, attempt: ExportAttempt, temp: string,
    extension: string, title: string): Promise<string | undefined> {
    const library = photoAccessHelper.getPhotoAccessHelper(ctx);
    while (await attempt.beginCommit()) {
      const request = photoAccessHelper.MediaAssetChangeRequest.createAssetRequest(
        ctx, photoAccessHelper.PhotoType.IMAGE, extension, {title: title});
      request.addResource(photoAccessHelper.ResourceType.IMAGE_RESOURCE, fileUri.getUriFromPath(temp));
      const started = Date.now();
      try {
        await library.applyChanges(request);
        AppLog.record('export write ms=' + (Date.now() - started));
        return request.getAsset().displayName;
      } catch (err) {
        if ((err as BusinessError).code !== 201) throw new Error((err as BusinessError).message);
        attempt.committing = false;
        this.waitingForSaveGrant = true;
        this.message = '请再点一次保存，继续写入相册';
        await new Promise<void>((resolve) => { this.resumeSaveGrant = resolve; });
        if (!attempt.cancelled) this.message = '正在保存';
      }
    }
    return undefined;
  }

  private closePhoto(): void {
    this.hideFan();
    this.cancelRawPredecode();
    this.stopPreview(false);
    this.releaseNativeResources();
    this.input = undefined;
    const preview = this.preview, original = this.original;
    this.preview = undefined; this.original = undefined;
    this.resetBorder();
    this.resetGeometry();
    this.sourceUri = ''; this.sourceName = ''; this.widthPx = 0; this.heightPx = 0; this.linear = false;
    this.rawRotation = 0;
    this.film = ''; this.paper = ''; this.lastColorPaper = DEFAULT_PAPER;
    this.values = [0, 1, 1, 1];
    this.dirty = false; this.matched = false; this.message = '';
    this.tab = 0; this.panel = 1; this.panelPosition = 1; this.compare = false; this.resetZoom();
    this.updateMaterialOrderHint();
    preview?.release(); original?.release();
    this.scheduleReviewPrompt();
  }

  private cancelReviewPrompt(): void {
    if (this.reviewTimer >= 0) clearTimeout(this.reviewTimer);
    this.reviewTimer = -1;
  }

  private scheduleReviewPrompt(): void {
    this.cancelReviewPrompt();
    this.reviewTimer = setTimeout(() => {
      this.reviewTimer = -1;
      if (!this.editorActive || !AppStorage.get<boolean>('appInForeground') || this.busy ||
        this.original || this.importing || this.choosingPhoto) return;
      AppReviewService.requestIfEligible(this.getUIContext().getHostContext() as common.UIAbilityContext);
    }, 650);
  }

  onBackPress(): boolean {
    this.cancelReviewPrompt();
    if (this.choosingPhoto) { this.cancelPhoto(); return true; }
    if (this.cropOpen) { this.cropOpen = false; return true; }
    if (this.framingOpen) { this.framingOpen = false; return true; }
    if (this.exportAttempt) {
      this.saveHelpOpen = false;
      if (this.exportAttempt.requestConfirmation()) this.stopSaveDialog.open();
      return true;
    }
    if (this.importing) { this.stopImport(); return true; }
    if (this.rendering) { this.stopPreview(true); return true; }
    if (this.borderLoading) {
      this.borderRequest++;
      this.borderLoading = false;
      return true;
    }
    if (this.busy) return false;
    if (!this.original) return false;
    if (!this.wide() && this.panel === 2) { this.snapPanel(1); return true; }
    if (this.dirty || !this.matched) this.leaveDialog.open();
    else this.closePhoto();
    return true;
  }
  private async renderOriginal(params: string | undefined, geometry: PhotoGeometry,
    attempt: ExportAttempt, fastExport: boolean): Promise<image.PixelMap | undefined> {
    const cacheDir = (this.getUIContext().getHostContext() as common.UIAbilityContext).cacheDir;
    const source = fs.openSync(this.sourceUri, fs.OpenMode.READ_ONLY);
    try {
      if (this.linear) {
        return await taskpool.execute(new taskpool.Task(renderRawPrint, this.assets, source.fd, params ?? '', cacheDir,
          this.rawRotation, geometry, attempt.nativeOperation, fastExport), taskpool.Priority.HIGH) as image.PixelMap;
      }
      const frame = await this.readPhoto(source.fd, false, () => attempt.cancelled);
      if (attempt.cancelled) return undefined;
      if (params === undefined) {
        return geometryMap(frame.pixels, frame.width, frame.height, 0, geometry);
      }
      const task = new taskpool.Task(renderPixels, this.assets, frame.pixels,
        frame.width, frame.height, params, false, 0, geometry, attempt.nativeOperation, fastExport);
      task.setTransferList([frame.pixels]);
      return await taskpool.execute(task, taskpool.Priority.HIGH) as image.PixelMap;
    } finally { fs.closeSync(source); }
  }

  private rawSaveHint(): string {
    if (!this.original || !this.linear || this.hasMaterials()) return '';
    if (!this.film && !this.paper) return '保存 RAW 前请先选择胶片和相纸';
    return this.film ? '保存 RAW 前请先选择相纸' : '保存 RAW 前请先选择胶片';
  }

  private canSave(): boolean {
    return !!this.sourceUri && (this.hasMaterials() || (!this.linear && (this.hasGeometry() || !!this.borderId))) &&
      this.matched && !this.busy && !this.rendering && !this.borderLoading;
  }

  private async save(): Promise<void> {
    if (!this.canSave()) return;
    if (this.predecodeTimer !== -1) {
      clearTimeout(this.predecodeTimer);
      this.predecodeTimer = -1;
    }
    const attempt = new ExportAttempt();
    this.exportAttempt = attempt;
    this.busy = true;
    this.message = '正在保存';
    const started = Date.now();
    const border = this.currentBorder();
    const framing = this.framingFor(border);
    const geometry = framing ? fullPhoto() : this.geometry;
    const title = exportTitle(this.sourceName, this.film, this.paper);
    const filmName = this.borderFilm(this.film);
    const quality = normalizeExportQuality(this.exportQuality);
    const fastExport = isFastExport(quality);
    const params = this.hasMaterials() ? this.params(this.film, this.paper, this.linear) : undefined;
    AppLog.record('export start quality=' + quality);
    let print: image.PixelMap | undefined;
    let framed: image.PixelMap | undefined;
    let overlay: image.PixelMap | undefined;
    let temp: string = '';
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const encoder = image.createImagePacker();
      let mime: string;
      try { mime = exportMime(this.exportFormat, encoder.supportedFormats); }
      finally { await encoder.release(); }
      if (attempt.cancelled) return;
      const extension = exportExtension(mime);
      const renderStarted = Date.now();
      attempt.nativeOperation = nativeEngine.beginOperation();
      print = await this.renderOriginal(params, geometry, attempt, fastExport);
      if (!print || attempt.cancelled) return;
      AppLog.record('export render ms=' + (Date.now() - renderStarted));
      AppLog.record('export border ' + (border.id || 'none'));
      if (border.id) {
        overlay = await loadBorderOverlay(ctx.resourceManager, border);
        if (attempt.cancelled) return;
        framed = await taskpool.execute(new taskpool.Task(frameExport, print, border, overlay,
          filmName, framing), taskpool.Priority.HIGH) as image.PixelMap;
        if (attempt.cancelled) return;
      }
      const output = framed ?? print;
      const expected = output.getImageInfoSync().size;
      temp = ctx.cacheDir + '/print-' + util.generateRandomUUID() + '.' + extension;
      const file = fs.openSync(temp, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      try {
        const encodeStarted = Date.now();
        const packer = image.createImagePacker();
        try { await packer.packToFile(output, file.fd, {format: mime, quality: 95}); }
        finally { await packer.release(); }
        if (attempt.cancelled) return;
        AppLog.record('export encode ms=' + (Date.now() - encodeStarted));
        const bytes = fs.statSync(file.fd).size;
        if (!bytes) throw new Error('图片编码结果为空');
        const encoded = image.createImageSource(temp);
        try {
          const info = await encoded.getImageInfo();
          const sameFormat = info.mimeType === mime ||
            (['image/heic', 'image/heif'].includes(mime) && ['image/heic', 'image/heif'].includes(info.mimeType));
          if (!sameFormat || info.size.width !== expected.width || info.size.height !== expected.height) {
            throw new Error('编码后的图片格式或尺寸不一致');
          }
          AppLog.record('export verified ' + info.mimeType + ' ' + info.size.width + 'x' + info.size.height);
        } finally { await encoded.release(); }
      } finally { fs.closeSync(file); }

      const savedName = await this.publishExport(ctx, attempt, temp, extension, title);
      if (savedName === undefined) return;
      this.dirty = false; this.message = '已保存到相册';
      AppReviewService.recordExport(ctx);
      AppLog.record('export complete ' + mime + ' ' + expected.width + 'x' + expected.height);
      AppLog.record('export filename ' + savedName);
      AppLog.record('export total ms=' + (Date.now() - started));
    } catch (err) {
      if (!attempt.cancelled && this.exportAttempt === attempt) {
        this.message = '保存失败，请重试';
        AppLog.failure('export', err as BusinessError); console.error('SpektraLab export: ' + String(err));
      }
    } finally {
      nativeEngine.endOperation(attempt.nativeOperation);
      if (this.exportAttempt === attempt) {
        attempt.resolveConfirmation(false);
        this.exportAttempt = undefined;
        this.stopSaveDialog.close();
        this.busy = false;
        this.saveHelpOpen = false;
      }
      if (temp) {
        try { fs.unlinkSync(temp); } catch (err) { AppLog.failure('export cleanup', err as BusinessError); }
      }
      framed?.release(); print?.release(); overlay?.release();
      if (!this.editorActive) this.releaseNativeResources();
    }
  }

  @Builder
  action(label: string, fn: () => void, accent: boolean = false) {
    Button(label, {type: ButtonType.Normal}).borderRadius(CORNER_RADIUS).fontSize(16).height(48).fontColor(accent ? '#EFBD70' : '#ECEAE5')
      .backgroundColor('#303032').onClick(fn)
  }

  @Builder
  photo() {
    Stack({alignContent: Alignment.BottomEnd}) {
      Stack() {
        Image(this.displayedPhoto())
          .width(this.displayedWidth() * this.fittedScale()).height(this.displayedHeight() * this.fittedScale())
          .objectFit(ImageFit.Contain).borderRadius(this.framed && !this.compare ? 0 : CORNER_RADIUS).clip(true)
          .scale({x: this.zoom, y: this.zoom}).translate({x: this.dx, y: this.dy})
      }.width('100%').height('100%').borderRadius(CORNER_RADIUS).clip(true)
        .onAreaChange((_a, b) => { this.extentX = Number(b.width); this.extentY = Number(b.height); this.move(this.dx, this.dy); })
        .gesture(GestureGroup(GestureMode.Exclusive,
          PinchGesture().onActionStart(() => { this.pinchStart = this.zoom; })
            .onActionUpdate(e => { this.zoomTo(this.pinchStart * e.scale); }),
          PanGesture().onActionStart(() => { this.panX = this.dx; this.panY = this.dy; })
            .onActionUpdate(e => { this.move(this.panX + e.offsetX, this.panY + e.offsetY); }),
          LongPressGesture().onAction(() => { this.compare = true; }).onActionEnd(() => { this.compare = false; })
            .onActionCancel(() => { this.compare = false; }),
          TapGesture({count: 2}).onAction(() => { this.zoomTo(this.zoom > 1 ? 1 : 2); })
        ))
      if ((this.message === '正在冲印' && !this.compare) || this.message === '正在保存') {
        Stack({alignContent: Alignment.Center}) {
          DevelopingFilm({label: this.message, onSaveHelp: () => { this.saveHelpOpen = true; }})
        }.width('100%').height('100%').hitTestBehavior(HitTestMode.Transparent)
      }
      Row({space: 6}) {
        Button(this.canAdjustFraming() ? '调整取景' : '裁切', {type: ButtonType.Normal})
          .id('photo-crop-action').height(36).width(this.canAdjustFraming() ? 82 : 58).borderRadius(CORNER_RADIUS)
          .padding({left: 8, right: 8})
          .fontSize(13).fontColor(this.hasGeometry() || this.framingFor(this.currentBorder()) ? '#FFDA9E' : '#F2ECE5')
          .backgroundColor('#AD252425').accessibilityText(this.canAdjustFraming() ? '调整边框取景' : '裁切与旋转')
          .enabled(!this.busy)
          .onClick(() => {
            this.stopPreview(true);
            this.borderRequest++;
            this.borderLoading = false;
            this.compare = false;
            if (this.canAdjustFraming()) this.framingOpen = true;
            else this.cropOpen = true;
          })
        Button({type: ButtonType.Normal}) {
          Image($r('app.media.compare_icon')).width(16).height(16)
        }.width(36).height(36).borderRadius(CORNER_RADIUS).backgroundColor(this.compare ? '#B86A512F' : '#AD252425')
          .accessibilityText('按住查看原图，松开查看成片').onTouch(e => {
            if (e.type === TouchType.Down) this.compare = true;
            if (e.type === TouchType.Up || e.type === TouchType.Cancel) this.compare = false;
          })
      }.margin(10)
    }.width('100%').layoutWeight(1).clip(true)
  }

  private hasMaterials(): boolean { return this.film.length > 0 && this.paper.length > 0; }

  private clearMaterials(): void {
    this.stopPreview(false);
    this.film = ''; this.paper = ''; this.lastColorPaper = DEFAULT_PAPER;
    this.values = [0, 1, 1, 1];
    const preview = this.preview, cropped = this.croppedPreview;
    this.preview = undefined; this.croppedPreview = undefined;
    preview?.release(); cropped?.release();
    const base = this.croppedOriginal ?? this.original;
    if (base && this.original && this.borderId) this.replaceFrame(base, this.original, '');
    this.goodFilm = ''; this.goodPaper = ''; this.goodValues = this.values.slice();
    this.borderSourceRevision++;
    this.retryFilm = ''; this.retryPaper = ''; this.retryValues = [];
    this.matched = true; this.dirty = this.hasGeometry() || !!this.borderId; this.message = ''; this.compare = false;
  }

  private selected(stock: Stock): boolean { return stock.id === (stock.paper ? this.paper : this.film); }

  private shortName(stock: Stock): string {
    if (stock.id === 'fujifilm_crystal_archive_typeii') return 'Crystal Archive II';
    if (stock.id === 'ilford_multigrade_iv_rc') return 'Multigrade IV RC';
    return stock.name.replace('Kodak Professional ', '').replace('Kodak Portra ', 'Portra ')
      .replace('Fujifilm ', '').replace(' (Push ', ' +').replace(')', '');
  }

  private pick(stock: Stock): void {
    if (this.busy || !this.input) return;
    if (!stock.id) { this.clearMaterials(); return; }
    if (this.selected(stock)) return;
    if (stock.paper) {
      this.paper = stock.id;
      if (!this.film) this.film = DEFAULT_FILM;
    } else {
      const paper = this.papers.find((s: Stock) => s.id === this.paper)!;
      if (!this.paper) this.paper = stock.monochrome ? stock.targetPrint : DEFAULT_PAPER;
      if (!stock.reversal && stock.monochrome !== paper.monochrome) {
        this.paper = stock.monochrome ? stock.targetPrint : this.lastColorPaper;
      }
      if (paper.id && !paper.monochrome) this.lastColorPaper = paper.id;
      this.film = stock.id;
    }
    this.process();
  }

  @Builder
  cover(stock: Stock, fit: ImageFit = ImageFit.Cover) {
    if (stock.id) {
      Image($rawfile('materials/' + stock.id + '.webp')).objectFit(fit)
        .width('100%').height('100%').draggable(false).accessibilityLevel('no')
    } else {
      Text('—').fontSize(24).fontColor('#85827F').textAlign(TextAlign.Center)
        .width('100%').height('100%').backgroundColor('#302F30').accessibilityLevel('no')
    }
  }

  @Builder
  materialRow(stock: Stock, linked: boolean) {
    Row({space: 12}) {
      Stack() { this.cover(stock) }.width(68).height(44).borderRadius(CORNER_RADIUS).clip(true)
      Column({space: 2}) {
        Text(this.shortName(stock)).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#F0EBE5')
        if (stock.id) {
        Text(stock.name.split(' ')[0] + ' · ' + (stock.paper ?
          (stock.id === 'kodak_2383' || stock.id === 'kodak_2393' ? '电影印片' : '相纸') : stock.group))
          .fontSize(12).fontColor('#B2AEA9')
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      if (linked) {
        Image($r('app.media.chevron')).width(16).height(16)
      } else if (this.selected(stock)) {
        Text('✓').fontSize(16).fontColor('#EDBD72')
      }
    }.padding({left: 8, right: 12, top: 6, bottom: 6}).width('100%')
      .backgroundColor('#292829').borderRadius(CORNER_RADIUS)
      .border({radius: CORNER_RADIUS, width: !linked && this.selected(stock) ? 1 : 0, color: '#DFB26B'})
      .accessibilityText(stock.name + (this.selected(stock) ? '，已选中' : ''))
      .onClick(() => { if (linked) this.changeTab(stock.paper ? 1 : 0); else this.pick(stock); })
  }

  @Builder
  card(stock: Stock) {
    Column() {
      Stack({alignContent: Alignment.TopEnd}) {
        this.cover(stock)
        if (this.selected(stock)) {
          Text('✓').fontSize(11).fontWeight(FontWeight.Bold).fontColor('#292016')
            .textAlign(TextAlign.Center).width(16).height(16).borderRadius(Math.min(CORNER_RADIUS, 8))
            .backgroundColor('#F1C077').margin(5)
        }
      }.width('100%').height(66).borderRadius(CORNER_RADIUS).clip(true)
      Text(this.shortName(stock)).width('100%').height(28).fontSize(12).minFontSize(10).maxFontSize(12)
        .maxLines(1).textOverflow({overflow: TextOverflow.Ellipsis}).textAlign(TextAlign.Center)
        .fontWeight(this.selected(stock) ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.selected(stock) ? '#F1C077' : '#DBD7D1')
    }.width(this.cardWidth).padding(1.5).clip(true).borderRadius(CORNER_RADIUS)
      .backgroundColor(this.selected(stock) ? '#2C2925' : '#252426')
      .border({radius: CORNER_RADIUS, width: 1.5, color: this.selected(stock) ? '#E6B162' : '#333132'})
      .accessibilityText(stock.name + (this.selected(stock) ? '，已选中' : ''))
      .onClick(() => this.pick(stock))
  }

  @Builder
  materials(full: boolean) {
    if (full && this.showMaterialOrderHint) {
      Text('长按拖动可调整顺序').fontSize(13).fontColor('#EFCD97').width('100%')
        .padding({left: 8, right: 8, bottom: 8})
    }
    List({space: 8, scroller: full ? undefined : this.materialStripScroller}) {
      ListItem() {
        if (full) {
          this.materialRow(this.tab === 1 ? this.papers[0] : this.films[0], false)
        } else {
          this.card(this.tab === 1 ? this.papers[0] : this.films[0])
        }
      }
      ForEach(this.orderedStocks(), (stock: Stock) => {
        ListItem() {
          if (full) { this.materialRow(stock, false) } else { this.card(stock) }
        }.id((full ? 'material-row-' : 'material-card-') + stock.id)
      }, (stock: Stock) => stock.id)
        .onMove((from: number, to: number) => this.moveStock(from, to))
    }.id(full ? 'material-library' : 'material-strip')
      .listDirection(full ? Axis.Vertical : Axis.Horizontal)
      .layoutWeight(full ? 1 : 0)
      .height(full ? '100%' : 102).width('100%').scrollBar(BarState.Off)
      .onAreaChange((_a, area) => { this.cardWidth = Math.max(84, (Number(area.width) - 16) / 3); })
  }

  @Builder
  compactMaterials() {
    Stack({alignContent: Alignment.TopStart}) {
      Column() {
        this.materials(false)
        if (this.filmProfile(this.film).reversal) {
          Text('反转片直扫').fontSize(15).fontColor('#E6E0D9')
            .width('100%').padding(12).margin({top: 8}).backgroundColor('#292829').borderRadius(CORNER_RADIUS)
        } else {
          Text(this.tab === 0 ? '相纸' : '胶片').width('100%').fontSize(12).fontColor('#C3BDB6')
            .margin({top: 8, bottom: 5})
          ForEach((this.tab === 0 ? this.papers : this.films).filter((s: Stock) => this.selected(s)), (stock: Stock) => {
            this.materialRow(stock, true)
          }, (s: Stock) => s.id)
        }
      }.width('100%').opacity(this.fanVisible ? 0 : 1)
        .hitTestBehavior(this.fanVisible ? HitTestMode.None : HitTestMode.Default)
        .accessibilityLevel(this.fanVisible ? 'no-hide-descendants' : 'auto')
      if (this.fanVisible) { this.materialFan() }
    }.width('100%').onAreaChange((_old: Area, area: Area) => { this.fanHeight = Number(area.height); })
    Column() { this.materialPager(48) }.width('100%').margin({top: 10})
  }

  @Builder
  adjustmentSlider(index: number) {
    Slider({value: this.values[index], min: index === 0 ? -this.limits[0] : 0,
      max: this.limits[index], step: 0.1, style: SliderStyle.InSet})
      .width('100%').height(44).trackThickness(24)
      .blockSize({width: 18, height: 18})
      .selectedColor('#DCAF70').trackColor('#393638').blockColor('#FFF2DC')
      .blockBorderColor('#E7CDA7').blockBorderWidth(1)
      .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
      .onGestureJudgeBegin((info: GestureInfo, event: BaseGestureEvent) => {
        if (info.isSystemGesture && info.type === GestureControl.GestureType.PAN_GESTURE) {
          const pan = event as PanGestureEvent;
          if (!horizontalAdjustment(pan.offsetX, pan.offsetY)) return GestureJudgeResult.REJECT;
        }
        return GestureJudgeResult.CONTINUE;
      })
      .accessibilityText(this.labels[index]).enabled(this.hasMaterials())
      .onChange((v, mode) => this.adjust(index, v, mode))
  }

  private adjust(index: number, value: number, mode: SliderChangeMode): void {
    if (!this.hasMaterials()) return;
    this.values[index] = value;
    this.matched = false;
    if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) this.process();
  }

  @Builder
  adjustments() {
    ForEach(this.filmProfile(this.film).reversal ? this.labels.slice(0, 3) : this.labels, (label: string, index: number) => {
      Row({space: 8}) {
        Text(label).width(28).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#E6E0D9')
        Column() { this.adjustmentSlider(index) }.layoutWeight(1)
        Text(this.values[index].toFixed(1) + (index === 0 ? ' EV' : ' ×'))
          .width(54).textAlign(TextAlign.End).fontSize(13).fontColor('#EFBD70')
        Button({type: ButtonType.Normal}) {
          Image($r('app.media.reset_icon')).width(15).height(15)
        }.height(32).width(32).backgroundColor('#302E2D').borderRadius(CORNER_RADIUS)
          .accessibilityText('复位' + label).onClick(() => {
            this.values[index] = index === 0 ? 0 : 1; this.process();
          })
      }.height(44).width('100%').margin({top: 4, bottom: 4}).enabled(this.hasMaterials())
    })
  }

  @Builder
  borderCard(border: FrameBorder, grid: boolean) {
    FrameBorderCard({
      preset: border, getSource: () => this.framingFor(border) ? this.preview ?? this.original : this.borderBase(),
      getFraming: () => this.framingFor(border), getFilm: () => this.borderFilm(this.goodFilm),
      sourceRevision: this.borderSourceRevision, selected: this.borderId === border.id,
      cardWidth: grid ? Math.max(60, (this.borderListWidth - 16) / 3) : this.borderStripWidth(),
      compact: !grid,
      onSelect: () => this.chooseBorder(border)
    })
  }

  private borderStripWidth(): number { return Math.max(64, (this.borderListWidth - 24) / 2.65); }

  private borderStripStart(): number {
    return Math.max(0, this.borderOrder.indexOf(this.borderId));
  }

  private moveBorder(from: number, to: number): void {
    const next = moveVisibleMaterial(this.borderOrder, this.borderOrder, from, to);
    if (next === this.borderOrder) return;
    this.borderOrder = next;
    this.saveMaterialPreference('borderOrder', next);
  }

  @Builder
  borderList(grid: boolean) {
    List({space: grid ? 8 : 12, initialIndex: grid ? 0 : this.borderStripStart(),
      scroller: grid ? undefined : this.borderStripScroller}) {
      ListItem() { this.borderCard(NO_FRAME, grid) }
      ForEach(this.borderOrder.map((id: string) => this.borders.find((border: FrameBorder) => border.id === id)!),
        (border: FrameBorder) => {
        ListItem() { this.borderCard(border, grid) }
      }, (border: FrameBorder) => border.id)
        .onMove((from: number, to: number) => this.moveBorder(from, to))
    }.id(grid ? 'border-grid' : 'border-strip')
      .listDirection(grid ? Axis.Vertical : Axis.Horizontal)
      .lanes(grid ? 3 : 1, grid ? 8 : 0)
      .width('100%').layoutWeight(grid ? 1 : 0)
      .height(grid ? '100%' : Math.min(Math.round(this.borderStripWidth()), this.compactHeight() - 150) + 43)
      .scrollBar(grid ? BarState.Auto : BarState.Off)
  }

  @Builder
  borderPicker(forceGrid: boolean) {
    Column({space: 8}) {
      if (forceGrid || this.panel === 2) {
        this.borderName()
        if (this.showBorderOrderHint) {
          Text('长按拖动可调整顺序').fontSize(13).fontColor('#EFCD97').width('100%')
            .padding({left: 8, right: 8, bottom: 4})
        }
        this.borderList(true)
      } else {
        Stack({alignContent: Alignment.TopStart}) {
          Column({space: 8}) {
            this.borderName()
            this.borderList(false)
          }.width('100%').opacity(this.fanVisible ? 0 : 1)
            .hitTestBehavior(this.fanVisible ? HitTestMode.None : HitTestMode.Default)
            .accessibilityLevel(this.fanVisible ? 'no-hide-descendants' : 'auto')
          if (this.fanVisible) { this.materialFan() }
        }.width('100%').onAreaChange((_old: Area, area: Area) => { this.fanHeight = Number(area.height); })
        this.materialPager(36)
      }
    }.width('100%').layoutWeight(1).alignItems(HorizontalAlign.Start)
      .onAreaChange((_old, area) => { this.borderListWidth = Number(area.width); })
  }

  @Builder
  borderName() {
    Text(this.currentBorder().name).id('border-current-name').fontSize(15).fontWeight(FontWeight.Bold)
      .fontColor('#F2ECE5').height(28).maxLines(1).textOverflow({overflow: TextOverflow.Ellipsis}).width('100%')
  }

  private pickerPages(): MaterialPage[] {
    if (this.tab === BORDER_TAB) {
      return [NO_FRAME].concat(this.borderOrder.map((id: string) =>
        this.borders.find((border: FrameBorder) => border.id === id)!)).map((border: FrameBorder): MaterialPage => {
        return {id: border.id, name: border.name, border: border};
      });
    }
    const stocks = this.orderedStocks();
    const pages = this.tab === 1 && stocks.length === 1 ? stocks :
      [this.tab === 1 ? this.papers[0] : this.films[0]].concat(stocks);
    return pages
      .map((stock: Stock): MaterialPage => {
        return {id: stock.id, name: this.shortName(stock), stock: stock};
      });
  }

  private pagerIndex(): number {
    const id = this.tab === BORDER_TAB ? this.borderId : this.tab === 1 ? this.paper : this.film;
    return Math.max(0, this.pickerPages().findIndex((option: MaterialPage) => option.id === id));
  }

  private pagerReady(): boolean {
    return !this.busy && this.panel === 1;
  }

  private previewPager(position: number): void {
    this.fanPosition = position;
    if (this.fanVisible) return;
    this.fanPages = this.pickerPages();
    this.getUIContext().animateTo({duration: 180, curve: Curve.EaseOut}, () => { this.fanVisible = true; });
  }

  private hideFan(): void {
    if (!this.fanVisible) return;
    this.getUIContext().animateTo({duration: 190, curve: Curve.EaseOut}, () => { this.fanVisible = false; });
  }

  private async commitPager(index: number): Promise<void> {
    const tab = this.tab;
    const option = (this.fanVisible ? this.fanPages : this.pickerPages())[index];
    if (this.fanVisible) this.fanPosition = index;
    this.hideFan();
    if (!option || !this.pagerReady()) return;
    if (option.border) {
      await this.chooseBorder(option.border);
      if (this.tab === tab && this.panel === 1 && this.borderId === option.id) {
        this.borderStripScroller.scrollToIndex(index, true, ScrollAlign.CENTER);
      }
    } else if (option.stock) {
      this.pick(option.stock);
      this.materialStripScroller.scrollToIndex(index, true, ScrollAlign.CENTER);
    }
    AppLog.record('material pager committed tab=' + tab + ' index=' + index + ' id=' + (option.id || 'none'));
  }

  @Builder
  materialPager(height: number) {
    MaterialPager({
      count: this.pickerPages().length, index: this.pagerIndex(),
      label: this.pickerPages()[this.fanVisible ? Math.round(this.fanPosition) : this.pagerIndex()]?.name ?? '',
      available: this.pagerReady(), rowHeight: height,
      onPreview: (position: number) => this.previewPager(position),
      onCommit: (index: number) => { this.commitPager(index); },
      onCancel: () => this.hideFan()
    })
  }

  private visibleFanPages(): MaterialPage[] {
    const first = Math.max(0, Math.floor(this.fanPosition) - 3);
    const last = Math.min(this.fanPages.length, Math.ceil(this.fanPosition) + 4);
    return this.fanPages.slice(first, last);
  }

  private fanPlacement(option: MaterialPage): FanPlacement {
    const index = this.fanPages.findIndex((page: MaterialPage) => page.id === option.id);
    return materialFanPlacement(index - this.fanPosition,
      Math.min(73, (this.windowWidth - 24) * 0.185, this.fanHeight * 0.34), index === Math.round(this.fanPosition));
  }

  @Builder
  fanCard(option: MaterialPage) {
    Stack({alignContent: Alignment.TopStart}) {
      Image($rawfile('material-pager/carrier.webp')).width('100%').height('100%').objectFit(ImageFit.Fill)
        .draggable(false)
      Stack() {
        if (option.border) {
          FrameBorderCard({
            preset: option.border, previewOnly: true, sourceRevision: this.borderSourceRevision,
            getSource: () => this.framingFor(option.border!) ? this.preview ?? this.original : this.borderBase(),
            getFraming: () => this.framingFor(option.border!), getFilm: () => this.borderFilm(this.goodFilm)
          })
        } else if (option.stock) {
          this.cover(option.stock, ImageFit.Contain)
        }
      }.width('87.4%').height('69.6%').position({x: '6.3%', y: '9.5%'}).backgroundColor('#141313')
        .borderRadius(2).clip(true)
      Text(option.name).width('84%').height('14%').position({x: '8%', y: '82%'})
        .fontColor(this.fanPlacement(option).order >= 1000 ? '#FFDC9D' : '#E0CEC0')
        .fontSize(11).maxLines(2).textOverflow({overflow: TextOverflow.Ellipsis}).textAlign(TextAlign.Center)
    }.id('material-fan-card-' + (option.id || 'none'))
      .width(Math.min(154, (this.windowWidth - 24) * 0.39, this.fanHeight * 0.66)).aspectRatio(0.79)
      .opacity(this.fanPlacement(option).opacity).blur(this.fanPlacement(option).blur)
      .zIndex(this.fanPlacement(option).order)
      .scale({x: this.fanPlacement(option).scale, y: this.fanPlacement(option).scale})
      .rotate({angle: this.fanPlacement(option).angle})
      .translate({x: this.fanPlacement(option).x, y: this.fanPlacement(option).y - 6})
      .animation({duration: 105, curve: Curve.EaseOut})
  }

  @Builder
  materialFan() {
    Stack({alignContent: Alignment.Center}) {
      ForEach(this.visibleFanPages(), (option: MaterialPage) => { this.fanCard(option) },
        (option: MaterialPage) => option.id)
      Text((Math.round(this.fanPosition) + 1) + ' / ' + this.fanPages.length)
        .width('100%').height(15).align(Alignment.Center).textAlign(TextAlign.Center)
        .fontColor('#CAB8A8').fontSize(10).position({x: 0, y: Math.max(0, this.fanHeight - 15)}).zIndex(2000)
    }.width('100%').height(this.fanHeight).position({x: 0, y: 0}).id('material-fan')
      .clip(true).hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
      .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({y: 12})))
  }

  @Builder
  materialTabs() {
    Row() {
      ForEach(['胶片', '相纸', '边框', '调整'], (label: string, i: number) => {
        Button(label, {type: ButtonType.Normal}).id('editor-tab-' + i)
          .borderRadius(CORNER_RADIUS).layoutWeight(1).height(38).margin({left: 3, right: 3})
          .fontSize(15).fontWeight(this.tab === i ? FontWeight.Bold : FontWeight.Regular)
          .fontColor(this.tab === i ? '#FFDA9E' : '#ECE7E0')
          .backgroundColor(this.tab === i ? '#54432E' : '#302E2F').systemMaterial(this.tabMaterial)
          .enabled(i !== 1 || !this.filmProfile(this.film).reversal)
          .opacity(i === 1 && this.filmProfile(this.film).reversal ? 0.4 : 1)
          .accessibilityText(label + (this.tab === i ? '，已选中' : '')).onClick(() => this.changeTab(i))
      })
    }.margin({top: 8, bottom: 12})
  }

  @Builder
  bottomPanel() {
    Column() {
      Button({type: ButtonType.Normal}) { Rect().width(36).height(4).radius(2).fill('#AEAAA3') }
        .id('material-dock-handle')
        .accessibilityText(this.panel === 0 ? '展开材料' : this.panel === 1 ? '展开材料库' : '收起材料库')
        .width('100%').height(HANDLE_HEIGHT).borderRadius(CORNER_RADIUS).backgroundColor('#201F20')
        .gesture(GestureGroup(GestureMode.Exclusive,
          PanGesture({direction: PanDirection.Vertical}).onActionStart(() => {
            this.dragStart = this.panelPosition;
          }).onActionUpdate(e => {
            const compact = this.compactHeight();
            const start = this.dragStart <= 1 ? COLLAPSED_HEIGHT + this.dragStart * (compact - COLLAPSED_HEIGHT) :
              compact + (this.dragStart - 1) * (this.windowHeight * 0.63 - compact);
            const height = start - e.offsetY;
            const pos = height <= compact ? (height - COLLAPSED_HEIGHT) / (compact - COLLAPSED_HEIGHT) :
              1 + (height - compact) / (this.windowHeight * 0.63 - compact);
            this.panelPosition = Math.max(-0.025, Math.min(2.08, pos));
          }).onActionEnd(e => {
            let target = Math.round(this.panelPosition);
            if (target === this.panel && (Math.abs(e.offsetY) > 40 || Math.abs(e.velocityY) > 520)) {
              const direction = Math.abs(e.velocityY) > 520 ? e.velocityY : e.offsetY;
              target += direction < 0 ? 1 : -1;
            }
            this.snapPanel(Math.max(0, Math.min(2, target)));
          }).onActionCancel(() => this.snapPanel(this.panel)),
          TapGesture().onAction(() => this.snapPanel(this.tab === BORDER_TAB && this.panel === 2 ? 1 : (this.panel + 1) % 3))
        ))
      if (this.panelPosition > 0.02 || this.panel !== 0) {
        this.materialTabs()
        if (this.tab === BORDER_TAB) {
          this.borderPicker(false)
        } else if (this.tab === ADJUST_TAB) {
          Scroll() { Column() { this.adjustments() }.width('100%') }
            .layoutWeight(1).width('100%').align(Alignment.Top)
        } else {
          Stack({alignContent: Alignment.TopStart}) {
            Column() { this.compactMaterials() }
              .width('100%').height('100%').opacity(1 - this.libraryProgress())
              .hitTestBehavior(this.libraryProgress() < 0.5 ? HitTestMode.Default : HitTestMode.BLOCK_DESCENDANTS)
              .accessibilityLevel(this.libraryProgress() < 0.5 ? 'auto' : 'no-hide-descendants')
            Column() { this.materials(true) }
              .width('100%').height('100%').opacity(this.libraryProgress())
              .hitTestBehavior(this.libraryProgress() >= 0.5 ? HitTestMode.Default : HitTestMode.BLOCK_DESCENDANTS)
              .accessibilityLevel(this.libraryProgress() >= 0.5 ? 'auto' : 'no-hide-descendants')
          }.width('100%').layoutWeight(1).clip(true)
        }
      }
    }.enabled(!this.busy).width('100%').height(this.panelHeight() + this.getUIContext().px2vp(this.bottomInset))
      .scale({x: 1 - Math.min(0.018, Math.abs(this.panelPosition - Math.round(this.panelPosition)) * 0.04), y: 1,
        centerY: '100%'}).clip(true).padding({left: 12, right: 12, bottom: this.getUIContext().px2vp(this.bottomInset) + 8})
      .backgroundColor('#201F20').borderRadius({topLeft: CORNER_RADIUS, topRight: CORNER_RADIUS})
  }

  @Builder
  sidePanel() {
    Column() {
      this.materialTabs()
      if (this.tab === BORDER_TAB) {
        this.borderPicker(true)
      } else if (this.tab === ADJUST_TAB) {
        Scroll() { Column() { this.adjustments() }.width('100%') }
          .layoutWeight(1).width('100%').align(Alignment.Top)
      } else {
        this.materials(true)
      }
    }.width(Math.min(400, Math.max(268, this.windowWidth * 0.38))).height('100%')
      .padding({left: 12, right: 12, bottom: 8}).backgroundColor('#201F20').borderRadius(CORNER_RADIUS).clip(true).enabled(!this.busy)
  }

  @Builder
  importMenu() {
    Menu() {
      MenuItem({content: '从相册选择'}).contentFontColor('#F2ECE5')
        .enabled((!this.busy || this.importing) && !!this.assets)
        .onClick(() => { this.choosePhoto(); })
      MenuItem({content: '从文件选择'}).contentFontColor('#F2ECE5')
        .enabled((!this.busy || this.importing) && !!this.assets)
        .onClick(() => { this.chooseFile(); })
      MenuItem({content: '设置'}).contentFontColor('#F2ECE5').enabled(!this.busy || this.importing)
        .onClick(() => {
          this.stopImport();
          this.stopPreview(true);
          this.getUIContext().getRouter().pushUrl({url: 'pages/Settings'});
        })
    }.backgroundColor('#292829').radius(CORNER_RADIUS)
      .border({width: 0.5, color: '#50473F', radius: CORNER_RADIUS})
  }

  build() {
    Stack() {
    Column() {
      if (this.choosingPhoto) {
        FormatPhotoPicker({onCancel: () => this.cancelPhoto(), onConfirm: (uri: string) => this.confirmPhoto(uri)})
      } else if (this.framingOpen && this.original) {
        CropEditor({
          photo: this.preview ?? this.original,
          sourceWidth: this.rawRotation ? this.heightPx : this.widthPx,
          sourceHeight: this.rawRotation ? this.widthPx : this.heightPx,
          geometry: this.framingFor(this.currentBorder()) ?? this.defaultFraming(),
          borderFraming: true,
          resetGeometry: () => this.defaultFraming(),
          onOpenCrop: () => { this.framingOpen = false; this.cropOpen = true; },
          onCancel: () => { this.framingOpen = false; },
          onApply: (geometry: PhotoGeometry) => this.applyBorderFraming(geometry)
        })
      } else if (this.cropOpen && this.original) {
        CropEditor({
          photo: this.preview ?? this.original,
          sourceWidth: this.rawRotation ? this.heightPx : this.widthPx,
          sourceHeight: this.rawRotation ? this.widthPx : this.heightPx,
          geometry: this.geometry,
          onCancel: () => { this.cropOpen = false; },
          onApply: (geometry: PhotoGeometry) => this.applyGeometry(geometry)
        })
      } else {
      Row() {
        Button({type: ButtonType.Normal}) {
          Row({space: 5}) {
            Image($r('app.media.folder_icon')).width(15).height(15)
            Text('导入').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#F2ECE5')
            Image($r('app.media.chevron')).width(11).height(11).rotate({angle: 90})
          }
        }.width(78).height(34).borderRadius(CORNER_RADIUS).backgroundColor('#2A2929')
          .bindMenu(this.importMenu, {borderRadius: CORNER_RADIUS,
            backgroundColor: '#292829', backgroundBlurStyle: BlurStyle.NONE})
        Text() {
          Span('Spektra').fontColor('#F1EDE7')
          Span('Lab').fontColor('#EAB668')
        }.fontSize(18).fontWeight(FontWeight.Bold).textAlign(TextAlign.Center).layoutWeight(1)
        if (this.original) {
          SaveButton({icon: SaveIconStyle.LINES, text: SaveDescription.SAVE, buttonType: ButtonType.Normal})
            .width(78).height(34).borderRadius(CORNER_RADIUS).backgroundColor('#EFBD70')
            .iconSize(16).iconColor('#32271D').fontSize(14).fontColor('#32271D').textIconSpace(6)
            .enabled(this.canSave() || this.waitingForSaveGrant)
            .onClick((_event: ClickEvent, result: SaveButtonOnClickResult) => {
              if (result === SaveButtonOnClickResult.SUCCESS) {
                if (this.waitingForSaveGrant) this.resumeSaveAuthorization();
                else this.save();
              }
              else if (result === SaveButtonOnClickResult.TEMPORARY_AUTHORIZATION_FAILED) this.message = '保存授权失败，请重试';
            })
        } else { Blank().width(78) }
      }.height(54).width('100%').padding({left: 14, right: 14})
      if (this.rawSaveHint()) {
        Text(this.rawSaveHint()).id('raw-save-hint').fontSize(13).fontColor('#D9C4A8')
          .width('100%').textAlign(TextAlign.End).padding({left: 14, right: 14, bottom: 8})
      }
      Flex({direction: this.wide() ? FlexDirection.Row : FlexDirection.Column}) {
        Column() {
          if (this.importing) {
            Stack({alignContent: Alignment.Center}) {
              DevelopingFilm({prominent: true, label: '正在导入'})
            }.width('100%').layoutWeight(1).backgroundColor('#000000')
          } else if (this.original) { this.photo() }
          else {
            HomeGallery({ready: !this.busy && !this.rendering && this.assets.length > 0,
              currentIndex: $homeCardIndex, onSelect: (recipe: HomeRecipe) => this.choosePhoto(recipe)})
              .layoutWeight(1)
          }
          if (!this.importing && this.message && this.message !== '正在冲印' && this.message !== '正在保存') {
            Row() {
              Text(this.message).fontSize(14).fontColor('#ECEAE5').padding(8)
              if (this.message === '材料库加载失败') {
                this.action('重试', () => this.prepare())
              } else if (this.message === '冲印失败，请重试或更换材料') {
                this.action('重试', () => {
                  this.film = this.retryFilm; this.paper = this.retryPaper; this.values = this.retryValues.slice();
                  this.process();
                })
              }
            }
          }
        }.layoutWeight(1).width('100%').height('100%')
        if (this.original) {
          if (this.wide()) { this.sidePanel() } else { this.bottomPanel() }
        }
      }.width('100%').layoutWeight(1)
      }
    }.width('100%').height('100%').onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) this.cancelReviewPrompt();
    }).onAreaChange((_a, b) => {
        this.windowHeight = Number(b.height);
        this.windowWidth = Number(b.width) - this.getUIContext().px2vp(this.leftInset + this.rightInset);
        this.updateMaterialOrderHint();
      }).backgroundColor('#171819')
      .padding({top: this.topInset + 'px', left: this.leftInset + 'px', right: this.rightInset + 'px',
        bottom: !this.choosingPhoto && !this.cropOpen && !this.framingOpen && this.original && !this.wide() ? 0 : this.bottomInset + 'px'})
      AppUpdates({ready: !this.busy && !this.rendering && !this.original && !this.choosingPhoto && !!this.assets})
      if (this.saveHelpOpen) {
        Column() {
          Text(this.hasMaterials() ? '保存时，SpektraLab 会按照片的原始分辨率重新冲印，将胶片色彩、颗粒、光晕等效果计算到完整画面中，再生成照片并写入相册。原图的像素越多，处理时间通常越长。' :
            'SpektraLab 正在从原始照片按当前编辑效果生成图片，并写入相册。')
            .fontSize(14).lineHeight(22).fontColor('#F2ECE5').padding(20)
            .width('85%').constraintSize({maxWidth: 340})
            .backgroundColor('#353436').borderRadius(CORNER_RADIUS)
            .id('save-help-message')
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
          .backgroundColor('#66000000').id('save-help-overlay')
          .onClick(() => { this.saveHelpOpen = false; })
      }
    }.width('100%').height('100%')
  }
}
