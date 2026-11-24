import { KeyCode } from '@kit.InputKit';
import { SelectionHaptics } from '../common/SelectionHaptics';
import { MATERIAL_PAGER_ACTIVE_WIDTH, MATERIAL_PAGER_INSET, MATERIAL_PAGER_VISIBLE_DOTS, materialDotPageAt,
  materialDotSize, materialDotWindowStart, materialDotX, materialExpandedPagerWidth, materialExpandedPagePosition,
  materialPagerWidth } from '../common/MaterialPagerRules';

@Component
export struct MaterialPager {
  @Prop @Watch('cancelTouch') count: number = 0;
  @Prop index: number = 0;
  @Prop label: string = '';
  @Prop rowHeight: number = 38;
  @Prop @Watch('watchAvailability') available: boolean = true;
  onPreview: (position: number) => void = () => {};
  onCommit: (index: number) => void = () => {};
  onCancel: () => void = () => {};
  @State private availableWidth: number = 0;
  @State private pressed: boolean = false;
  @State private dragPosition: number = -1;
  private windowLeft: number = 0;
  private touchId: number = -1;
  private holdTimer: number = -1;
  private startX: number = 0;
  private startY: number = 0;
  private startIndex: number = 0;
  private readonly haptics: SelectionHaptics = new SelectionHaptics();

  aboutToAppear(): void { this.haptics.prepare('material pager'); }

  aboutToDisappear(): void { this.cancelTouch(); }

  private watchAvailability(): void { if (!this.available) this.cancelTouch(); }

  private dots(): number[] {
    const first = this.firstDot();
    const pages: number[] = [];
    for (let slot = 0; slot < this.visibleDotCount(); slot++) pages.push(first + slot);
    return pages;
  }

  private visibleDotCount(): number { return Math.min(this.count, MATERIAL_PAGER_VISIBLE_DOTS); }

  private firstDot(): number { return materialDotWindowStart(this.count, this.index); }

  private dotX(page: number): number {
    return materialDotX(page, this.count, this.index, this.compactWidth());
  }

  private dotSize(page: number): number {
    return materialDotSize(page, this.firstDot(), this.visibleDotCount(), this.count);
  }

  private currentIndex(): number { return this.dragPosition >= 0 ? Math.round(this.dragPosition) : this.index; }

  private compactWidth(): number {
    return this.availableWidth ? Math.min(this.availableWidth, materialPagerWidth(this.count)) :
      materialPagerWidth(this.count);
  }

  private expandedWidth(): number { return materialExpandedPagerWidth(this.availableWidth); }

  private trackWidth(): number { return Math.max(0, this.expandedWidth() - 2 * MATERIAL_PAGER_INSET); }

  private dragThumbX(): number {
    const position = this.dragPosition >= 0 ? this.dragPosition : this.index;
    return MATERIAL_PAGER_INSET + position * this.trackWidth() / Math.max(1, this.count - 1);
  }

  private drag(windowX: number): void {
    const position = materialExpandedPagePosition(windowX - this.windowLeft, this.startX - this.windowLeft,
      this.startIndex, this.availableWidth, this.count);
    const index = Math.round(position);
    if (index !== this.currentIndex()) this.haptics.pulse('material pager', index, 'indicator-point');
    this.dragPosition = position;
    this.onPreview(position);
  }

  private choose(index: number): void {
    if (index === this.currentIndex() || index < 0 || index >= this.count) return;
    this.haptics.pulse('material pager', index, 'indicator-point');
    this.onCommit(index);
  }

  private setPressed(pressed: boolean): void {
    if (pressed === this.pressed) return;
    this.getUIContext().animateTo({duration: 245, curve: Curve.EaseOut}, () => { this.pressed = pressed; });
  }

  private cancelTouch(): void {
    if (this.touchId < 0) return;
    this.clearHoldTimer();
    this.touchId = -1;
    const wasDragging = this.dragPosition >= 0;
    this.dragPosition = -1;
    this.setPressed(false);
    if (wasDragging) this.onCancel();
  }

  private clearHoldTimer(): void {
    if (this.holdTimer >= 0) clearTimeout(this.holdTimer);
    this.holdTimer = -1;
  }

  private handleTouch(event: TouchEvent): void {
    if (event.type === TouchType.Cancel) {
      this.cancelTouch();
      return;
    }
    if (event.type === TouchType.Down && this.touchId < 0) {
      if (!this.available || this.count <= 1 || !event.changedTouches.length) return;
      const touch = event.changedTouches[0];
      this.touchId = touch.id;
      this.startX = touch.windowX;
      this.startY = touch.windowY;
      this.startIndex = this.index;
      this.holdTimer = setTimeout(() => {
        this.holdTimer = -1;
        this.setPressed(true);
      }, 120);
      return;
    }
    if (this.touchId < 0) return;
    const touch = event.changedTouches.find((point: TouchObject) => point.id === this.touchId);
    if (!touch) return;
    if (event.type === TouchType.Move) {
      const dx = Math.abs(touch.windowX - this.startX);
      const dy = Math.abs(touch.windowY - this.startY);
      if (this.dragPosition < 0 && dy > 9 && dy > dx) this.cancelTouch();
      else if (this.dragPosition >= 0 || dx >= 4) {
        this.clearHoldTimer();
        this.setPressed(true);
        this.drag(touch.windowX);
      }
    } else if (event.type === TouchType.Up) {
      this.clearHoldTimer();
      if (this.dragPosition >= 0) this.drag(touch.windowX);
      const selected = Math.round(this.dragPosition);
      const tapped = !this.pressed;
      this.touchId = -1;
      this.dragPosition = -1;
      this.setPressed(false);
      if (selected >= 0) this.onCommit(selected);
      else if (tapped) {
        const left = this.windowLeft + (this.availableWidth - this.compactWidth()) / 2;
        this.choose(materialDotPageAt(touch.windowX - left, this.compactWidth(), this.count, this.index));
      }
    }
  }

  build() {
    Stack() {
      Stack() {
        Stack({alignContent: Alignment.Start}) {
          Rect().width('100%').height(26).radius(13).fill('#09D9BB9D').opacity(this.pressed ? 1 : 0)
          Stack({alignContent: Alignment.Start}) {
            Rect().width(this.trackWidth()).height(2).radius(1).fill('#554D46')
              .translate({x: MATERIAL_PAGER_INSET})
            Rect().width(Math.max(0, this.dragThumbX() - MATERIAL_PAGER_INSET)).height(2).radius(1)
              .fill('#8C7259').translate({x: MATERIAL_PAGER_INSET})
          }.width(this.expandedWidth()).height(26).opacity(this.pressed ? 1 : 0)
          Stack({alignContent: Alignment.Start}) {
            ForEach(this.dots(), (page: number) => {
              Rect().width(page === this.index ? MATERIAL_PAGER_ACTIVE_WIDTH : this.dotSize(page))
                .height(page === this.index ? 6 : this.dotSize(page)).radius(3)
                .fill('#7F7F7D').opacity(page === this.index ? 0 : 1)
                .translate({x: this.dotX(page) -
                  (page === this.index ? MATERIAL_PAGER_ACTIVE_WIDTH : this.dotSize(page)) / 2})
                .animation({duration: 140, curve: Curve.EaseOut})
            }, (page: number) => page.toString())
          }.width(this.compactWidth()).height(26).opacity(this.pressed ? 0 : 1)
          Circle().width(14).height(14).fill('#251E1A').stroke('#40F2BF79').strokeWidth(1)
            .translate({x: this.dragThumbX() - 7}).opacity(this.pressed ? 1 : 0)
          Rect().width(this.pressed ? 10 : MATERIAL_PAGER_ACTIVE_WIDTH).height(this.pressed ? 10 : 6)
            .radius(5).fill('#EFBD70')
            .translate({x: this.pressed ? this.dragThumbX() - 5 :
              this.dotX(this.index) - MATERIAL_PAGER_ACTIVE_WIDTH / 2})
        }.width('100%').height(26).borderRadius(13).clip(true).hitTestBehavior(HitTestMode.None)
          .accessibilityLevel('no-hide-descendants')
      }.width(this.pressed ? this.expandedWidth() : this.compactWidth()).height(this.rowHeight)
        .id('material-pager')
        .accessibilityRole(AccessibilityRoleType.SLIDER)
        .accessibilityText('款式分页，' + this.label + '，' + (this.currentIndex() + 1) + ' / ' + this.count)
        .focusable(true).enabled(this.available && this.count > 1)
        .onTouch((event: TouchEvent) => this.handleTouch(event))
        .onKeyEvent((event: KeyEvent) => {
          if (event.type !== KeyType.Down) return;
          if (event.keyCode === KeyCode.KEYCODE_DPAD_LEFT) this.choose(this.currentIndex() - 1);
          if (event.keyCode === KeyCode.KEYCODE_DPAD_RIGHT) this.choose(this.currentIndex() + 1);
        })
    }.width('100%').height(this.rowHeight).onAreaChange((_old: Area, area: Area) => {
      this.availableWidth = Number(area.width);
      this.windowLeft = Number(area.globalPosition.x);
    })
  }
}
