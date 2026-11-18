export interface ReleaseNote {
  title: string;
  text: string;
}

export const RELEASE_NOTES: ReleaseNote[] = [
  {title: '检查应用更新', text: '发现新版本时可前往应用商店更新；选择“稍后”后，七天内暂停自动提醒，仍可在设置中手动检查。'},
  {title: '查看版本日志', text: '在设置中打开更新日志，即可查看当前版本的变化。'}
];
