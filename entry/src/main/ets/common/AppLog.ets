import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';

const CURRENT = '/spektralab.log';
const PREVIOUS = '/spektralab.previous.log';

export class AppLog {
  private static dir: string = '';

  static start(dir: string): void {
    AppLog.dir = dir;
    AppLog.record('app start');
  }

  static record(event: string): void {
    console.info('SpektraLab ' + event);
    try {
      const path = AppLog.dir + CURRENT;
      if (fs.accessSync(path) && fs.statSync(path).size >= 64 * 1024) {
        fs.renameSync(path, AppLog.dir + PREVIOUS);
      }
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.APPEND);
      try {
        fs.writeSync(file.fd, new Date().toISOString() + ' ' + event + '\n');
      } finally { fs.closeSync(file); }
    } catch (_) { console.error('SpektraLab: 无法记录日志'); }
  }

  static failure(event: string, error: BusinessError): void {
    const message = String(error.message ?? error).split('\n')[0];
    const detail = /[\/@\\]/.test(message) ? '' : ' ' + message.slice(0, 160);
    AppLog.record(event + ' error' + (error.code !== undefined ? ' code=' + error.code : '') + detail);
  }

  static snapshot(ctx: common.UIAbilityContext): string {
    const previous = AppLog.dir + PREVIOUS;
    const text = (fs.accessSync(previous) ? fs.readTextSync(previous) : '') + fs.readTextSync(AppLog.dir + CURRENT);
    if (!text.length) throw new Error('日志为空');
    const now = Date.now();
    for (const name of fs.listFileSync(ctx.cacheDir)) {
      const match = /^SpektraLab-(?:shot-)?(\d+)(?:\.[a-zA-Z0-9]{1,8})?$/.exec(name);
      if (match && now - Number(match[1]) > 7 * 86400000) fs.unlinkSync(ctx.cacheDir + '/' + name);
    }
    const path = ctx.cacheDir + '/SpektraLab-' + now + '.log';
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      const bytes = new util.TextEncoder().encodeInto(text);
      if (fs.writeSync(file.fd, bytes.buffer) !== bytes.byteLength) throw new Error('日志写入不完整');
    } finally { fs.closeSync(file); }
    return fileUri.getUriFromPath(path);
  }
}
