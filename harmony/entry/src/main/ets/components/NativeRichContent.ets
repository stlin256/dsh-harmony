import { NativeHarnessClient } from '../services/NativeHarnessClient';
import { NativeTextBlock } from '../services/NativeSessionModel';
import { NativeCodeBlock } from './NativeCodeBlock';
import { NativeInlineText } from './NativeInlineText';
import { NativeTextContent } from './NativeTextContent';

/** Block-level Markdown surface shared by messages and expanded tool results. */
@Component
export struct NativeRichContent {
  client: NativeHarnessClient = new NativeHarnessClient('');
  sessionId: string = '';
  @Prop blocks: NativeTextBlock[] = [];
  @StorageLink('nativeDark') private dark: boolean = false;

  build() {
    Column({ space: 9 }) {
      ForEach(this.blocks, (block: NativeTextBlock) => {
        if (block.kind === 'code') {
          NativeCodeBlock({ code: block.text, language: block.language })
        } else if (block.kind === 'heading') {
          NativeInlineText({
            text: block.text,
            textSize: 17,
            lineHeight: '27fp',
            baseWeight: FontWeight.Medium,
            client: this.client,
            sessionId: this.sessionId
          })
        } else if (block.kind === 'quote') {
          Column() {
            NativeInlineText({
              text: block.text,
              textSize: 13,
              lineHeight: '21fp',
              muted: true,
              client: this.client,
              sessionId: this.sessionId
            })
          }
          .width('100%')
          .padding({ left: 11, right: 9, top: 8, bottom: 8 })
          .borderRadius(9)
          .backgroundColor(this.dark ? '#2A2B2F' : '#EEF1F5')
          .border({ width: { left: 2 }, color: this.dark ? '#5E88D8' : '#3964FE' })
        } else {
          NativeTextContent({
            text: block.text,
            client: this.client,
            sessionId: this.sessionId
          })
        }
      }, (_block: NativeTextBlock, index: number) => index.toString())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
