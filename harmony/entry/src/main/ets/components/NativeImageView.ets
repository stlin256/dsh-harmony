import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { NativeHarnessClient } from '../services/NativeHarnessClient';
import { NativeImageAttachment } from '../services/NativeSessionModel';

class AttachmentResult { data: string = ''; }
@Component
export struct NativeImageView {
  client: NativeHarnessClient = new NativeHarnessClient('');
  sessionId: string = '';
  @Prop attachment: NativeImageAttachment = new NativeImageAttachment();
  @StorageLink('nativeDark') private dark: boolean = false;
  @State private bitmap: image.PixelMap | null = null;
  @State private loading: boolean = false;
  @State private error: string = '';
  @State private preview: boolean = false;
  @State private scale: number = 1;
  private mounted: boolean = false;
  private source: image.ImageSource | null = null;
  aboutToAppear(): void { this.mounted = true; }
  aboutToDisappear(): void {
    this.mounted = false; this.bitmap?.release(); this.source?.release();
    this.bitmap = null; this.source = null;
  }
  private async load(): Promise<void> {
    if (this.loading) return;
    this.loading = true; this.error = '';
    try {
      const response = JSON.parse(await this.client.operation(JSON.stringify({ operation: 'attachment',
        sessionId: this.sessionId, attachment: this.attachment }))) as AttachmentResult;
      if (!this.mounted) return;
      const bytes = new util.Base64Helper().decodeSync(response.data);
      const source = image.createImageSource(bytes.buffer as ArrayBuffer);
      const bitmap = await source.createPixelMap();
      if (!this.mounted) { bitmap.release(); source.release(); return; }
      this.source = source; this.bitmap = bitmap;
    } catch (_) { if (this.mounted) this.error = '图片加载失败，点击重试'; }
    finally { if (this.mounted) this.loading = false; }
  }
  @Builder
  private fullImage() {
    Column({ space: 12 }) {
      Button('关闭预览').height(44).onClick(() => { this.preview = false; this.scale = 1; })
      if (this.bitmap) {
        Scroll() {
          Image(this.bitmap).objectFit(ImageFit.Contain).width('100%').scale({ x: this.scale, y: this.scale })
            .gesture(PinchGesture().onActionUpdate((event: GestureEvent) => { this.scale = Math.max(1, event.scale); }))
        }.scrollable(ScrollDirection.Free).layoutWeight(1).width('100%')
      }
    }.width('100%').height('100%').padding(16).backgroundColor(this.dark ? '#151517' : '#FFFFFF')
  }
  build() {
    Column({ space: 8 }) {
      Text(this.attachment.name || '图片').fontSize(12).fontColor(this.dark ? '#CFD3D6' : '#61666B')
      if (this.bitmap) {
        Image(this.bitmap).width('100%').height(220).objectFit(ImageFit.Contain).borderRadius(12)
          .onClick(() => { this.preview = true; })
      } else {
        Button(this.loading ? '正在加载图片…' : this.error || '查看图片 · ' + this.attachment.width + ' × ' + this.attachment.height)
          .height(48).enabled(!this.loading).onClick(() => { this.load(); })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
      .bindContentCover(this.preview, this.fullImage, { modalTransition: ModalTransition.DEFAULT, onDisappear: (): void => { this.preview = false; } })
  }
}
