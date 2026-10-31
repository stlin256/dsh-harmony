import { DSHIcon } from './DSHIcon';
import { NativeMotion } from '../services/NativeMotion';
import { NativePlanDocument, nativePlanProgress } from '../services/NativePlan';
import { NativePlanView } from './NativePlanView';

/** Floating current-plan control anchored below the conversation title. */
@Component
export struct NativeTaskDock {
  @Prop @Watch('sessionChanged') document: NativePlanDocument = new NativePlanDocument();
  @Prop @Watch('sessionChanged') sessionId: string = '';
  @StorageLink('nativeDark') private dark: boolean = false;
  @State private expanded: boolean = false;
  private currentSession: string = '';

  aboutToAppear(): void {
    this.currentSession = this.sessionId;
  }

  private sessionChanged(): void {
    if (this.currentSession === this.sessionId) return;
    this.currentSession = this.sessionId;
    this.expanded = false;
  }

  private toggle(): void {
    NativeMotion.animate(this.getUIContext(), 'surface', (): void => {
      this.expanded = !this.expanded;
    });
  }

  private surfaceColor(): string {
    return this.dark ? '#242527' : '#FFFFFF';
  }

  build() {
    Column({ space: 0 }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 5 }) {
          DSHIcon({ glyph: 'plan-outline', glyphSize: 14,
            color: this.dark ? '#B7BABE' : '#60656B' })
          Text('任务计划').fontSize(11).fontWeight(FontWeight.Medium)
            .fontColor(this.dark ? '#F0F0F2' : '#202124')
          Text(nativePlanProgress(this.document)).fontSize(10).layoutWeight(1).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor(this.dark ? '#A5A8AC' : '#777B80')
          DSHIcon({ glyph: this.expanded ? 'chevron-up-outline' : 'chevron-down-outline',
            glyphSize: 11, color: this.dark ? '#93969B' : '#777B80' })
        }.width('100%').padding({ left: 10, right: 8 })
      }.height(32).width('100%').padding(0).borderRadius(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText((this.expanded ? '收起' : '展开') + '任务计划')
        .onClick((): void => { this.toggle(); })
      if (this.expanded) {
        Divider().color(this.dark ? '#3A3B3E' : '#E4E5E8')
        Scroll() {
          NativePlanView({ document: this.document, showHeader: false })
            .padding({ left: 10, right: 7, top: 7, bottom: 8 })
        }.width('100%').constraintSize({ maxHeight: 180 })
          .scrollable(ScrollDirection.Vertical).scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.None)
          .transition(NativeMotion.rowTransition())
      }
    }.width('100%').constraintSize({ maxWidth: 620 }).clip(true)
      .borderRadius(this.expanded ? 14 : 16)
      .backgroundColor(this.surfaceColor())
      .border({ width: 0.5, color: this.dark ? '#4A4B4F' : '#D9DBDF' })
      .shadow({ radius: 18, color: this.dark ? '#88000000' : '#26000000',
        offsetX: 0, offsetY: 5 })
      .animation(NativeMotion.implicit('surface'))
  }
}
