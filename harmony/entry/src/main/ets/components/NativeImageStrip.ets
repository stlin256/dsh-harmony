import { NativeHarnessClient } from '../services/NativeHarnessClient';
import { NativeImageAttachment } from '../services/NativeSessionModel';
import { NativeImageView } from './NativeImageView';

/** Compact attachment row used by process operations that return images. */
@Component
export struct NativeImageStrip {
  client: NativeHarnessClient = new NativeHarnessClient('');
  sessionId: string = '';
  @Prop attachments: NativeImageAttachment[] = [];
  @Prop thumbnailSize: number = 84;
  @Prop trailingInset: number = 12;

  build() {
    Flex({
      direction: FlexDirection.Row,
      wrap: FlexWrap.Wrap,
      justifyContent: FlexAlign.Start,
      alignItems: ItemAlign.Start
    }) {
      ForEach(this.attachments, (attachment: NativeImageAttachment) => {
        NativeImageView({
          client: this.client,
          sessionId: this.sessionId,
          attachment,
          compact: true,
          compactSize: this.thumbnailSize
        })
      }, (attachment: NativeImageAttachment) => attachment.attachmentId)
    }
    .width('100%')
    .padding({ left: 1, right: this.trailingInset, top: 1, bottom: 1 })
  }
}
