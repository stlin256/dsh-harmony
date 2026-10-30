import { NativeMessage } from '../services/NativeSessionModel';
import { nativeActivity, nativeToolArgumentsVisible, nativeToolDetail, nativeToolCategory,
  nativeProcessIcon, nativeToolOutputVisible } from '../services/NativeTranscript';
import { NativeTextContent } from './NativeTextContent';
import { DSHIcon } from './DSHIcon';
import { NativeHarnessClient } from '../services/NativeHarnessClient';
import { NativeImageStrip } from './NativeImageStrip';
import { NativeRichContent } from './NativeRichContent';
import { NativeDiffBlock } from './NativeDiffBlock';
import { NativeDiffDocument, nativeDiff } from '../services/NativeDiff';
import { NativeMotion } from '../services/NativeMotion';

@Component
export struct NativeToolCallView {
  client: NativeHarnessClient = new NativeHarnessClient('');
  sessionId: string = '';
  disclosures: Map<string, boolean> = new Map<string, boolean>();
  @Prop @Watch('changed') message: NativeMessage = new NativeMessage();
  @Prop depth: number = 0;
  @Prop hideHeader: boolean = false;
  @Prop forceExpanded: boolean = false;
  @Prop maxExpandedHeight: number = 240;
  @StorageLink('nativeDark') private dark: boolean = false;
  @State private expanded: boolean = false;
  @State private diff: NativeDiffDocument = new NativeDiffDocument();
  @State private detail: string = '';
  aboutToAppear(): void {
    const saved = this.disclosures.get(this.message.turnKey + '|' + this.message.id);
    this.expanded = this.forceExpanded || saved === true;
    this.changed();
  }
  private changed(): void { this.diff = nativeDiff(this.message); this.detail = nativeToolDetail(this.message); }
  private toggle(): void {
    if (this.message.phase === 'preparing') return;
    this.expanded = !this.expanded;
    this.disclosures.set(this.message.turnKey + '|' + this.message.id, this.expanded);
  }
  build() {
    Column({ space: 4 }) {
      if (!this.hideHeader) {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 6 }) {
            DSHIcon({ glyph: nativeProcessIcon(nativeToolCategory(this.message.toolName)),
              color: this.dark ? '#93969B' : '#8A8D91', glyphSize: 14 })
            Text(nativeActivity(nativeToolCategory(this.message.toolName),
              this.message.status === 'running' || this.message.status === 'preparing'))
              .fontSize(12).fontWeight(FontWeight.Medium)
              .fontColor(this.dark ? '#CFD3D6' : '#61666B').maxLines(1)
            if (this.detail) {
              Text('·').fontSize(12).fontColor(this.dark ? '#777A80' : '#A1A4A9')
              Text(this.detail).fontSize(12).layoutWeight(1).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor(this.dark ? '#93969B' : '#8A8D91')
                .opacity(this.expanded ? 0 : 1).translate({ x: this.expanded ? 4 : 0 })
            } else {
              Blank().layoutWeight(1)
            }
            if (this.diff.matched && (this.diff.added > 0 || this.diff.removed > 0)) {
              Text('+' + this.diff.added).fontSize(10).fontWeight(FontWeight.Medium)
                .fontColor(this.dark ? '#9BE2B0' : '#187940')
              Text('-' + this.diff.removed).fontSize(10).fontWeight(FontWeight.Medium)
                .fontColor(this.dark ? '#FFB1B1' : '#B3261E')
            }
            if (this.message.status === 'error' || this.message.status === 'interrupted') {
              Text(this.message.status === 'error' ? '失败' : '已中断').fontSize(10)
                .fontColor(this.message.status === 'error' ? '#D55E5E' : '#A56A00')
            }
            if (this.message.phase !== 'preparing') {
              DSHIcon({ glyph: 'chevron-left-outline', color: this.dark ? '#93969B' : '#8A8D91', glyphSize: 12 })
                .rotate({ angle: this.expanded ? -90 : 180 })
            }
          }.width('100%')
        }.height(30).width('100%').padding({ left: 2, right: 2 }).backgroundColor(Color.Transparent)
          .onClick(() => { this.toggle(); })
      }
      if (this.forceExpanded || this.expanded) {
        Scroll() {
          Column({ space: 6 }) {
            if (this.diff.matched) {
              NativeDiffBlock({ document: this.diff })
            } else if (this.message.args && nativeToolArgumentsVisible(this.message)) {
              NativeTextContent({ text: this.message.args, monospace: true, client: this.client, sessionId: this.sessionId })
            }
            if (this.message.images.length) {
              NativeImageStrip({
                client: this.client,
                sessionId: this.sessionId,
                attachments: this.message.images
              })
            }
            if (!this.diff.matched && this.message.output && nativeToolOutputVisible(this.message)) {
              Divider().color(this.dark ? '#3B3B3E' : '#E4E5E8')
              if (this.message.blocks.length) {
                NativeRichContent({
                  blocks: this.message.blocks,
                  client: this.client,
                  sessionId: this.sessionId
                })
              } else {
                NativeTextContent({ text: this.message.output, client: this.client, sessionId: this.sessionId })
              }
            }
            if (this.message.error) { Text(this.message.error).fontSize(12).fontColor('#D55E5E') }
            if (this.message.status === 'interrupted') {
              Text('已中断').fontSize(11).fontColor(this.dark ? '#93969B' : '#8A8D91')
            }
            ForEach(this.message.children, (child: NativeMessage) => {
              NativeNestedToolRow({ client: this.client, sessionId: this.sessionId, message: child,
                maxExpandedHeight: this.maxExpandedHeight })
            }, (child: NativeMessage) => child.id)
          }.padding({ left: 8, right: 16, top: 8, bottom: 8 }).width('100%')
            .alignItems(HorizontalAlign.Start).borderRadius(8)
            .backgroundColor(this.dark ? '#232324' : '#F5F6F7')
        }.width('100%').constraintSize({ maxHeight: Math.max(96, this.maxExpandedHeight) })
          .scrollable(ScrollDirection.Vertical).scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.None)
          .transition(NativeMotion.rowTransition())
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

/** Non-recursive summary for nested PTC actions. */
@Component
struct NativeNestedToolRow {
  client: NativeHarnessClient = new NativeHarnessClient('');
  sessionId: string = '';
  @Prop message: NativeMessage = new NativeMessage();
  @Prop maxExpandedHeight: number = 240;
  @StorageLink('nativeDark') private dark: boolean = false;
  @State private expanded: boolean = false;

  private preview(): string { return nativeToolDetail(this.message); }
  private toggle(): void {
    NativeMotion.animate(this.getUIContext(), 'micro', (): void => { this.expanded = !this.expanded; });
  }

  build() {
    Column({ space: this.expanded ? 4 : 0 }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 6 }) {
          DSHIcon({ glyph: nativeProcessIcon(nativeToolCategory(this.message.toolName)),
            color: this.dark ? '#93969B' : '#8A8D91', glyphSize: 13 })
          Text(nativeActivity(nativeToolCategory(this.message.toolName),
            this.message.status === 'running' || this.message.status === 'preparing'))
            .fontSize(11).fontColor(this.dark ? '#CFD3D6' : '#61666B')
          if (this.preview()) {
            Text('·').fontSize(11).fontColor(this.dark ? '#777A80' : '#A1A4A9')
            Text(this.preview()).fontSize(11).layoutWeight(1).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontColor(this.dark ? '#93969B' : '#8A8D91')
              .opacity(this.expanded ? 0 : 1)
          } else {
            Blank().layoutWeight(1)
          }
          DSHIcon({ glyph: 'chevron-left-outline',
            color: this.dark ? '#93969B' : '#8A8D91', glyphSize: 11 })
            .rotate({ angle: this.expanded ? -90 : 180 })
        }.width('100%')
      }.height(28).width('100%').padding({ left: 2, right: 2 })
        .backgroundColor(Color.Transparent).onClick((): void => { this.toggle(); })
      if (this.expanded) {
        Scroll() {
          Column({ space: 5 }) {
            if (this.message.args && nativeToolArgumentsVisible(this.message)) {
              NativeTextContent({ text: this.message.args, monospace: true,
                client: this.client, sessionId: this.sessionId })
            }
            if (this.message.images.length) {
              NativeImageStrip({
                client: this.client,
                sessionId: this.sessionId,
                attachments: this.message.images
              })
            }
            if (this.message.output && nativeToolOutputVisible(this.message)) {
              if (this.message.blocks.length) {
                NativeRichContent({
                  blocks: this.message.blocks,
                  client: this.client,
                  sessionId: this.sessionId
                })
              } else {
                NativeTextContent({ text: this.message.output,
                  client: this.client, sessionId: this.sessionId })
              }
            }
          }.width('100%').padding({ right: 10 }).alignItems(HorizontalAlign.Start)
        }.width('100%').constraintSize({ maxHeight: Math.max(80, this.maxExpandedHeight * 0.7) })
          .scrollable(ScrollDirection.Vertical).edgeEffect(EdgeEffect.None)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
