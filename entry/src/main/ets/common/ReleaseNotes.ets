export interface ReleaseNote {
  title: string;
  text: string;
}

export const RELEASE_NOTES: ReleaseNote[] = [
  {title: '冲印与导出提速', text: '重构底层 GPU 计算与内存复用管线，完整画质冲印和导出明显加快，结果保持无损一致。'},
  {title: '极速预览与后台预解', text: 'RAW 照片导入先以轻量化预览快速进入编辑页，同时在后台预解原片；调整相纸参数直接复用已冲印底片，减少重复等待。'},
  {title: '导出画质选项', text: '设置页新增「导出画质」，可在保持原始无损结果的「高质量」与更快的「快速」模式之间切换。'},
  {title: '资源更新校验', text: '引擎着色器与资源包升级时自动校验内容摘要，避免旧版缓存导致冲印异常。'}
];
