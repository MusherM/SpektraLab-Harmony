export type ExportQuality = 'HIGH' | 'FAST';

export const EXPORT_QUALITY_OPTIONS: ExportQuality[] = ['HIGH', 'FAST'];

export function normalizeExportQuality(value: string): ExportQuality {
  return value === 'FAST' ? 'FAST' : 'HIGH';
}

export function isFastExport(quality: string): boolean {
  return normalizeExportQuality(quality) === 'FAST';
}

export function exportQualityLabel(quality: ExportQuality): string {
  return quality === 'FAST' ? '快速' : '高质量';
}

export function exportQualityDescription(quality: string): string {
  return isFastExport(quality)
    ? '保留颗粒与眩光质感，显著缩短导出耗时'
    : '原画质无损冲印，适合保存原片与后期';
}
