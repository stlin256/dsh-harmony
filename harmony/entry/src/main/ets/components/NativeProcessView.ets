import { NativeHarnessClient } from '../services/NativeHarnessClient';
import { NativeMessage } from '../services/NativeSessionModel';
import { NativeExperience } from '../services/NativeExperience';
import { NativeMessageView } from './NativeMessageView';
import { NativeToolCallView } from './NativeToolCallView';
import { DSHIcon } from './DSHIcon';
import { nativeProcessIcon } from '../services/NativeTranscript';

@Component
export struct NativeProcessView {
  client: NativeHarnessClient = new NativeHarnessClient('');
  sessionId: string = '';
  disclosures: Map<string, boolean> = new Map<string, boolean>();
  maxGroupHeight: number = 400;
  @Prop @Watch('changed') message: NativeMessage = new NativeMessage();
  @StorageLink('nativeDark') private dark: boolean = false;
  @State private expanded: boolean = false;
  @State private headline: string = '';
  private titleTimer: number = -1;
  private shownAt: number = 0;
  private groupScroller: Scroller = new Scroller();
  private follow: boolean = false;
  aboutToAppear(): void { this.expanded = this.disclosures.get(this.message.turnKey + '|' + this.message.id) === true; this.changed(); }
  aboutToDisappear(): void { clearTimeout(this.titleTimer); }
  private changed(): void {
    clearTimeout(this.titleTimer);
    const remaining = 150 - (Date.now() - this.shownAt);
    const update = (): void => { this.headline = this.message.label; this.shownAt = Date.now(); };
    if (this.message.closed || remaining <= 0 || !this.headline) update();
    else this.titleTimer = setTimeout(update, remaining);
    if (!this.message.closed && this.expanded && this.follow && !this.message.flat) setTimeout(() => { this.groupScroller.scrollEdge(Edge.Bottom); }, 0);
  }
  private toggle(): void {
    const update = (): void => { this.expanded = !this.expanded; this.disclosures.set(this.message.turnKey + '|' + this.message.id, this.expanded);
      if (this.expanded) { this.follow = !this.message.closed; if (this.follow) setTimeout(() => { this.groupScroller.scrollEdge(Edge.Bottom); }, 0); } };
    if (NativeExperience.reducedMotion()) update();
    else this.getUIContext().animateTo({ duration: 110, curve: Curve.EaseInOut }, update);
  }
  @Builder
  private members() {
    Column({ space: 4 }) {
      ForEach(this.message.children, (child: NativeMessage) => {
        if (child.role === 'tool') { NativeToolCallView({ client: this.client, sessionId: this.sessionId, message: child, disclosures: this.disclosures }) }
        else if (child.role === 'reasoning') { NativeMessageView({ client: this.client, sessionId: this.sessionId, message: child,
          preview: this.message.preview, runningReasoning: !this.message.closed, disclosures: this.disclosures }) }
        else { Text(child.label).fontSize(12).fontColor(this.dark ? '#93969B' : '#8A8D91') }
      }, (child: NativeMessage) => child.id)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  build() {
    Column({ space: this.expanded && !this.message.flat ? 8 : 0 }) {
      if (!this.message.flat) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 6 }) {
          DSHIcon({ glyph: nativeProcessIcon(this.message.toolName), color: this.dark ? '#93969B' : '#8A8D91', glyphSize: 14 })
          Text(this.headline).fontSize(12).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor(this.dark ? '#CFD3D6' : '#61666B')
          DSHIcon({ glyph: 'chevron-left-outline', color: this.dark ? '#93969B' : '#8A8D91', glyphSize: 12 })
            .rotate({ angle: this.expanded ? -90 : 180 })
        }.width('100%')
      }.height(30).width('100%').padding({ left: 2, right: 2 }).backgroundColor(Color.Transparent)
        .onClick(() => { this.toggle(); })
      }
      if (this.message.flat) { this.members() }
      else if (this.expanded) {
        Scroll(this.groupScroller) { this.members() }.width('100%').constraintSize({ maxHeight: this.maxGroupHeight })
          .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
          .edgeEffect(NativeExperience.reducedMotion() ? EdgeEffect.None : EdgeEffect.Spring)
          .onScroll(() => { this.follow = this.groupScroller.isAtEnd(); })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
