import { common } from '@kit.AbilityKit';
import { curves, window } from '@kit.ArkUI';

@Entry
@Component
struct Credits {
  @State private glow: number = 0;
  @State private orbit: number = -35;
  @State private expansion: number = 0.65;
  @State private developed: number = 0;
  @State private powered: number = 0;
  @State private heart: number = 0;
  @State private heartbeat: number = 0.7;
  @State private sceneOpacity: number = 1;
  private timers: number[] = [];
  private active: boolean = false;
  private closing: boolean = false;
  private mainWindow: window.Window | undefined = undefined;

  aboutToAppear(): void {
    this.active = true;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    window.getLastWindow(context).then((win: window.Window) => {
      if (!this.active) return;
      this.mainWindow = win;
      win.setWindowSystemBarEnable([]).catch(() => {});
    }).catch(() => {});
    this.later(80, () => {
      this.getUIContext().animateTo({duration: 2600, curve: Curve.EaseOut}, () => {
        this.glow = 1; this.expansion = 1; this.orbit = 25;
      });
    });
    this.later(500, () => {
      this.getUIContext().animateTo({duration: 1000, curve: Curve.EaseOut}, () => { this.developed = 1; });
    });
    this.later(1700, () => {
      this.getUIContext().animateTo({duration: 1000, curve: Curve.EaseOut}, () => { this.powered = 1; });
    });
    this.later(2800, () => {
      this.getUIContext().animateTo({duration: 750, curve: curves.springMotion(0.5, 0.75)}, () => {
        this.heart = 1; this.heartbeat = 1;
      });
    });
    this.later(3700, () => {
      this.getUIContext().animateTo({duration: 650, iterations: 2, playMode: PlayMode.Alternate,
        curve: Curve.EaseInOut}, () => { this.heartbeat = 1.12; });
    });
    this.later(6500, () => this.close());
  }

  private later(delay: number, action: () => void): void {
    this.timers.push(setTimeout(() => { if (this.active && !this.closing) action(); }, delay));
  }

  private clearTimers(): void {
    this.timers.forEach((timer: number) => clearTimeout(timer));
    this.timers = [];
  }

  aboutToDisappear(): void {
    this.active = false;
    this.clearTimers();
    this.mainWindow?.setWindowSystemBarEnable(['status', 'navigation']).catch(() => {});
  }

  private close(): void {
    if (this.closing || !this.active) return;
    this.closing = true;
    this.clearTimers();
    this.getUIContext().animateTo({duration: 450, curve: Curve.EaseIn,
      onFinish: () => { if (this.active) this.getUIContext().getRouter().back(); }}, () => {
      this.sceneOpacity = 0; this.expansion = 1.08;
    });
  }

  onBackPress(): boolean { this.close(); return true; }

  build() {
    Stack() {
      Stack({alignContent: Alignment.Center}) {
        Stack() {
          Circle().width(330).height(330).fill(Color.Transparent)
            .radialGradient({center: ['50%', '50%'], radius: 165,
              colors: [['#20EFBD70', 0], ['#00EFBD70', 1]]})
          Circle().width(240).height(240).fill(Color.Transparent).stroke('#40EFBD70').strokeWidth(1)
            .rotate({x: 1, y: 0, z: 0, angle: 66})
          Circle().width(290).height(290).fill(Color.Transparent).stroke('#20EFBD70').strokeWidth(1)
            .rotate({x: 0, y: 1, z: 0, angle: 62})
        }.rotate({angle: this.orbit}).scale({x: this.expansion, y: this.expansion})
          .opacity(this.glow).translate({y: -135}).accessibilityLevel('no')
        Column() {
          Image($r('app.media.developing_aperture')).width(42).height(42)
            .rotate({angle: this.orbit * 2}).opacity(this.glow).margin({bottom: 38}).accessibilityLevel('no')
          Column({space: 8}) {
            Text('Developed By').fontSize(16).fontColor('#C4B8A6').letterSpacing(1.2)
            Text('Musher').fontSize(54).fontWeight(FontWeight.Lighter).fontColor('#FFF0DA').letterSpacing(1)
          }.opacity(this.developed).translate({y: 20 * (1 - this.developed)})
          Divider().width(36).color('#756044').margin({top: 30, bottom: 30}).opacity(this.powered)
          Column({space: 8}) {
            Text('Powered By').fontSize(16).fontColor('#C4B8A6').letterSpacing(1.2)
            Text('Donut').fontSize(42).fontWeight(FontWeight.Lighter).fontColor('#EFBD70').letterSpacing(1)
          }.opacity(this.powered).translate({y: 20 * (1 - this.powered)})
          Row({space: 9}) {
            Text('With').fontSize(16).fontColor('#C4B8A6')
            Text('❤️').fontSize(23).scale({x: this.heartbeat, y: this.heartbeat})
          }.margin({top: 24}).opacity(this.heart)
        }.width('100%').padding({left: 28, right: 28})
        Button('关闭', {type: ButtonType.Normal}).fontSize(14).fontColor('#B9AC98')
          .width(72).height(44).backgroundColor('#20201F').borderRadius(22)
          .position({x: '50%', y: '88%'}).translate({x: -36})
          .onClick(() => this.close()).accessibilityText('关闭彩蛋')
      }.width('100%').height('100%').opacity(this.sceneOpacity)
    }.width('100%').height('100%').backgroundColor('#121315')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
