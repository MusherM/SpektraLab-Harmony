export interface ReleaseNote {
  title: string;
  text: string;
}

export const RELEASE_NOTES: ReleaseNote[] = [
  {title: '修复部分华为竖拍 DNG 的方向', text: '导入预览和保存到相册的成片保持拍摄方向。'}
];
