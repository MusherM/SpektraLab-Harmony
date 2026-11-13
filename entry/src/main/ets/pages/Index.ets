import { FormatPhotoPicker } from './FormatPhotoPicker';
import { HomeGallery, HomeRecipe } from './HomeGallery';
import { exportTitle } from '../common/MaterialNames';
import { horizontalAdjustment } from '../common/InteractionRules';
import { AppLog } from '../common/AppLog';
import { exportMime, exportExtension } from '../common/ExportFormat';
import { straightPhotoPixels } from '../common/PhotoPixels';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { colorSpaceManager } from '@kit.ArkGraphics2D';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { taskpool, util } from '@kit.ArkTS';
import { framePrint } from './FilmFrame';
import nativeEngine, { RawFrame } from 'libspektralab.so';

import { curves, uiMaterial } from '@kit.ArkUI';

let resourceCleanup: Promise<void> = Promise.resolve();

const DEFAULT_FILM: string = 'kodak_portra_400';
const DEFAULT_PAPER: string = 'kodak_portra_endura';

const CORNER_RADIUS: number = 10;
const HANDLE_HEIGHT: number = 44;
const COLLAPSED_HEIGHT: number = HANDLE_HEIGHT + 12;

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
  params: string, linear: boolean): image.PixelMap {
  const rgba = linear ? nativeEngine.renderLinear(path, input, width, height, params) :
    nativeEngine.render(path, input, width, height, params);
  return image.createPixelMapSync(rgba, { size: { width, height },
    srcPixelFormat: image.PixelMapFormat.RGBA_8888, pixelFormat: image.PixelMapFormat.RGBA_8888 });
}

@Concurrent
function frameExport(photo: image.PixelMap, name: string): image.PixelMap {
  return framePrint(photo, name);
}

@Concurrent
function clearNativeResources(releaseEngine: boolean): void { nativeEngine.clearResources(releaseEngine); }

@Concurrent
function decodeRaw(fd: number, cacheDir: string): RawFrame { return nativeEngine.decodeRaw(fd, cacheDir); }

@Concurrent
function renderRawPrint(path: string, fd: number, params: string, cacheDir: string): image.PixelMap {
  const frame = nativeEngine.renderRaw(path, fd, params, cacheDir);
  return image.createPixelMapSync(frame.pixels, { size: { width: frame.width, height: frame.height },
    srcPixelFormat: image.PixelMapFormat.RGBA_8888, pixelFormat: image.PixelMapFormat.RGBA_8888 });
}

@CustomDialog
struct LeaveEditorDialog {
  controller: CustomDialogController;
  discard: () => void = () => {};

  build() {
    Column({space: 12}) {
      Text('放弃本次调整？').fontSize(20).fontWeight(FontWeight.Medium).fontColor('#F2ECE5')
      Text('未保存的调整将丢失，原照片会保留。').fontSize(14).fontColor('#C8BEB2')
      Row({space: 10}) {
        Button('放弃调整', {type: ButtonType.Normal})
          .layoutWeight(1).height(44).borderRadius(CORNER_RADIUS).backgroundColor('#343233').fontColor('#ECE5DC')
          .onClick(() => { this.controller.close(); this.discard(); })
        Button('继续编辑', {type: ButtonType.Normal})
          .layoutWeight(1).height(44).borderRadius(CORNER_RADIUS).backgroundColor('#EFBD70').fontColor('#32271D')
          .defaultFocus(true).onClick(() => this.controller.close())
      }.width('100%').margin({top: 10})
    }.width('88%').constraintSize({maxWidth: 360}).alignItems(HorizontalAlign.Start)
      .padding(22).borderRadius(16).backgroundColor('#242426').border({width: 0.5, color: '#50473F'})
  }
}

@Entry
@Component
struct Index {
  @StorageProp('exportFormat') private exportFormat: string = 'JPEG';
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
  private widthPx: number = 0;
  private heightPx: number = 0;

  private editorActive: boolean = false;

  aboutToAppear(): void { this.editorActive = true; this.prepare(); }

  aboutToDisappear(): void { this.editorActive = false; this.releaseNativeResources(); }

  private releaseNativeResources(): void {
    if (this.busy || this.rendering) return;
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
      this.films = stocks.filter((s: Stock) => !s.paper).sort((a: Stock, b: Stock) => a.group.localeCompare(b.group));
      this.papers = stocks.filter((s: Stock) => s.paper);
      this.films.unshift({id: '', name: '未选中', paper: false, group: '', reversal: false,
        monochrome: false, targetPrint: DEFAULT_PAPER});
      this.papers.unshift({id: '', name: '未选中', paper: true, group: '', reversal: false,
        monochrome: false, targetPrint: DEFAULT_PAPER});
      const dir = ctx.filesDir + '/assets-v1';
      if (!fs.accessSync(dir + '/ready')) {
        const list = decoder.decodeWithStream(await rm.getRawFileContent('engine-files.txt')).trim().split('\n');
        for (const name of list) {
          const target = dir + '/' + name;
          const parent = target.substring(0, target.lastIndexOf('/'));
          if (!fs.accessSync(parent)) fs.mkdirSync(parent, true);
          const bytes = await rm.getRawFileContent(name);
          const file = fs.openSync(target, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
          try {
            if (fs.writeSync(file.fd, bytes.slice().buffer) !== bytes.byteLength) throw new Error('资源写入不完整');
          } finally { fs.closeSync(file); }
        }
        fs.closeSync(fs.openSync(dir + '/ready', fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY));
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
    this.panel = target;
    this.getUIContext().animateTo({curve: curves.interpolatingSpring(0, 1, 245, 23)}, () => {
      this.panelPosition = target;
    });
  }
  @State private rendering: boolean = false;
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

  private params(film: string, paper: string, linear: boolean, fullSize: boolean = false): string {
    return JSON.stringify({ product_defaults: true, film_stock: film, print_stock: paper, scan_film: this.filmProfile(film).reversal,
      exposure_compensation_ev: this.values[0], grain_active: true, grain_amount: this.values[1],
      halation_active: true, halation_amount: this.values[2], glare_active: true, glare_amount: this.values[3],
      auto_exposure: true, auto_exposure_method: 'balanced',
      input_color_space: linear ? 'ProPhoto RGB' : 'sRGB', input_cctf_decoding: !linear,
      output_color_space: 'sRGB', output_cctf_encoding: true,
      striped: fullSize, strip_rows: fullSize ? 256 : 0 });
  }

  private async pixels(input: ArrayBuffer, w: number, h: number, linear: boolean,
    film: string, paper: string): Promise<image.PixelMap> {
    const pixels = input.slice(0);
    const task = new taskpool.Task(renderPixels, this.assets, pixels, w, h,
      this.params(film, paper, linear), linear);
    task.setTransferList([pixels]);
    return await taskpool.execute(task) as image.PixelMap;
  }

  private makeMap(buf: ArrayBuffer, w: number, h: number): Promise<image.PixelMap> {
    return image.createPixelMap(buf, { size: { width: w, height: h },
      srcPixelFormat: image.PixelMapFormat.RGBA_8888, pixelFormat: image.PixelMapFormat.RGBA_8888 });
  }

  private async readPhoto(fd: number, preview: boolean): Promise<RawFrame> {
    const source = image.createImageSource(fd);
    try {
      const info = await source.getImageInfo();
      const scale = preview ? Math.min(1, 2048 / Math.max(info.size.width, info.size.height)) : 1;
      const size: image.Size = { width: Math.max(1, Math.round(info.size.width * scale)),
        height: Math.max(1, Math.round(info.size.height * scale)) };
      const map = await source.createPixelMap({ desiredSize: size, editable: true,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        desiredDynamicRange: image.DecodingDynamicRange.SDR });
      try {
        // Convert pixels before discarding the source's ICC/color-space metadata.
        await map.applyColorSpace(colorSpaceManager.create(colorSpaceManager.ColorSpace.SRGB));
        let orientation = '1';
        try { orientation = await source.getImageProperty(image.PropertyKey.ORIENTATION); } catch (_) {}
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

  @State private frameEnabled: boolean = false;
  @State private framed: image.PixelMap | undefined = undefined;

  private printMap(): image.PixelMap | undefined {
    return this.framed ?? this.preview ?? this.original;
  }

  private replaceFrame(photo: image.PixelMap, film: string, enabled: boolean): void {
    const next = enabled ? framePrint(photo, this.filmProfile(film).name) : undefined;
    const old = this.framed;
    this.framed = next;
    old?.release();
  }

  private toggleFrame(enabled: boolean): void {
    if (!this.preview) return;
    try {
      this.replaceFrame(this.preview, this.goodFilm, enabled);
      this.frameEnabled = enabled;
      this.dirty = true;
    } catch (err) { AppLog.failure('frame', err as BusinessError); this.message = '相框生成失败，请重试'; }
  }

  @State private choosingPhoto: boolean = false;

  private choosePhoto(recipe?: HomeRecipe): void {
    if (this.busy || this.rendering || !this.assets) return;
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
    await this.open(uri, recipe);
  }

  private async chooseFile(): Promise<void> {
    if (this.busy || this.rendering || !this.assets) return;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      const uris = await new picker.DocumentViewPicker(context).select(options);
      if (uris.length > 0) await this.open(uris[0]);
    } catch (err) {
      AppLog.failure('file picker', err as BusinessError);
      this.message = '无法打开文件选择器，请重试';
    }
  }

  private async open(uri: string, recipe?: HomeRecipe): Promise<void> {
    if (this.busy || this.rendering || !this.assets) return;
    this.busy = true;
    this.importing = true;
    this.message = '';
    let imported = false;
    try {
      if (recipe && (!this.films.some((stock: Stock) => stock.id === recipe.film) ||
        !this.papers.some((stock: Stock) => stock.id === recipe.paper))) {
        throw new Error('卡片材料不存在');
      }
      this.message = '正在导入';
      const name = new fileUri.FileUri(uri).name;
      const knownPhoto = /\.(jpe?g|png|heic|heif|webp|gif|bmp|avif)$/i.test(name);
      const knownRaw = /\.(dng|cr[23w]|nef|nrw|arw|srf|sr2|raf|rw2|orf|pef|ptx|3fr|fff|iiq|rwl|srw|x3f|mrw|mos|kdc|dcr|erf|mef|raw)$/i.test(name);
      let raw = false;
      await resourceCleanup;
      await taskpool.execute(new taskpool.Task(clearNativeResources, false));
      AppLog.record('import start');
      const cacheDir = (this.getUIContext().getHostContext() as common.UIAbilityContext).cacheDir;
      const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      let frame: RawFrame;
      try {
        if (knownPhoto) {
          frame = await this.readPhoto(file.fd, true);
        } else {
          try {
            frame = await taskpool.execute(new taskpool.Task(decodeRaw, file.fd, cacheDir)) as RawFrame;
            raw = true;
            AppLog.record('RAW decoded bytes=' + fs.statSync(file.fd).size + ' ' + (frame.rawInfo ?? ''));
          } catch (err) {
            if (knownRaw) throw new Error((err as BusinessError).message ?? String(err));
            frame = await this.readPhoto(file.fd, true);
          }
        }
      } finally { fs.closeSync(file); }
      const w = frame.width, h = frame.height;
      if (raw && !frame.displayPixels) throw new Error('RAW 预览数据缺失');
      const buf = frame.displayPixels ?? frame.pixels;
      const original = await this.makeMap(buf, w, h);
      const oldOriginal = this.original;
      this.clearMaterials();
      this.sourceUri = uri;
      this.sourceName = name;
      this.input = frame.pixels; this.linear = raw; this.widthPx = w; this.heightPx = h;
      this.original = original;
      AppLog.record((raw ? 'import RAW complete ' : 'import photo complete ') + w + 'x' + h);
      this.compare = false; this.resetZoom(); this.dirty = false; this.matched = true;
      this.message = frame.warning ?? '';
      oldOriginal?.release();
      imported = true;
    } catch (err) {
      this.message = '无法处理这张照片，请选择其他照片';
      AppLog.failure('import', err as BusinessError); console.error('SpektraLab import: ' + String(err));
    } finally {
      this.importing = false; this.busy = false;
      if (!this.editorActive) this.releaseNativeResources();
    }
    if (imported && recipe && this.editorActive) {
      this.film = recipe.film;
      this.paper = recipe.paper;
      if (!this.filmProfile(recipe.film).monochrome) this.lastColorPaper = recipe.paper;
      AppLog.record('home recipe ' + recipe.id + ' ' + recipe.film + ' ' + recipe.paper);
      await this.process();
    }
  }

  private async process(): Promise<void> {
    this.version++;
    if (!this.input || !this.hasMaterials()) return;
    this.matched = false;
    if (this.rendering) return;
    this.rendering = true;
    this.message = '正在冲印';
    while (this.input && this.hasMaterials()) {
      const version = this.version;
      const sentValues = this.values.slice();
      AppLog.record('render ' + this.film + ' ' + this.paper);
      try {
        const next = await this.pixels(this.input, this.widthPx, this.heightPx, this.linear, this.film, this.paper);
        if (version !== this.version) { await next.release(); continue; }
        try { this.replaceFrame(next, this.film, this.frameEnabled); }
        catch (err) { await next.release(); throw new Error(String(err)); }
        const old = this.preview; this.preview = next; old?.release();
        this.goodFilm = this.film; this.goodPaper = this.paper; this.goodValues = sentValues;
        AppLog.record('render complete');
        this.dirty = true; this.matched = sentValues.every((v: number, i: number) => v === this.values[i]); this.message = '';
      } catch (err) {
        if (version !== this.version) continue;
        this.retryFilm = this.film; this.retryPaper = this.paper; this.retryValues = this.values.slice();
        this.film = this.goodFilm; this.paper = this.goodPaper; this.values = this.goodValues.slice();
        this.matched = true; this.message = '冲印失败，请重试或更换材料';
        AppLog.failure('render', err as BusinessError); console.error('SpektraLab render: ' + String(err));
      }
      break;
    }
    this.rendering = false;
    if (!this.input || !this.editorActive) this.releaseNativeResources();
  }

  @State private cardWidth: number = 108;
  private lastColorPaper: string = DEFAULT_PAPER;
  private readonly favorites: string[] = ['kodak_gold_200', 'kodak_portra_400', 'cinestill_800t'];
  private stocks(full: boolean): Stock[] {
    const film = this.filmProfile(this.film);
    const all = this.tab === 1 ? this.papers.filter((s: Stock) => !s.id || s.monochrome === film.monochrome) : this.films;
    if (full) return all;
    const ids: string[] = [''].concat(this.tab === 1 ? (film.monochrome ? [] : [DEFAULT_PAPER]) : this.favorites);
    return ids.map((id: string) => all.find((s: Stock) => s.id === id)!)
      .concat(all.filter((s: Stock) => !ids.includes(s.id)));
  }
  private resetZoom(): void { this.zoom = 1; this.dx = 0; this.dy = 0; }
  private zoomTo(value: number): void {
    this.zoom = Math.max(1, Math.min(5, value));
    this.move(this.dx, this.dy);
  }
  private displayedWidth(): number {
    return (!this.compare && this.framed) ? this.framed.getImageInfoSync().size.width : this.widthPx;
  }
  private displayedHeight(): number {
    return (!this.compare && this.framed) ? this.framed.getImageInfoSync().size.height : this.heightPx;
  }
  private fittedScale(): number {
    return this.widthPx && this.heightPx ? Math.min(this.extentX / this.displayedWidth(), this.extentY / this.displayedHeight()) : 0;
  }
  private move(x: number, y: number): void {
    const scale = this.fittedScale();
    const maxX = Math.max(0, (this.displayedWidth() * scale * this.zoom - this.extentX) / 2);
    const maxY = Math.max(0, (this.displayedHeight() * scale * this.zoom - this.extentY) / 2);
    this.dx = Math.max(-maxX, Math.min(maxX, x)); this.dy = Math.max(-maxY, Math.min(maxY, y));
  }
  private changeTab(index: number): void {
    this.tab = index;
  }
  private leaveDialog: CustomDialogController = new CustomDialogController({
    builder: LeaveEditorDialog({discard: () => this.closePhoto()}),
    customStyle: true, alignment: DialogAlignment.Center, autoCancel: true
  });

  private closePhoto(): void {
    this.releaseNativeResources();
    // Invalidate any render still running before releasing its preview.
    this.version++;
    this.input = undefined;
    const preview = this.preview, original = this.original, framed = this.framed;
    this.preview = undefined; this.original = undefined; this.framed = undefined;
    this.sourceUri = ''; this.sourceName = ''; this.widthPx = 0; this.heightPx = 0; this.linear = false;
    this.film = ''; this.paper = ''; this.lastColorPaper = DEFAULT_PAPER;
    this.values = [0, 1, 1, 1]; this.frameEnabled = false;
    this.dirty = false; this.matched = false; this.message = '';
    this.tab = 0; this.panel = 1; this.panelPosition = 1; this.compare = false; this.resetZoom();
    preview?.release(); original?.release(); framed?.release();
  }

  onBackPress(): boolean {
    if (this.choosingPhoto) { this.cancelPhoto(); return true; }
    if (this.busy) return true;
    if (!this.original) return false;
    if (!this.wide() && this.panel === 2) { this.snapPanel(1); return true; }
    if (this.dirty || this.rendering || !this.matched) this.leaveDialog.open();
    else this.closePhoto();
    return true;
  }
  private async renderOriginal(params: string): Promise<image.PixelMap> {
    const cacheDir = (this.getUIContext().getHostContext() as common.UIAbilityContext).cacheDir;
    const source = fs.openSync(this.sourceUri, fs.OpenMode.READ_ONLY);
    try {
      if (this.linear) {
        return await taskpool.execute(new taskpool.Task(renderRawPrint, this.assets, source.fd, params, cacheDir), taskpool.Priority.HIGH) as image.PixelMap;
      }
      const frame = await this.readPhoto(source.fd, false);
      return await taskpool.execute(new taskpool.Task(renderPixels, this.assets, frame.pixels,
        frame.width, frame.height, params, false), taskpool.Priority.HIGH) as image.PixelMap;
    } finally { fs.closeSync(source); }
  }

  private async save(): Promise<void> {
    if (!this.sourceUri || !this.hasMaterials() || !this.matched || this.busy || this.rendering) return;
    this.busy = true;
    this.message = '正在保存';
    const started = Date.now();
    AppLog.record('export start');
    let print: image.PixelMap | undefined;
    let framed: image.PixelMap | undefined;
    let destination: fs.File | undefined;
    try {
      const encoder = image.createImagePacker();
      let mime: string;
      try { mime = exportMime(this.exportFormat, encoder.supportedFormats); }
      finally { await encoder.release(); }
      const extension = exportExtension(mime);
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      // Acquire the destination while the SaveButton grant is active.
      const title = exportTitle(this.sourceName, this.film, this.paper);
      const uri = await photoAccessHelper.getPhotoAccessHelper(ctx).createAsset(
        photoAccessHelper.PhotoType.IMAGE, extension, {title: title});
      const savedName = new fileUri.FileUri(uri).name;
      destination = fs.openSync(uri, fs.OpenMode.WRITE_ONLY);
      AppLog.record('export destination ms=' + (Date.now() - started));
      const name = this.filmProfile(this.film).name;
      const withFrame = this.frameEnabled;
      // A downsampled preview always has a 2048-pixel long edge.
      let output = Math.max(this.widthPx, this.heightPx) < 2048 ? this.printMap() : undefined;
      if (!output) {
        const renderStarted = Date.now();
        print = await this.renderOriginal(this.params(this.film, this.paper, this.linear, true));
        AppLog.record('export render ms=' + (Date.now() - renderStarted));
        if (withFrame) {
          framed = await taskpool.execute(new taskpool.Task(frameExport, print, name), taskpool.Priority.HIGH) as image.PixelMap;
        }
        output = framed ?? print;
      }
      const temp = ctx.cacheDir + '/print-' + util.generateRandomUUID() + '.' + extension;
      const file = fs.openSync(temp, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      try {
        const encodeStarted = Date.now();
        const packer = image.createImagePacker();
        try { await packer.packToFile(output, file.fd, {format: mime, quality: 95}); }
        finally { await packer.release(); }
        AppLog.record('export encode ms=' + (Date.now() - encodeStarted));
        const bytes = fs.statSync(file.fd).size;
        if (!bytes) throw new Error('图片编码结果为空');
        const encoded = image.createImageSource(temp);
        try {
          const info = await encoded.getImageInfo();
          const expected = output.getImageInfoSync().size;
          const sameFormat = info.mimeType === mime ||
            (['image/heic', 'image/heif'].includes(mime) && ['image/heic', 'image/heif'].includes(info.mimeType));
          if (!sameFormat || info.size.width !== expected.width || info.size.height !== expected.height) {
            throw new Error('编码后的图片格式或尺寸不一致');
          }
          AppLog.record('export verified ' + info.mimeType + ' ' + info.size.width + 'x' + info.size.height);
        } finally { await encoded.release(); }
        const header = new ArrayBuffer(Math.min(bytes, 24));
        fs.readSync(file.fd, header, {offset: 0});
        AppLog.record('export encoded ' + mime + ' bytes=' + bytes + ' header=' +
          Array.from(new Uint8Array(header)).map((value: number) => value.toString(16).padStart(2, '0')).join(''));
        const writeStarted = Date.now();
        await fs.copyFile(temp, destination.fd);
        if (fs.statSync(destination.fd).size !== bytes) throw new Error('照片写入不完整');
        AppLog.record('export write ms=' + (Date.now() - writeStarted));
      } finally {
        fs.closeSync(file);
        fs.unlinkSync(temp);
      }
      this.dirty = false; this.message = '已保存到相册';
      const size = output.getImageInfoSync().size;
      AppLog.record('export complete ' + mime + ' ' + size.width + 'x' + size.height);
      AppLog.record('export filename ' + savedName);
      AppLog.record('export total ms=' + (Date.now() - started));
    } catch (err) {
      this.message = '保存失败，请重试';
      AppLog.failure('export', err as BusinessError); console.error('SpektraLab export: ' + String(err));
    } finally {
      if (destination) fs.closeSync(destination);
      framed?.release(); print?.release();
      this.busy = false;
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
        Image(this.compare ? this.original : this.printMap())
          .width(this.displayedWidth() * this.fittedScale()).height(this.displayedHeight() * this.fittedScale())
          .objectFit(ImageFit.Contain).borderRadius(CORNER_RADIUS).clip(true)
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
      Button({type: ButtonType.Normal}) {
        Image($r('app.media.compare_icon')).width(16).height(16)
      }.width(36).height(30).borderRadius(CORNER_RADIUS).backgroundColor(this.compare ? '#B86A512F' : '#AD252425').margin(10)
        .accessibilityText('按住查看原图，松开查看成片').onTouch(e => {
          if (e.type === TouchType.Down) this.compare = true;
          if (e.type === TouchType.Up || e.type === TouchType.Cancel) this.compare = false;
        })
    }.width('100%').layoutWeight(1).clip(true)
  }

  private hasMaterials(): boolean { return this.film.length > 0 && this.paper.length > 0; }

  private clearMaterials(): void {
    this.version++;
    this.film = ''; this.paper = ''; this.lastColorPaper = DEFAULT_PAPER;
    this.values = [0, 1, 1, 1]; this.frameEnabled = false;
    const preview = this.preview, framed = this.framed;
    this.preview = undefined; this.framed = undefined;
    preview?.release(); framed?.release();
    this.goodFilm = ''; this.goodPaper = ''; this.goodValues = this.values.slice();
    this.retryFilm = ''; this.retryPaper = ''; this.retryValues = [];
    this.matched = true; this.dirty = false; this.message = ''; this.compare = false;
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
  cover(stock: Stock) {
    if (stock.id) {
      Image($rawfile('materials/' + stock.id + '.webp')).objectFit(ImageFit.Cover)
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
    List({space: 8}) {
      ForEach(this.stocks(full), (stock: Stock, i: number) => {
        ListItem() {
          if (full) {
            Column({space: 6}) {
              if (stock.id && this.tab === 0 && (i === 0 || this.films[i-1].group !== stock.group)) {
                Text(stock.group).fontSize(13).fontColor('#B9B3AC').padding({top: 8})
              }
              this.materialRow(stock, false)
            }.width('100%').alignItems(HorizontalAlign.Start)
          } else { this.card(stock) }
        }
      }, (s: Stock) => s.id)
    }.listDirection(full ? Axis.Vertical : Axis.Horizontal)
      .layoutWeight(full ? 1 : 0)
      .height(full ? '100%' : 102).width('100%').scrollBar(BarState.Off)
      .onAreaChange((_a, area) => { this.cardWidth = Math.max(84, (Number(area.width) - 16) / 3); })
    if (!full) {
      if (this.filmProfile(this.film).reversal) {
        Text('反转片直扫').fontSize(15).fontColor('#E6E0D9')
          .width('100%').padding(12).margin({top: 8}).backgroundColor('#292829').borderRadius(CORNER_RADIUS)
      } else {
        Text(this.tab === 0 ? '相纸' : '胶片').width('100%').fontSize(12).fontColor('#C3BDB6').margin({top: 8, bottom: 5})
      ForEach((this.tab === 0 ? this.papers : this.films).filter((s: Stock) => this.selected(s)), (stock: Stock) => {
        this.materialRow(stock, true)
      }, (s: Stock) => s.id)
      }
      this.quickGrain()
    }
  }

  @Builder
  quickGrain() {
    Row() {
      Text('颗粒').fontSize(12).fontColor('#C3BDB6')
      Blank()
      Text(this.values[1].toFixed(1) + ' ×').fontSize(12).fontColor('#D6CFC6')
    }.width('100%').margin({top: 10})
    this.adjustmentSlider(1, true)
  }

  @Builder
  adjustmentSlider(index: number, compact: boolean = false) {
    Slider({value: this.values[index], min: index === 0 ? -this.limits[0] : 0,
      max: this.limits[index], step: 0.1, style: SliderStyle.InSet})
      .width('100%').height(compact ? 34 : 44).trackThickness(compact ? 16 : 24)
      .blockSize({width: compact ? 12 : 18, height: compact ? 12 : 18})
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
    Row() {
      Text('胶卷相框').fontSize(14).fontColor('#E6E0D9').layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.frameEnabled }).selectedColor('#AA763B')
        .accessibilityText('胶卷相框').onChange((enabled: boolean) => this.toggleFrame(enabled))
    }.height(44).width('100%').enabled(this.hasMaterials() && !this.rendering)
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
  materialTabs() {
    Row() {
      ForEach(['胶片','相纸','调整'], (label: string, i: number) => {
        Button(label, {type: ButtonType.Normal}).borderRadius(CORNER_RADIUS).layoutWeight(1).height(38).margin({left: 3, right: 3})
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
          TapGesture().onAction(() => this.snapPanel((this.panel + 1) % 3))
        ))
      if (this.panelPosition > 0.02 || this.panel !== 0) {
        this.materialTabs()
        if (this.tab === 2) {
          Scroll() { Column() { this.adjustments() }.width('100%') }
            .layoutWeight(1).width('100%').align(Alignment.Top)
        } else {
          Stack({alignContent: Alignment.TopStart}) {
            Column() { this.materials(false) }
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
      if (this.tab === 2) {
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
        .enabled(!this.busy && !this.rendering && !!this.assets)
        .onClick(() => { this.choosePhoto(); })
      MenuItem({content: '从文件选择'}).contentFontColor('#F2ECE5')
        .enabled(!this.busy && !this.rendering && !!this.assets)
        .onClick(() => { this.chooseFile(); })
      MenuItem({content: '设置'}).contentFontColor('#F2ECE5')
        .onClick(() => { this.getUIContext().getRouter().pushUrl({url: 'pages/Settings'}); })
    }.backgroundColor('#292829').radius(CORNER_RADIUS)
      .border({width: 0.5, color: '#50473F', radius: CORNER_RADIUS})
  }

  build() {
    Stack() {
    Column() {
      if (this.choosingPhoto) {
        FormatPhotoPicker({onCancel: () => this.cancelPhoto(), onConfirm: (uri: string) => this.confirmPhoto(uri)})
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
            .enabled(this.hasMaterials() && this.matched && !this.busy && !this.rendering)
            .onClick((_event: ClickEvent, result: SaveButtonOnClickResult) => {
              if (result === SaveButtonOnClickResult.SUCCESS) this.save();
              else if (result === SaveButtonOnClickResult.TEMPORARY_AUTHORIZATION_FAILED) this.message = '保存授权失败，请重试';
            })
        } else { Blank().width(78) }
      }.height(54).width('100%').padding({left: 14, right: 14})
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
    }.width('100%').height('100%').onAreaChange((_a, b) => { this.windowHeight = Number(b.height);
        this.windowWidth = Number(b.width) - this.getUIContext().px2vp(this.leftInset + this.rightInset); }).backgroundColor('#171819')
      .padding({top: this.topInset + 'px', left: this.leftInset + 'px', right: this.rightInset + 'px',
        bottom: !this.choosingPhoto && this.original && !this.wide() ? 0 : this.bottomInset + 'px'})
      if (this.saveHelpOpen) {
        Column() {
          Text('保存时，SpektraLab 会按照片的原始分辨率重新冲印，将胶片色彩、颗粒、光晕等效果计算到完整画面中，再生成照片并写入相册。原图的像素越多，处理时间通常越长。')
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
