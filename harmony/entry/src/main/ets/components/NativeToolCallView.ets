import { NativeMessage } from '../services/NativeSessionModel';
import { nativeToolDetail, nativeToolCategory, nativeProcessIcon } from '../services/NativeTranscript';
import { NativeExperience } from '../services/NativeExperience';
import { NativeTextContent } from './NativeTextContent';
import { DSHIcon } from './DSHIcon';
import { NativeHarnessClient } from '../services/NativeHarnessClient';
import { NativeImageView } from './NativeImageView';
import { NativeImageAttachment } from '../services/NativeSessionModel';
import { NativeDiffBlock } from './NativeDiffBlock';
import { NativeDiffDocument, nativeDiff } from '../services/NativeDiff';

@Component
export struct NativeToolCallView {
  client: NativeHarnessClient = new NativeHarnessClient('');
  sessionId: string = '';
  disclosures: Map<string, boolean> = new Map<string, boolean>();
  @Prop @Watch('changed') message: NativeMessage = new NativeMessage();
  @Prop depth: number = 0;
  @StorageLink('nativeDark') private dark: boolean = false;
  @State private expanded: boolean = false;
  @State private diff: NativeDiffDocument = new NativeDiffDocument();
  aboutToAppear(): void {
    const saved = this.disclosures.get(this.message.turnKey + '|' + this.message.id);
    this.expanded = saved === undefined ? true : saved;
    this.changed();
  }
  private changed(): void { this.diff = nativeDiff(this.message); }
  private toggle(): void {
    if (this.message.phase === 'preparing') return;
    const update = (): void => { this.expanded = !this.expanded; this.disclosures.set(this.message.turnKey + '|' + this.message.id, this.expanded); };
    if (NativeExperience.reducedMotion()) update();
    else this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseInOut }, update);
  }
  build() {
    Column({ space: 4 }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 6 }) {
          DSHIcon({ glyph: nativeProcessIcon(nativeToolCategory(this.message.toolName)),
            color: this.dark ? '#93969B' : '#8A8D91', glyphSize: 14 })
          Text(this.message.toolName || this.message.label || '工具').fontSize(12).fontWeight(FontWeight.Medium)
            .fontColor(this.dark ? '#CFD3D6' : '#61666B').maxLines(1)
          Text(nativeToolDetail(this.message)).fontSize(12).layoutWeight(1).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor(this.dark ? '#93969B' : '#8A8D91')
          if (this.message.status === 'error' || this.message.status === 'interrupted') {
            Text(this.message.status === 'error' ? '失败' : '已中断').fontSize(10).fontColor(this.message.status === 'error' ? '#D55E5E' : '#A56A00')
          }
          if (this.message.phase !== 'preparing') {
            DSHIcon({ glyph: 'chevron-left-outline', color: this.dark ? '#93969B' : '#8A8D91', glyphSize: 12 })
              .rotate({ angle: this.expanded ? -90 : 180 })
          }
        }.width('100%')
      }.height(30).width('100%').padding({ left: 2, right: 2 }).backgroundColor(Color.Transparent)
        .onClick(() => { this.toggle(); })
      if (this.expanded) {
        Column({ space: 6 }) {
          if (this.diff.matched) {
            NativeDiffBlock({ document: this.diff })
          } else if (this.message.args) {
            NativeTextContent({ text: this.message.args, monospace: true, client: this.client, sessionId: this.sessionId })
          }
          if (!this.diff.matched && this.message.output) {
            Divider().color(this.dark ? '#3B3B3E' : '#E4E5E8')
            NativeTextContent({ text: this.message.output, client: this.client, sessionId: this.sessionId })
          }
          ForEach(this.message.images, (attachment: NativeImageAttachment) => {
            NativeImageView({ client: this.client, sessionId: this.sessionId, attachment })
          }, (attachment: NativeImageAttachment) => attachment.attachmentId)
          if (this.message.error) { Text(this.message.error).fontSize(12).fontColor('#D55E5E') }
          if (this.message.status === 'interrupted') { Text('已中断').fontSize(11).fontColor(this.dark ? '#93969B' : '#8A8D91') }
            ForEach(this.message.children, (child: NativeMessage) => {
              NativeToolCallView({ client: this.client, sessionId: this.sessionId, message: child, depth: this.depth + 1, disclosures: this.disclosures })
            }, (child: NativeMessage) => child.id)
        }.padding(8).width('100%').alignItems(HorizontalAlign.Start).borderRadius(8)
          .backgroundColor(this.dark ? '#232324' : '#F5F6F7')
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
