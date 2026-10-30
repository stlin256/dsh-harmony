import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { NativeHarnessClient } from '../services/NativeHarnessClient';
import { NativeImageAttachment } from '../services/NativeSessionModel';
import { DSHIcon } from './DSHIcon';
import { NativeExperience } from '../services/NativeExperience';

class AttachmentResult { data: string = ''; }
@Component
export struct NativeImageView {
  client: NativeHarnessClient = new NativeHarnessClient('');
  sessionId: string = '';
  @Prop attachment: NativeImageAttachment = new NativeImageAttachment();
  @StorageLink('nativeDark') private dark: boolean = false;
  @StorageLink('nativeSafeTop') private safeTop: number = 0;
  @StorageLink('nativeSafeBottom') private safeBottom: number = 0;
  @StorageLink('nativeSafeLeft') private safeLeft: number = 0;
  @StorageLink('nativeSafeRight') private safeRight: number = 0;
  @State private bitmap: image.PixelMap | null = null;
  @State private fullBitmap: image.PixelMap | null = null;
  @State private loading: boolean = false;
  @State private error: string = '';
  @State private preview: boolean = false;
  @State private previewScale: number = 1;
  private mounted: boolean = false;
  private source: image.ImageSource | null = null;
  aboutToAppear(): void { this.mounted = true; this.load(); }
  aboutToDisappear(): void {
    this.mounted = false; this.fullBitmap?.release(); this.bitmap?.release(); this.source?.release();
    this.fullBitmap = null; this.bitmap = null; this.source = null;
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
      const options: image.DecodingOptions = { desiredSize: { width: Math.min(960, this.attachment.width || 960),
        height: Math.min(960, this.attachment.height || 960) } };
      const bitmap = await source.createPixelMap(options);
      if (!this.mounted) { bitmap.release(); source.release(); return; }
      this.source = source; this.bitmap = bitmap;
    } catch (_) { if (this.mounted) this.error = '图片加载失败，点击重试'; }
    finally { if (this.mounted) this.loading = false; }
  }
  private async openPreview(): Promise<void> {
    if (!this.source) return;
    this.preview = true; this.previewScale = 1;
    if (this.fullBitmap || this.loading) return;
    this.loading = true;
    try {
      const bitmap = await this.source.createPixelMap();
      if (!this.mounted) { bitmap.release(); return; }
      this.fullBitmap = bitmap;
    } catch (_) {
      if (this.mounted) this.error = '图片预览失败，请重试';
    } finally { if (this.mounted) this.loading = false; }
  }
  private animate(action: () => void): void {
    if (NativeExperience.reducedMotion()) action();
    else this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, action);
  }
  @Builder
  private fullImage() {
    Column({ space: 8 }) {
      Row({ space: 4 }) {
        Text(this.attachment.name || '图片').fontSize(14).fontWeight(FontWeight.Medium).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor(this.dark ? '#F9FAFB' : '#17181B')
        Button({ type: ButtonType.Normal }) {
          DSHIcon({ glyph: 'close-outline', glyphSize: 15, color: this.dark ? '#F9FAFB' : '#17181B' })
        }.width(32).height(32).borderRadius(9).backgroundColor(Color.Transparent)
          .accessibilityText('关闭图片预览').onClick(() => { this.preview = false; this.previewScale = 1; })
      }.height(40).width('100%')
      if (this.fullBitmap || this.bitmap) {
        Scroll() {
          Image(this.fullBitmap || this.bitmap).objectFit(ImageFit.Contain).width('100%').scale({ x: this.previewScale, y: this.previewScale })
            .gesture(PinchGesture().onActionUpdate((event: GestureEvent) => {
              this.animate(() => { this.previewScale = Math.max(1, Math.min(4, event.scale)); });
            }))
            .gesture(TapGesture({ count: 2 }).onAction(() => {
              this.animate(() => { this.previewScale = 1; });
            }))
        }.scrollable(ScrollDirection.Free).layoutWeight(1).width('100%')
      } else {
        LoadingProgress().width(28).height(28)
      }
    }.width('100%').height('100%').padding({
      left: 12 + this.safeLeft, right: 12 + this.safeRight,
      top: 8 + this.safeTop, bottom: 10 + this.safeBottom
    }).backgroundColor(this.dark ? '#151517' : '#FFFFFF')
  }
  build() {
    Column({ space: 8 }) {
      Text(this.attachment.name || '图片').fontSize(12).fontColor(this.dark ? '#CFD3D6' : '#61666B')
      if (this.bitmap) {
        Image(this.bitmap).width('100%').height(Math.min(320, Math.max(140, 320 * this.attachment.height /
          Math.max(1, this.attachment.width)))).objectFit(ImageFit.Contain).borderRadius(12)
          .backgroundColor(this.dark ? '#232324' : '#F5F6F7').onClick(() => { this.openPreview(); })
      } else {
        Button(this.loading ? '正在加载图片…' : this.error || '图片 · ' + this.attachment.width + ' × ' + this.attachment.height)
          .height(48).width('100%').borderRadius(12).enabled(!this.loading)
          .backgroundColor(this.dark ? '#232324' : '#F5F6F7').fontColor(this.dark ? '#CFD3D6' : '#61666B')
          .onClick(() => { if (!this.loading) this.load(); })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
      .bindContentCover(this.preview, this.fullImage, {
        modalTransition: NativeExperience.reducedMotion() ? ModalTransition.NONE : ModalTransition.DEFAULT,
        onDisappear: (): void => { this.preview = false; }
      })
  }
}
