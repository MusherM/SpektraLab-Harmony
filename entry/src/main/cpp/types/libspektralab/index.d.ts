export const render: (resources: string, pixels: ArrayBuffer, width: number, height: number, params: string) => ArrayBuffer;
export interface RawFrame { pixels: ArrayBuffer; width: number; height: number; rawInfo?: string; warning?: string; displayPixels?: ArrayBuffer }
export const decodeRaw: (fd: number, cacheDir: string) => RawFrame;
export const renderLinear: typeof render;
export const renderRaw: (resources: string, fd: number, params: string, cacheDir: string) => RawFrame;
export const clearResources: (releaseEngine: boolean) => void;
