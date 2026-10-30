import { pasteboard } from '@kit.BasicServicesKit';
import { NativeTextContent } from './NativeTextContent';
import { DSHIcon } from './DSHIcon';
import { NativeHarnessClient } from '../services/NativeHarnessClient';
import { NativeImageView } from './NativeImageView';
import { NativeExperience } from '../services/NativeExperience';
import { nativeReasoningPreview } from '../services/NativeTranscript';
import { NativeMessage, NativeTextBlock, NativeImageAttachment } from '../services/NativeSessionModel';

@Component
export struct NativeMessageView {
  client: NativeHarnessClient = new NativeHarnessClient('');
  sessionId: string = '';
  disclosures: Map<string, boolean> = new Map<string, boolean>();
  @Prop preview: boolean = true;
  @Prop runningReasoning: boolean = false;
  onCompatibility: () => void = (): void => {};
  @Prop message: NativeMessage = new NativeMessage();
  @StorageLink('nativeDark') private dark: boolean = false;
  @State private reasoningOpen: boolean = false;
  @State private toolOpen: boolean = false;
  @State private copied: boolean = false;
  aboutToAppear(): void { this.reasoningOpen = this.disclosures.get(this.message.turnKey + '|' + this.message.id) === true; }

  private copyMessage(): void {
    const text = this.message.text || this.message.blocks.map((block: NativeTextBlock) => block.text).join('\n');
    if (!text) return;
    pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text))
      .then(() => { this.copied = true; }).catch(() => { this.copied = false; });
  }

  private animate(action: () => void): void {
    if (NativeExperience.reducedMotion()) action();
    else this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseInOut }, action);
  }

  build() {
    Column({ space: 6 }) {
      if (this.message.role !== 'user' && this.message.role !== 'assistant' && this.message.role !== 'tool' && this.message.role !== 'reasoning') {
        Text(this.message.label).fontSize(12).fontWeight(FontWeight.Medium)
          .fontColor(this.dark ? '#CFD3D6' : '#61666B')
      }
      if (this.message.reasoning) {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 6 }) {
            DSHIcon({ glyph: 'chevron-left-outline', color: this.dark ? '#93969B' : '#8A8D91', glyphSize: 12 })
              .rotate({ angle: this.reasoningOpen ? -90 : 180 })
            Text('思考过程').fontSize(12)
            if (!this.reasoningOpen && this.preview) {
              Text(nativeReasoningPreview(this.message.reasoning, this.runningReasoning)).fontSize(12).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            }
          }.width('100%')
        }.width('100%').height(28).padding(0).fontSize(12).borderRadius(8)
          .backgroundColor(Color.Transparent).fontColor(this.dark ? '#CFD3D6' : '#61666B')
          .onClick(() => { this.animate(() => { this.reasoningOpen = !this.reasoningOpen;
            this.disclosures.set(this.message.turnKey + '|' + this.message.id, this.reasoningOpen); }); })
        if (this.reasoningOpen) {
          NativeTextContent({ text: this.message.reasoning, client: this.client, sessionId: this.sessionId })
        }
      }
      if (this.message.role === 'tool') {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 6 }) {
            DSHIcon({ glyph: 'chevron-left-outline', color: this.dark ? '#93969B' : '#8A8D91', glyphSize: 12 })
              .rotate({ angle: this.toolOpen ? -90 : 180 })
            Text(this.message.label).fontSize(12).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }.height(30).fontSize(12).borderRadius(8).backgroundColor(Color.Transparent)
          .fontColor(this.dark ? '#CFD3D6' : '#61666B')
          .onClick(() => { this.animate(() => { this.toolOpen = !this.toolOpen; }); })
      }
      if (this.message.role !== 'tool' || this.toolOpen) {
        if (!this.message.blocks.length && this.message.text) { NativeTextContent({ text: this.message.text, client: this.client, sessionId: this.sessionId }) }
        ForEach(this.message.blocks, (block: NativeTextBlock) => {
          if (block.kind === 'code') {
            Column({ space: 8 }) {
              Text(block.language || '代码').fontSize(11).fontColor(this.dark ? '#CFD3D6' : '#61666B')
              NativeTextContent({ text: block.text, monospace: true, client: this.client, sessionId: this.sessionId })
            }.padding(10).width('100%').alignItems(HorizontalAlign.Start)
              .borderRadius(12).backgroundColor(this.dark ? '#353638' : '#F5F6F7')
          } else if (block.kind === 'heading') {
            Text(block.text).fontSize(18).lineHeight('28fp').fontWeight(FontWeight.Medium)
              .copyOption(CopyOptions.InApp).fontColor(this.dark ? '#F9FAFB' : '#0F1115')
          } else if (block.kind === 'quote') {
            Text(block.text).fontSize(13).lineHeight('22fp').padding(12).borderRadius(12)
              .backgroundColor(this.dark ? '#353638' : '#F5F6F7')
              .copyOption(CopyOptions.InApp).fontColor(this.dark ? '#CFD3D6' : '#61666B')
          } else {
            NativeTextContent({ text: block.text, client: this.client, sessionId: this.sessionId })
          }
        }, (_block: NativeTextBlock, index: number) => index.toString())
      }
      ForEach(this.message.images || [], (attachment: NativeImageAttachment) => {
        NativeImageView({ client: this.client, sessionId: this.sessionId, attachment })
      }, (attachment: NativeImageAttachment) => attachment.attachmentId)
      if (this.message.role === 'notice') {
        Button('打开完整交互', { type: ButtonType.Normal }).height(36).fontSize(12).borderRadius(10)
          .backgroundColor(this.dark ? '#353638' : '#F5F6F7').fontColor(this.dark ? '#F9FAFB' : '#0F1115')
          .onClick(this.onCompatibility)
      }
      if (!this.message.text && !this.message.reasoning) {
        Text('此消息包含高级内容，请在兼容模式查看。').fontSize(13)
          .fontColor(this.dark ? '#CFD3D6' : '#61666B')
      }
      if ((this.message.role === 'user' || this.message.role === 'assistant') && this.message.text) {
        Row() {
          Blank()
          Button({ type: ButtonType.Normal }) {
            DSHIcon({ glyph: this.copied ? 'check-outline' : 'copy-outline', color: this.dark ? '#93969B' : '#8A8D91', glyphSize: 14 })
          }.width(28).height(28).borderRadius(14).backgroundColor(Color.Transparent)
            .accessibilityText(this.copied ? '已复制' : '复制消息').onClick(() => { this.copyMessage(); })
        }.width('100%')
      }
    }.alignItems(HorizontalAlign.Start).width(this.message.role === 'user' ? '82%' : '100%')
      .padding(this.message.role === 'user' || this.message.role === 'tool' ? 10 : this.message.role === 'reasoning' ? 0 : 2)
      .backgroundColor(this.message.role === 'user' || this.message.role === 'tool' ? this.dark ? '#2C2C2E' : '#F5F6F7' : Color.Transparent)
      .borderRadius(16)
  }
}
