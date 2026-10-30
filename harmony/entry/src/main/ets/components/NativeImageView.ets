import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { NativeHarnessClient } from '../services/NativeHarnessClient';
import { NativeImageAttachment, NativeImagePreviewRequest } from '../services/NativeSessionModel';
import { NativeAttachmentCache } from '../services/NativeAttachmentCache';

class AttachmentResult { data: string = ''; }
@Component
export struct NativeImageView {
  client: NativeHarnessClient = new NativeHarnessClient('');
  sessionId: string = '';
  @Prop attachment: NativeImageAttachment = new NativeImageAttachment();
  @Prop compact: boolean = false;
  @Prop compactSize: number = 84;
  @StorageLink('nativeDark') private dark: boolean = false;
  @State private bitmap: image.PixelMap | null = null;
  @State private loading: boolean = false;
  @State private error: string = '';
  private mounted: boolean = false;
  private source: image.ImageSource | null = null;
  private context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
  aboutToAppear(): void { this.mounted = true; this.load(); }
  aboutToDisappear(): void {
    this.mounted = false; this.bitmap?.release(); this.source?.release();
    this.bitmap = null; this.source = null;
  }
  private async load(): Promise<void> {
    if (this.loading) return;
    this.loading = true; this.error = '';
    try {
      let bytes = await NativeAttachmentCache.load(this.context, this.client.cacheKey(),
        this.sessionId, this.attachment);
      if (!bytes) {
        const response = JSON.parse(await this.client.operation(JSON.stringify({ operation: 'attachment',
          sessionId: this.sessionId, attachment: this.attachment }))) as AttachmentResult;
        if (!this.mounted) return;
        bytes = new util.Base64Helper().decodeSync(response.data);
        await NativeAttachmentCache.save(this.context, this.client.cacheKey(),
          this.sessionId, this.attachment, bytes).catch(() => {});
      }
      if (!this.mounted) return;
      const source = image.createImageSource(bytes.buffer as ArrayBuffer);
      const options: image.DecodingOptions = { desiredSize: { width: Math.min(960, this.attachment.width || 960),
        height: Math.min(960, this.attachment.height || 960) } };
      const bitmap = await source.createPixelMap(options);
      if (!this.mounted) { bitmap.release(); source.release(); return; }
      this.source = source; this.bitmap = bitmap;
    } catch (_) { if (this.mounted) this.error = '图片加载失败，点击重试'; }
    finally { if (this.mounted) this.loading = false; }
  }
  private openLightbox(): void {
    const request = new NativeImagePreviewRequest();
    request.sessionId = this.sessionId;
    request.attachment = this.attachment;
    AppStorage.setOrCreate<string>('nativeImagePreviewPayload', JSON.stringify(request));
    AppStorage.setOrCreate<number>('nativeImagePreviewRevision',
      (AppStorage.get<number>('nativeImagePreviewRevision') || 0) + 1);
  }
  private compactHeight(): number {
    return Math.max(52, Math.round(this.compactSize * 0.76));
  }
  build() {
    Column({ space: this.compact ? 0 : 8 }) {
      if (!this.compact) {
        Text(this.attachment.name || '图片').fontSize(12).fontColor(this.dark ? '#CFD3D6' : '#61666B')
      }
      if (this.bitmap) {
        Button({ type: ButtonType.Normal }) {
          Image(this.bitmap).width('100%').height('100%')
            .objectFit(this.compact ? ImageFit.Cover : ImageFit.Contain)
            .borderRadius(12).hitTestBehavior(HitTestMode.None)
        }.width(this.compact ? this.compactSize : '100%')
          .height(this.compact ? this.compactHeight() : Math.min(320, Math.max(140, 320 * this.attachment.height /
            Math.max(1, this.attachment.width))))
          .padding(0).borderRadius(this.compact ? 10 : 12)
          .backgroundColor(this.dark ? '#232324' : '#F5F6F7').clip(true)
          .accessibilityText('预览图片 ' + (this.attachment.name || ''))
          .onClick((): void => { this.openLightbox(); })
      } else {
        Button({ type: ButtonType.Normal }) {
          if (this.loading) {
            LoadingProgress().width(this.compact ? Math.max(16, Math.round(this.compactSize * 0.22)) : 24)
              .height(this.compact ? Math.max(16, Math.round(this.compactSize * 0.22)) : 24)
              .color(this.dark ? '#8AB4FF' : '#3964FE')
          } else {
            Text(this.compact ? '重试' : (this.error || '图片 · ' + this.attachment.width + ' × ' +
              this.attachment.height))
              .fontSize(this.compact ? 10 : 12)
              .fontColor(this.dark ? '#CFD3D6' : '#61666B')
          }
        }.height(this.compact ? this.compactHeight() : 48).width(this.compact ? this.compactSize : '100%')
          .borderRadius(this.compact ? 10 : 12).enabled(!this.loading)
          .backgroundColor(this.dark ? '#232324' : '#F5F6F7')
          .accessibilityText(this.loading ? '正在加载图片' : '重试加载图片')
          .onClick((): void => { if (!this.loading) this.load(); })
      }
    }.width(this.compact ? this.compactSize : '100%').alignItems(HorizontalAlign.Start)
      .margin(this.compact ? { right: 8, bottom: 8 } : 0)
  }
}
