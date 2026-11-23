import { image } from '@kit.ImageKit';
import { drawing } from '@kit.ArkGraphics2D';
import { resourceManager } from '@kit.LocalizationKit';
import { framePrint } from './FilmFrame';
import { PhotoGeometry } from '../common/PhotoGeometry';
import { framingInSource } from '../common/BorderFraming';

export interface FrameBorder {
  id: string;
  name: string;
  width: number;
  height: number;
  windows: number[][];
}

export const FILM_RAIL: string = 'film-rail';
const LOCAL_FRAME_BORDERS: FrameBorder[] = [
  { id: '02-10', name: 'Kodak 400UC', width: 880, height: 798,
    windows: [[0.016364, 0.148445, 0.958182, 0.707121]] },
  { id: '07-02', name: 'Portra 400 · 齿孔边 · 单边', width: 880, height: 776,
    windows: [[0.0, 0.243764, 1.0, 0.756236]] },
  { id: '03-10', name: '粉紫色漏光', width: 850, height: 478,
    windows: [[0.0, 0.129707, 1.0, 0.742678]] },
  { id: '02-06', name: 'Ektar 100 · 橙色边码', width: 880, height: 875,
    windows: [[0.062264, 0.038899, 0.895283, 0.899431]] },
  { id: '04-01', name: '细黑暗房边', width: 716, height: 880,
    windows: [[0.035436, 0.021082, 0.941227, 0.950105]] },
  { id: '01-01', name: '双格齿孔', width: 720, height: 490,
    windows: [[0.015278, 0.153061, 0.4375, 0.687755], [0.516667, 0.153061, 0.466667, 0.687755]] },
  { id: '01-02', name: '竖幅宽边带色码', width: 453, height: 680,
    windows: [[0.090508, 0.132353, 0.777042, 0.732353]] },
  { id: '01-03', name: 'Portra 400 四格接触印样', width: 661, height: 880,
    windows: [[0.083333, 0.022523, 0.36, 0.472973], [0.554, 0.026527, 0.349333, 0.464965], [0.074, 0.532533, 0.369333, 0.467467], [0.552667, 0.525025, 0.356667, 0.474975]] },
  { id: '01-04', name: 'Portra 400 三格横向片条', width: 880, height: 302,
    windows: [[0.0, 0.0, 1.0, 1.0]] },
  { id: '01-05', name: 'Portra 400 · 25 / 25A', width: 869, height: 880,
    windows: [[0.0, 0.171165, 1.0, 0.664911]] },
  { id: '01-06', name: 'Portra 多格接触印样', width: 880, height: 848,
    windows: [[0.01, 0.0, 0.98, 1.0]] },
  { id: '02-01', name: 'Portra 400 · 35 / 35A', width: 880, height: 792,
    windows: [[0.023636, 0.148485, 0.952727, 0.709091]] },
  { id: '02-02', name: 'Portra 400 · 窄边', width: 548, height: 490,
    windows: [[0.043796, 0.038776, 0.928832, 0.946939]] },
  { id: '02-03', name: 'CineStill 400D', width: 552, height: 493,
    windows: [[0.021739, 0.156187, 0.952899, 0.697769]] },
  { id: '02-04', name: 'Portra 400 · 明色齿孔', width: 548, height: 509,
    windows: [[0.023723, 0.166994, 0.958029, 0.691552]] },
  { id: '02-05', name: 'CineStill 800T · 明色齿孔', width: 552, height: 501,
    windows: [[0.047101, 0.157685, 0.927536, 0.710579]] },
  { id: '02-07', name: '不规则中画幅边口', width: 880, height: 725,
    windows: [[0.015267, 0.028935, 0.955153, 0.931713]] },
  { id: '02-08', name: 'Ilford HP5 Plus', width: 880, height: 798,
    windows: [[0.0, 0.140421, 0.980909, 0.713139]] },
  { id: '02-09', name: '彩色三格片条', width: 880, height: 272,
    windows: [[0.015455, 0.155882, 0.318182, 0.7], [0.343636, 0.155882, 0.323636, 0.7], [0.679091, 0.155882, 0.313636, 0.7]] },
  { id: '03-01', name: '青棕色漏光', width: 850, height: 478,
    windows: [[0.0, 0.121339, 1.0, 0.753138]] },
  { id: '03-02', name: 'CineStill 800T', width: 525, height: 478,
    windows: [[0.017143, 0.148536, 0.965714, 0.700837]] },
  { id: '03-03', name: 'CineStill BWXX', width: 525, height: 478,
    windows: [[0.017143, 0.150628, 0.965714, 0.700837]] },
  { id: '03-04', name: 'Fuji 400 · 3', width: 531, height: 478,
    windows: [[0.016949, 0.140167, 0.966102, 0.717573]] },
  { id: '03-05', name: 'Fuji 400 · 18', width: 524, height: 478,
    windows: [[0.017176, 0.142259, 0.965649, 0.715481]] },
  { id: '03-06', name: 'Ilford SFX 200 · 4', width: 529, height: 478,
    windows: [[0.017013, 0.146444, 0.965974, 0.707113]] },
  { id: '03-07', name: 'Ilford SFX 200 · 20', width: 528, height: 478,
    windows: [[0.017045, 0.150628, 0.965909, 0.700837]] },
  { id: '03-08', name: 'Kodak P3200TMZ', width: 529, height: 478,
    windows: [[0.017013, 0.146444, 0.965974, 0.707113]] },
  { id: '03-09', name: 'Kodak GC 400', width: 526, height: 478,
    windows: [[0.01711, 0.144351, 0.965779, 0.709205]] },
  { id: '04-02', name: '35mm 暗房厚边', width: 621, height: 880,
    windows: [[0.054545, 0.04156, 0.892364, 0.935351]] },
  { id: '04-03', name: '中画幅手工黑边', width: 714, height: 880,
    windows: [[0.044248, 0.034341, 0.924147, 0.939006]] },
  { id: '06-01', name: '黑色暗房相纸边', width: 880, height: 583,
    windows: [[0.016178, 0.024427, 0.968655, 0.952672]] },
  { id: '07-01', name: 'Portra 接触印样', width: 733, height: 880,
    windows: [[0.021469, 0.070555, 0.963842, 0.780809]] },
  { id: '07-03', name: 'Portra 400 · 窄边 · 单边', width: 880, height: 663,
    windows: [[0.0, 0.11421, 1.0, 0.88579]] },
  { id: '07-04', name: 'Portra 800-2 · 单边', width: 880, height: 661,
    windows: [[0.0, 0.111851, 1.0, 0.888149]] },
  { id: '07-05', name: '400TX · 单边', width: 880, height: 820,
    windows: [[0.0, 0.284335, 1.0, 0.715665]] },
  { id: '08-01', name: 'Cinegrading Portra 400', width: 815, height: 668,
    windows: [[0.015951, 0.047904, 0.928834, 0.905689]] },
  { id: '12-01', name: '双格扫描边框', width: 600, height: 338,
    windows: [[0.03, 0.017751, 0.463333, 0.95858], [0.52, 0.017751, 0.463333, 0.95858]] },
];

export const NO_FRAME: FrameBorder = { id: '', name: '无边框', width: 0, height: 0, windows: [] };

export const BUILT_IN_FRAME_BORDERS: FrameBorder[] = [
  { id: 'studio-wide', name: '暖棕 35 mm', width: 900, height: 690,
    windows: [[0.04, 0.13, 0.92, 0.72]] },
  { id: 'studio-square', name: '方幅暗房', width: 850, height: 850,
    windows: [[0.05, 0.05, 0.9, 0.9]] },
  { id: 'studio-portrait', name: '竖幅相纸', width: 720, height: 900,
    windows: [[0.05, 0.04, 0.9, 0.9]] },
  { id: FILM_RAIL, name: '胶卷相框', width: 0, height: 0, windows: [] }
];

export function availableFrameBorders(resources: resourceManager.ResourceManager): FrameBorder[] {
  let files: string[] = [];
  try { files = resources.getRawFileListSync('borders'); } catch (_) {}
  return LOCAL_FRAME_BORDERS.filter((border: FrameBorder) =>
    files.includes(border.id + '.webp') || files.includes('borders/' + border.id + '.webp'))
    .concat(BUILT_IN_FRAME_BORDERS);
}

function studioOverlay(border: FrameBorder, longest: number): image.PixelMap {
  const scale = longest ? Math.min(1, longest / Math.max(border.width, border.height)) : 1;
  const width = Math.max(1, Math.round(border.width * scale));
  const height = Math.max(1, Math.round(border.height * scale));
  const result = image.createPixelMapSync({size: {width, height}, editable: true,
    pixelFormat: image.PixelMapFormat.RGBA_8888});
  try {
    const canvas = new drawing.Canvas(result);
    const brush = new drawing.Brush();
    const window = border.windows[0];
    const left = window[0] * width;
    const top = window[1] * height;
    const right = (window[0] + window[2]) * width;
    const bottom = (window[1] + window[3]) * height;
    if (border.id === 'studio-portrait') brush.setColor(255, 238, 227, 206);
    else if (border.id === 'studio-square') brush.setColor(255, 32, 30, 27);
    else brush.setColor(255, 49, 29, 22);
    canvas.attachBrush(brush);
    canvas.drawRect({left: 0, top: 0, right: width, bottom: top});
    canvas.drawRect({left: 0, top: bottom, right: width, bottom: height});
    canvas.drawRect({left: 0, top, right: left, bottom});
    canvas.drawRect({left: right, top, right: width, bottom});
    canvas.detachBrush();
    if (border.id === 'studio-wide') {
      brush.setColor(255, 205, 151, 88);
      canvas.attachBrush(brush);
      const font = new drawing.Font();
      font.setSize(height * 0.035);
      canvas.drawTextBlob(drawing.TextBlob.makeFromString('35 MM', font), left, top * 0.46);
      canvas.drawTextBlob(drawing.TextBlob.makeFromString('35A', font), right * 0.9, height * 0.96);
      canvas.detachBrush();
      brush.setColor(255, 16, 12, 10);
      canvas.attachBrush(brush);
      for (let i = 0; i < 8; i++) {
        const x = width * (0.048 + i * 0.12);
        const w = width * 0.053;
        canvas.drawRoundRect(new drawing.RoundRect({left: x, right: x + w,
          top: top * 0.6, bottom: top * 0.85}, w * 0.1, w * 0.1));
      }
      canvas.detachBrush();
    }
    return result;
  } catch (err) {
    result.release();
    throw new Error(String(err));
  }
}

export function borderAperture(border: FrameBorder): number {
  if (border.windows.length !== 1 || border.id === '01-04' || border.id === '01-06') return 0;
  return border.windows[0][2] * border.width / (border.windows[0][3] * border.height);
}

export async function loadBorderOverlay(resources: resourceManager.ResourceManager, border: FrameBorder,
  longest: number = 0): Promise<image.PixelMap | undefined> {
  if (!border.width) return undefined;
  if (border.id.startsWith('studio-')) return studioOverlay(border, longest);
  const bytes = await resources.getRawFileContent('borders/' + border.id + '.webp');
  const source = image.createImageSource(bytes.slice().buffer);
  try {
    const scale = longest > 0 ? Math.min(1, longest / Math.max(border.width, border.height)) : 1;
    return await source.createPixelMap({
      desiredSize: {width: Math.max(1, Math.round(border.width * scale)),
        height: Math.max(1, Math.round(border.height * scale))},
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
    });
  } finally { await source.release(); }
}

export function composeBorder(photo: image.PixelMap, border: FrameBorder, overlay: image.PixelMap | undefined,
  film: string, longest: number = 0, framing?: PhotoGeometry): image.PixelMap {
  const size = photo.getImageInfoSync().size;
  const sampling = new drawing.SamplingOptions(drawing.FilterMode.FILTER_MODE_LINEAR);
  if (border.id === FILM_RAIL) {
    if (!longest) return framePrint(photo, film);
    const scale = longest / Math.max(size.width, size.height);
    const width = Math.max(1, Math.round(size.width * scale));
    const height = Math.max(1, Math.round(size.height * scale));
    const thumb = image.createPixelMapSync({size: {width, height}, editable: true,
      pixelFormat: image.PixelMapFormat.RGBA_8888});
    try {
      new drawing.Canvas(thumb).drawImageRect(photo, {left: 0, top: 0, right: width, bottom: height}, sampling);
      return framePrint(thumb, film);
    } finally { thumb.release(); }
  }
  if (border.id && !overlay) throw new Error('边框图层缺失');
  const outputLength = longest || Math.max(size.width, size.height);
  const aspectWidth = border.width || size.width;
  const aspectHeight = border.height || size.height;
  const factor = outputLength / Math.max(aspectWidth, aspectHeight);
  const width = Math.max(1, Math.round(aspectWidth * factor));
  const height = Math.max(1, Math.round(aspectHeight * factor));
  const output = image.createPixelMapSync({size: {width, height}, editable: true,
    pixelFormat: image.PixelMapFormat.RGBA_8888});
  try {
    const canvas = new drawing.Canvas(output);
    const brush = new drawing.Brush();
    brush.setColor(255, 8, 8, 9);
    canvas.drawBackground(brush);
    const windows = overlay ? border.windows : [[0, 0, 1, 1]];
    for (const window of windows) {
      const left = window[0] * width;
      const top = window[1] * height;
      const w = window[2] * width;
      const h = window[3] * height;
      if (framing) {
        const source = framingInSource(framing);
        const sideways = framing.angle % 180 !== 0;
        const dw = sideways ? h : w;
        const dh = sideways ? w : h;
        canvas.save();
        canvas.translate(left + w / 2, top + h / 2);
        canvas.rotate(framing.angle, 0, 0);
        canvas.drawImageRectWithSrc(photo, {left: source.left * size.width, top: source.top * size.height,
          right: source.right * size.width, bottom: source.bottom * size.height},
          {left: -dw / 2, top: -dh / 2, right: dw / 2, bottom: dh / 2}, sampling);
        canvas.restore();
        continue;
      }
      const scale = Math.max(w / size.width, h / size.height);
      const sw = w / scale;
      const sh = h / scale;
      const x = Math.max(0, (size.width - sw) / 2);
      const y = Math.max(0, (size.height - sh) / 2);
      canvas.drawImageRectWithSrc(photo, {left: x, top: y,
        right: Math.min(size.width, x + sw), bottom: Math.min(size.height, y + sh)},
        {left, top, right: left + w, bottom: top + h}, sampling);
    }
    if (overlay) canvas.drawImageRect(overlay, {left: 0, top: 0, right: width, bottom: height}, sampling);
    return output;
  } catch (err) {
    output.release();
    throw new Error(String(err));
  }
}
