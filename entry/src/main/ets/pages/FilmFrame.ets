import { image } from '@kit.ImageKit';
import { drawing } from '@kit.ArkGraphics2D';

function fraction(value: number): number { return value - Math.floor(value); }

function edgeType(canvas: drawing.Canvas, brush: drawing.Brush, font: drawing.Font,
  text: string, x: number, baseline: number, size: number, scaleX: number = 1): void {
  font.setSize(size);
  font.setScaleX(scaleX);
  const blob = drawing.TextBlob.makeFromString(text, font);
  brush.setColor(30, 186, 116, 48);
  canvas.attachBrush(brush);
  for (const dx of [-0.025, 0.025]) canvas.drawTextBlob(blob, x + size * dx, baseline);
  canvas.detachBrush();
  brush.setColor(255, 197, 153, 84);
  brush.setMaskFilter(drawing.MaskFilter.createBlurMaskFilter(drawing.BlurType.NORMAL, size * 0.007));
  canvas.attachBrush(brush);
  canvas.drawTextBlob(blob, x, baseline);
  canvas.detachBrush();
  brush.setMaskFilter(null);
}

function emulsionGrain(canvas: drawing.Canvas, length: number, rail: number, unit: number): void {
  const width = Math.max(1, Math.round(length / unit));
  const height = Math.max(1, Math.round(rail / unit));
  const pixels = new Uint8Array(width * height * 4);
  let seed = 173;
  for (let i = 3; i < pixels.length; i += 4) {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    pixels[i] = seed >>> 24 & 15;
  }
  const grain = image.createPixelMapSync(pixels.buffer, {size: {width, height},
    srcPixelFormat: image.PixelMapFormat.RGBA_8888, pixelFormat: image.PixelMapFormat.RGBA_8888});
  try {
    canvas.drawImageRect(grain, {left: 0, top: 0, right: length, bottom: rail},
      new drawing.SamplingOptions(drawing.FilterMode.FILTER_MODE_LINEAR));
  } finally { grain.release(); }
}

function edgeBars(canvas: drawing.Canvas, brush: drawing.Brush, length: number, rail: number): void {
  // Measured in the reference's 1100 x 140 lower rail, including connected code blocks.
  const blocks: number[][] = [
    [11, 925, 23, 990], [34, 925, 93, 990], [104, 925, 163, 990],
    [174, 925, 187, 964], [198, 925, 210, 990], [221, 925, 233, 990],
    [245, 925, 256, 964], [268, 925, 304, 990],
    [490, 925, 549, 990], [560, 925, 572, 990], [584, 925, 643, 990],
    [654, 925, 712, 990], [724, 925, 736, 962], [748, 925, 783, 990],
    [794, 925, 806, 962], [818, 925, 853, 990], [1028, 925, 1086, 990]
  ];
  const notches: number[][] = [
    [46, 925, 58, 964], [70, 925, 81, 964],
    [116, 925, 128, 964], [139, 925, 151, 964], [128, 964, 139, 990],
    [280, 964, 291, 990], [502, 963, 513, 990], [525, 963, 537, 990],
    [596, 925, 607, 962], [619, 925, 630, 962],
    [666, 925, 677, 962], [689, 925, 700, 962], [678, 962, 689, 990],
    [759, 925, 771, 962], [771, 962, 783, 990], [830, 962, 841, 990],
    [1040, 960, 1051, 990], [1063, 960, 1074, 990]
  ];
  for (let pass = 0; pass < 2; pass++) {
    if (pass === 0) brush.setColor(255, 203, 159, 89);
    else brush.setColor(255, 2, 1, 2);
    canvas.attachBrush(brush);
    for (const rect of pass === 0 ? blocks : notches) {
      canvas.drawRect({left: rect[0] * length / 1100, top: (990 - rect[3]) * rail / 140,
        right: rect[2] * length / 1100, bottom: (990 - rect[1]) * rail / 140});
    }
    canvas.detachBrush();
  }
}

function filmRail(canvas: drawing.Canvas, brush: drawing.Brush, length: number,
  rail: number, pitch: number, lower: boolean): void {
  brush.setColor(255, 2, 1, 2);
  canvas.attachBrush(brush);
  canvas.drawRect({left: 0, top: 0, right: length, bottom: rail});
  canvas.detachBrush();
  if (lower) edgeBars(canvas, brush, length, rail);
  const unit = rail / (lower ? 140 : 145);
  emulsionGrain(canvas, length, rail, unit);
  const count = Math.round(length / pitch);
  for (let i = 0; i < count; i++) {
    const x = (i + (lower ? 0.325 : 0.28)) * pitch;
    const y = (lower ? 92 : 91) * unit;
    const halfWidth = 31.5 * unit;
    const halfHeight = 42 * unit;
    brush.setShaderEffect(drawing.ShaderEffect.createLinearGradient(
      {x: x - halfWidth, y: y + halfHeight}, {x: x + halfWidth, y: y - halfHeight},
      [0xFF403004, 0xFF75600D, 0xFF0B0802, 0xFF352007], drawing.TileMode.CLAMP,
      [0, 0.22, 0.7, 1]));
    brush.setMaskFilter(drawing.MaskFilter.createBlurMaskFilter(drawing.BlurType.NORMAL, unit * 0.32));
    canvas.attachBrush(brush);
    canvas.drawRoundRect(new drawing.RoundRect({left: x - halfWidth - unit, top: y - halfHeight - unit,
      right: x + halfWidth + unit, bottom: y + halfHeight + unit}, 13 * unit, 13 * unit));
    canvas.detachBrush();
    brush.setShaderEffect(null);
    brush.setMaskFilter(null);
    brush.setColor(255, 0, 0, 0);
    canvas.attachBrush(brush);
    canvas.drawRoundRect(new drawing.RoundRect({left: x - halfWidth, top: y - halfHeight,
      right: x + halfWidth, bottom: y + halfHeight}, 12 * unit, 12 * unit));
    canvas.detachBrush();
  }
  // Fixed film-space grain keeps preview and full-resolution exports consistent.
  brush.setColor(10, 118, 81, 45);
  canvas.attachBrush(brush);
  for (let i = 0; i < 2200; i++) {
    const x = fraction(Math.sin(i * 127.1 + 17) * 43758.5453) * length;
    const y = fraction(Math.sin(i * 311.7 + 53) * 19731.743) * rail;
    canvas.drawCircle(x, y, unit * (i % 4 === 0 ? 0.42 : 0.24));
  }
  canvas.detachBrush();
}

// Both orientations use the same film-transport coordinates.
export function framePrint(photo: image.PixelMap, name: string): image.PixelMap {
  const size = photo.getImageInfoSync().size;
  const portrait = size.height > size.width;
  const short = Math.min(size.width, size.height);
  const upperRail = Math.max(4, Math.round(short * 145 / 704));
  const lowerRail = Math.max(4, Math.round(short * 140 / 704));
  const end = Math.max(1, Math.round(short * 25 / 704));
  const left = portrait ? lowerRail : end;
  const top = portrait ? end : upperRail;
  const width = size.width + (portrait ? upperRail + lowerRail : 2 * end);
  const height = size.height + (portrait ? 2 * end : upperRail + lowerRail);
  const framed = image.createPixelMapSync({size: {width, height}, editable: true,
    pixelFormat: image.PixelMapFormat.RGBA_8888});
  try {
    const canvas = new drawing.Canvas(framed);
    const brush = new drawing.Brush();
    brush.setAntiAlias(true);
    brush.setColor(255, 2, 1, 2);
    canvas.drawBackground(brush);
    canvas.save();
    const radius = Math.max(1, short * 8 / 704);
    canvas.clipRoundRect(new drawing.RoundRect({left, top, right: left + size.width,
      bottom: top + size.height}, radius, radius), drawing.ClipOp.INTERSECT, true);
    canvas.drawImage(photo, left, top);
    canvas.restore();
    if (portrait) {
      canvas.translate(width, 0);
      canvas.rotate(90, 0, 0);
    }
    const length = portrait ? height : width;
    const breadth = portrait ? width : height;
    const count = Math.max(2, Math.round(length / (short * 137.5 / 704)));
    const pitch = length / count;
    filmRail(canvas, brush, length, upperRail, pitch, false);
    canvas.save();
    canvas.translate(0, breadth);
    canvas.scale(1, -1);
    filmRail(canvas, brush, length, lowerRail, pitch, true);
    canvas.restore();

    const font = new drawing.Font();
    font.setTypeface(drawing.Typeface.makeFromRawFile($rawfile('fonts/LiberationSans-Bold.ttf')));
    const stock = name.toUpperCase();
    const u = upperRail / 145;
    const b = lowerRail / 140;
    const rating = stock.match(/\b\d{2,4}\b/);
    if (rating) edgeType(canvas, brush, font, rating[0], 0, 35 * u, 49 * u, 0.98);
    edgeType(canvas, brush, font, '35', length * 400 / 1100, 35 * u, 49 * u, 1.38);
    font.setSize(49 * u);
    font.setScaleX(1);
    const stockWidth = font.measureText(stock, drawing.TextEncoding.TEXT_ENCODING_UTF8);
    const stockX = length * 654 / 1100;
    const stockRight = length - Math.max(12 * u, length * 0.015);
    const typeSize = 49 * u * Math.min(1, (stockRight - stockX) / Math.max(1, stockWidth));
    edgeType(canvas, brush, font, stock, stockX, 34 * u, typeSize);
    edgeType(canvas, brush, font, '35', length * 383 / 1100, breadth - 8 * b, 55 * b, 1.48);
    edgeType(canvas, brush, font, '35A', length * 922 / 1100, breadth - 27 * b, 45 * b, 1.1);
    brush.setColor(255, 197, 154, 85);
    canvas.attachBrush(brush);
    const arrow = new drawing.Path();
    const x = length / 1100;
    arrow.moveTo(903 * x, breadth - 14 * b);
    arrow.lineTo(968 * x, breadth - 14 * b);
    arrow.lineTo(968 * x, breadth - 21 * b);
    arrow.lineTo(1014 * x, breadth - 12 * b);
    arrow.lineTo(968 * x, breadth - 3 * b);
    arrow.lineTo(968 * x, breadth - 9 * b);
    arrow.lineTo(903 * x, breadth - 9 * b);
    arrow.close();
    canvas.drawPath(arrow);
    canvas.detachBrush();
    return framed;
  } catch (err) {
    framed.release();
    throw new Error(String(err));
  }
}
