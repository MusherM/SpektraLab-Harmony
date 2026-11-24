export const render: (resources: string, pixels: ArrayBuffer, width: number, height: number, params: string,
  operation?: number) => ArrayBuffer;
export interface RawFrame { pixels: ArrayBuffer; width: number; height: number; rawInfo?: string; warning?: string; displayPixels?: ArrayBuffer }
export const decodeRaw: (fd: number, cacheDir: string, operation?: number) => RawFrame;
export const renderLinear: typeof render;
export const renderRaw: (resources: string, fd: number, params: string, cacheDir: string, operation?: number) => RawFrame;
export const clearResources: (releaseEngine: boolean) => void;
export const beginOperation: () => number;
export const cancelOperation: (operation: number) => void;
export const endOperation: (operation: number) => void;

declare const nativeEngine: {
  render: typeof render;
  renderLinear: typeof renderLinear;
  renderRaw: typeof renderRaw;
  decodeRaw: typeof decodeRaw;
  clearResources: typeof clearResources;
  beginOperation: typeof beginOperation;
  cancelOperation: typeof cancelOperation;
  endOperation: typeof endOperation;
};

export default nativeEngine;
