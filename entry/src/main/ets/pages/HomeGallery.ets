import { curves } from '@kit.ArkUI';
import { vibrator } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppLog } from '../common/AppLog';

export interface HomeRecipe {
  id: string;
  image: string;
  imageRatio: number;
  imageDescription: string;
  film: string;
  paper: string;
  filmName: string;
  paperName: string;
  filmHistory: string;
  paperHistory: string;
}

export const HOME_RECIPES: HomeRecipe[] = [{
  id: 'ektar-vision-premier', image: 'home/ektar-100-vision-2393.jpg',
  imageRatio: 3016 / 2008, imageDescription: '蓝色玻璃与石雕拱窗',
  film: 'kodak_ektar_100', paper: 'kodak_2393',
  filmName: 'Kodak Ektar 100', paperName: 'Vision Premier 2393',
  filmHistory: '2008 年推出的 Ektar 100，将柯达电影胶片技术带入静态摄影，以细腻颗粒和鲜明色彩记录风光。',
  paperHistory: 'Vision Premier 2393 于 1998 年问世，是用于制作影院放映拷贝的彩色印片，延续了电影的光化学传统。'
}, {
  id: 'gold-portra-endura', image: 'home/gold-200-portra-endura.jpg',
  imageRatio: 4608 / 3456, imageDescription: '海边的面包铺与彩色木屋',
  film: 'kodak_gold_200', paper: 'kodak_portra_endura',
  filmName: 'Kodak Gold 200', paperName: 'Portra Endura',
  filmHistory: 'Gold 200 延续了柯达消费级彩色负片的传统，陪伴人们记录旅行与家庭生活。',
  paperHistory: 'Portra Endura 在 2002 年接替 Portra III，以柔和反差呈现肤色，服务于人像、影楼与婚礼照片冲印。'
}];

@Component
export struct HomeGallery {
  @Prop ready: boolean = false;
  @Link currentIndex: number;
  @State private cardHeight: number = 640;
  onSelect: (recipe: HomeRecipe) => void = () => {};
  @State private cardScales: number[] = [1, 1];
  private feedbackIndex: number = 0;
  private feedbackSource: string = 'none';
  private initialPageIndex: number = 0;
  private indicatorTarget: number = 0;
  private indicatorController: IndicatorComponentController = new IndicatorComponentController();
  private active: boolean = false;
  private softHaptic: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.feedbackIndex = this.currentIndex;
    this.initialPageIndex = this.currentIndex;
    this.indicatorTarget = this.currentIndex;
    vibrator.isSupportEffect(vibrator.HapticFeedback.EFFECT_SOFT).then((supported: boolean) => {
      this.softHaptic = supported;
    }).catch((error: BusinessError) => AppLog.failure('home haptic capability', error));
  }

  aboutToDisappear(): void { this.active = false; }

  private async selectionFeedback(index: number, source: string): Promise<void> {
    if (!this.active || index === this.feedbackIndex) return;
    this.feedbackIndex = index;
    AppLog.record('home selection index=' + index + ' source=' + source);
    try {
      if (this.softHaptic) {
        await vibrator.startVibration({type: 'preset', effectId: vibrator.HapticFeedback.EFFECT_SOFT,
          count: 1}, {usage: 'touch'});
      } else {
        await vibrator.startVibration({type: 'time', duration: 12}, {usage: 'touch'});
      }
      AppLog.record('home selection index=' + index + ' haptic accepted');
    } catch (error) { AppLog.failure('home haptic', error as BusinessError); }
  }

  private scrubIndicator(event: GestureEvent): void {
    if (event.fingerList.length === 0) return;
    const index = Math.max(0, Math.min(HOME_RECIPES.length - 1,
      Math.floor(event.fingerList[0].localX / (80 / HOME_RECIPES.length))));
    this.feedbackSource = 'indicator';
    if (index === this.indicatorTarget) return;
    this.indicatorTarget = index;
    this.selectionFeedback(index, 'indicator-point');
    this.indicatorController.changeIndex(index, true);
  }

  @Builder
  materialImage(id: string) {
    Image($rawfile('materials/' + id + '.webp')).width(92).height(55)
      .objectFit(ImageFit.Contain).borderRadius(6).clip(true)
      .border({width: 1, color: '#62594E', radius: 6}).accessibilityLevel('no')
  }

  @Builder
  materialText(name: string, history: string) {
    Column({space: 8}) {
      Text(name).fontSize(16).fontWeight(FontWeight.Bold).fontColor('#F1EDE7').lineHeight(22)
      Text(history).fontSize(14).lineHeight(22).fontColor('#CBC5BE')
    }.alignItems(HorizontalAlign.Start).layoutWeight(1)
  }

  @Builder
  recipeCard(recipe: HomeRecipe, index: number) {
    Column() {
      Scroll() {
        Column() {
          Stack({alignContent: Alignment.BottomStart}) {
            Image($rawfile(recipe.image)).width('100%').height(Math.max(180, this.cardHeight * 0.38))
              .objectFit(ImageFit.Cover).draggable(false).accessibilityText(recipe.imageDescription)
            Column() {}.width('100%').height(125)
              .linearGradient({angle: 180, colors: [['#00242426', 0], ['#242426', 1]]})
            Column({space: 3}) {
              Text(recipe.filmName).fontSize(29).fontWeight(FontWeight.Bold).fontColor('#F1EDE7')
              Text('× ' + recipe.paperName).fontSize(19).fontWeight(FontWeight.Medium).fontColor('#C8C1B8')
            }.alignItems(HorizontalAlign.Start).padding({left: 18, right: 18, bottom: 12})
          }.width('100%')
          Column({space: 20}) {
            Row({space: 16}) {
              this.materialImage(recipe.film)
              this.materialText(recipe.filmName, recipe.filmHistory)
            }.width('100%').alignItems(VerticalAlign.Center)
            Divider().color('#514D46').strokeWidth(0.5)
            Row({space: 16}) {
              this.materialText(recipe.paperName, recipe.paperHistory)
              this.materialImage(recipe.paper)
            }.width('100%').alignItems(VerticalAlign.Center)
          }.width('100%').padding({left: 18, right: 18, top: 16, bottom: 20})
        }.width('100%').constraintSize({minHeight: Math.max(0, this.cardHeight - 84)})
          .justifyContent(FlexAlign.SpaceBetween)
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
      Button('冲印同款', {type: ButtonType.Normal})
        .fontSize(17).fontWeight(FontWeight.Medium).fontColor('#32271D')
        .height(48).width('calc(100% - 36vp)').borderRadius(10).backgroundColor('#EFBD70')
        .margin({top: 12, bottom: 20}).enabled(this.ready).onClick(() => this.onSelect(recipe))
        .accessibilityText('冲印同款，' + recipe.filmName + '，' + recipe.paperName)
    }.width('100%').height('100%').backgroundColor('#242426').borderRadius(16).clip(true)
      .renderGroup(true).scale({x: this.cardScales[index], y: this.cardScales[index]})
  }

  build() {
    Stack({alignContent: Alignment.Bottom}) {
      Swiper() {
        ForEach(HOME_RECIPES, (recipe: HomeRecipe, index: number) => {
          Stack() { this.recipeCard(recipe, index) }
            .width('100%').height('100%').padding({left: 14, right: 14, top: 12, bottom: 40})
        }, (recipe: HomeRecipe) => recipe.id)
      }.width('100%').height('100%').index(this.initialPageIndex).loop(false).autoPlay(false)
        .itemSpace(8).curve(curves.springMotion(0.55, 0.68)).effectMode(EdgeEffect.Spring)
        .indicator(this.indicatorController)
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) this.feedbackSource = 'card';
        })
        .onChange((index: number) => {
          this.currentIndex = index;
          if (this.feedbackSource !== 'indicator') this.indicatorTarget = index;
        })
        .onContentDidScroll((_selected: number, index: number, position: number, length: number) => {
          const scale = 1 - 0.045 * Math.min(1, Math.abs(position));
          const scales = this.cardScales.slice();
          scales[index] = scale;
          this.cardScales = scales;
          // 卡片边缘首次全部进入视口时反馈，不等待弹簧回弹结束。
          const visibleInset = (length - (length - 28) * scale) / 2;
          if (this.feedbackSource === 'card' && length > 0 && Math.abs(position * length) <= visibleInset) {
            this.selectionFeedback(index, 'card-visible');
          }
        })
        .onAnimationStart((_index: number, target: number) => {
          AppLog.record('home animation started target=' + target);
        })
        .onAnimationEnd((index: number) => { AppLog.record('home animation ended index=' + index); })
        .onAreaChange((_old: Area, area: Area) => { this.cardHeight = Math.max(0, Number(area.height) - 52); })
      IndicatorComponent(this.indicatorController).initialIndex(this.initialPageIndex)
        .count(HOME_RECIPES.length).loop(false).width(80).height(40)
        .style(Indicator.dot().itemWidth(6).itemHeight(6).selectedItemWidth(22).selectedItemHeight(6)
          .color('#65615C').selectedColor('#EFBD70'))
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) this.feedbackSource = 'indicator';
        })
        .priorityGesture(GestureGroup(GestureMode.Exclusive,
          PanGesture({direction: PanDirection.Horizontal, distance: 1})
            .onActionStart((event: GestureEvent) => { this.scrubIndicator(event); })
            .onActionUpdate((event: GestureEvent) => { this.scrubIndicator(event); }),
          TapGesture().onAction((event: GestureEvent) => { this.scrubIndicator(event); })))
    }.width('100%').height('100%')
  }
}
