export interface ReleaseNote {
  title: string;
  text: string;
}

export const RELEASE_NOTES: ReleaseNote[] = [
  {title: '照片裁切与旋转', text: '在照片预览打开裁切，可自由裁切、锁定原始比例或选择常用横竖比例，并向左或向右旋转 90°。'},
  {title: '按构图保存照片', text: '普通照片可直接保存裁切与旋转结果，冲印成片也会保留同一构图。'}
];
