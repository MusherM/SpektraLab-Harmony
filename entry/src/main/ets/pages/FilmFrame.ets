import { image } from '@kit.ImageKit';
import { drawing } from '@kit.ArkGraphics2D';

// Draw the two rails in film-transport coordinates, including on portrait prints.
export function framePrint(photo: image.PixelMap, name: string): image.PixelMap {
  const size = photo.getImageInfoSync().size;
  const portrait = size.height > size.width;
  const short = Math.min(size.width, size.height);
  const rail = Math.max(4, Math.round(short * 0.095));
  const end = Math.max(1, Math.round(short * 0.016));
  const left = portrait ? rail : end;
  const top = portrait ? end : rail;
  const width = size.width + 2 * left;
  const height = size.height + 2 * top;
  const framed = image.createPixelMapSync({ size: { width, height }, editable: true,
    pixelFormat: image.PixelMapFormat.RGBA_8888 });
  try {
    const canvas = new drawing.Canvas(framed);
    const brush = new drawing.Brush();
    brush.setAntiAlias(true);
    brush.setColor(255, 31, 25, 21);
    canvas.drawBackground(brush);
    canvas.drawImage(photo, left, top);
    if (portrait) {
      canvas.translate(width, 0);
      canvas.rotate(90, 0, 0);
    }
    const length = portrait ? height : width;
    const breadth = portrait ? width : height;
    const count = Math.max(2, Math.round(length / (1.9 * rail)));
    const pitch = length / count;
    brush.setColor(255, 236, 226, 204);
    canvas.attachBrush(brush);
    for (let i = 0; i < count; i++) {
      const x = (i + 0.5) * pitch;
      for (const y of [0.29 * rail, breadth - 0.29 * rail]) {
        canvas.drawRoundRect(new drawing.RoundRect({ left: x - 0.28 * rail, top: y - 0.13 * rail,
          right: x + 0.28 * rail, bottom: y + 0.13 * rail }, rail * 0.065, rail * 0.065));
      }
    }
    canvas.detachBrush();
    brush.setColor(255, 235, 175, 91);
    canvas.attachBrush(brush);
    const font = new drawing.Font();
    font.setSize(rail * 0.32);
    const stock = name.toUpperCase();
    if (font.measureText(stock, drawing.TextEncoding.TEXT_ENCODING_UTF8) > length * 0.78) {
      font.setSize(rail * 0.32 * length * 0.78 / font.measureText(stock, drawing.TextEncoding.TEXT_ENCODING_UTF8));
    }
    canvas.drawTextBlob(drawing.TextBlob.makeFromString(stock, font), end + pitch * 0.18, rail * 0.87);
    canvas.drawTextBlob(drawing.TextBlob.makeFromString('01', font), length - pitch, breadth - rail * 0.58);
    canvas.detachBrush();
    return framed;
  } catch (err) {
    framed.release();
    throw new Error(String(err));
  }
}
