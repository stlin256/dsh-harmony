import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { NativeHarnessClient } from '../services/NativeHarnessClient';
import { NativeImageAttachment } from '../services/NativeSessionModel';
import { NativeAttachmentCache } from '../services/NativeAttachmentCache';
import { NativeMotion } from '../services/NativeMotion';
import { DSHIcon } from './DSHIcon';

class LightboxAttachmentResult {
  data: string = '';
}

@Component
export struct NativeImageLightbox {
  client: NativeHarnessClient = new NativeHarnessClient('');
  sessionId: string = '';
  attachment: NativeImageAttachment = new NativeImageAttachment();
  onClose: () => void = (): void => {};
  @StorageLink('nativeSafeTop') private safeTop: number = 0;
  @StorageLink('nativeSafeBottom') private safeBottom: number = 0;
  @StorageLink('nativeSafeLeft') private safeLeft: number = 0;
  @StorageLink('nativeSafeRight') private safeRight: number = 0;
  @State private bitmap: image.PixelMap | null = null;
  @State private loading: boolean = true;
  @State private error: string = '';
  @State private zoom: number = 1;
  @State private saving: boolean = false;
  @State private viewportWidth: number = 0;
  @State private viewportHeight: number = 0;
  private mounted: boolean = false;
  private bytes: Uint8Array | null = null;
  private context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;

  aboutToAppear(): void {
    this.mounted = true;
    this.load();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.bytes = null;
    this.bitmap?.release();
    this.bitmap = null;
  }

  private async load(): Promise<void> {
    if (this.loading && this.bitmap) return;
    this.loading = true;
    this.error = '';
    let source: image.ImageSource | null = null;
    try {
      let bytes = await NativeAttachmentCache.load(this.context, this.client.cacheKey(),
        this.sessionId, this.attachment);
      if (!bytes) {
        const response = JSON.parse(await this.client.operation(JSON.stringify({
          operation: 'attachment', sessionId: this.sessionId, attachment: this.attachment
        }))) as LightboxAttachmentResult;
        bytes = new util.Base64Helper().decodeSync(response.data);
        await NativeAttachmentCache.save(this.context, this.client.cacheKey(),
          this.sessionId, this.attachment, bytes).catch((): void => {});
      }
      this.bytes = bytes;
      source = image.createImageSource(bytes.buffer as ArrayBuffer);
      const bitmap = await source.createPixelMap();
      source.release();
      source = null;
      if (!this.mounted) {
        bitmap.release();
        return;
      }
      this.bitmap?.release();
      this.bitmap = bitmap;
      this.zoom = 1;
    } catch (_) {
      if (this.mounted) this.error = '图片加载失败';
    } finally {
      source?.release();
      if (this.mounted) this.loading = false;
    }
  }

  private resetZoom(): void {
    NativeMotion.animate(this.getUIContext(), 'micro', (): void => { this.zoom = 1; });
  }

  private mediaExtension(): string {
    const name = (this.attachment.name || '').toLowerCase();
    const dot = name.lastIndexOf('.');
    const candidate = dot >= 0 ? name.slice(dot + 1) : '';
    if (['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'heif'].includes(candidate)) {
      return candidate;
    }
    const mediaType = (this.attachment.mediaType || '').toLowerCase();
    if (mediaType === 'image/png') return 'png';
    if (mediaType === 'image/webp') return 'webp';
    if (mediaType === 'image/gif') return 'gif';
    if (mediaType === 'image/bmp') return 'bmp';
    if (mediaType === 'image/heic') return 'heic';
    if (mediaType === 'image/heif') return 'heif';
    return 'jpg';
  }

  private async saveToGallery(): Promise<void> {
    if (this.saving || !this.bytes) return;
    this.saving = true;
    const extension = this.mediaExtension();
    const path = this.context.cacheDir + '/dsh-image-' + util.generateRandomUUID() + '.' + extension;
    let output: fileIo.File | null = null;
    try {
      output = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(output.fd, this.bytes.buffer as ArrayBuffer);
      fileIo.closeSync(output);
      output = null;
      const config: photoAccessHelper.PhotoCreationConfig = {
        title: 'DSH-Harmony-' + Date.now(),
        fileNameExtension: extension,
        photoType: photoAccessHelper.PhotoType.IMAGE
      };
      const created = await photoAccessHelper.getPhotoAccessHelper(this.context)
        .showAssetsCreationDialog([fileUri.getUriFromPath(path)], [config]);
      if (this.mounted) {
        this.getUIContext().getPromptAction().showToast({
          message: created.length ? '已保存到图库' : '已取消保存',
          duration: 1500
        });
      }
    } catch (_) {
      if (this.mounted) {
        this.getUIContext().getPromptAction().showToast({
          message: '保存图片失败',
          duration: 1500
        });
      }
    } finally {
      if (output) fileIo.closeSync(output);
      try { fileIo.unlinkSync(path); } catch (_) {}
      if (this.mounted) this.saving = false;
    }
  }

  private closeIfOutside(x: number, y: number): void {
    const width = Math.max(1, this.viewportWidth);
    const height = Math.max(1, this.viewportHeight);
    const sourceWidth = Math.max(1, this.attachment.width);
    const sourceHeight = Math.max(1, this.attachment.height);
    const fit = Math.min(width / sourceWidth, height / sourceHeight);
    const imageWidth = sourceWidth * fit * this.zoom;
    const imageHeight = sourceHeight * fit * this.zoom;
    const left = (width - imageWidth) / 2;
    const top = (height - imageHeight) / 2;
    const inside = x >= left && x <= left + imageWidth && y >= top && y <= top + imageHeight;
    if (!inside) this.onClose();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.bitmap) {
        Scroll() {
          Image(this.bitmap).objectFit(ImageFit.Contain).width('100%').height('100%')
            .scale({ x: this.zoom, y: this.zoom })
            .accessibilityText('长按可保存图片')
            .gesture(PinchGesture({ fingers: 2, distance: 5 })
              .onActionUpdate((event: GestureEvent): void => {
                this.zoom = Math.max(1, Math.min(5, event.scale));
              }))
            .gesture(TapGesture({ count: 2 }).onAction((): void => { this.resetZoom(); }))
            .gesture(LongPressGesture({ repeat: false, duration: 500 })
              .onAction((): void => { this.saveToGallery(); }))
        }.width('100%').height('100%').scrollable(ScrollDirection.Free)
          .edgeEffect(EdgeEffect.None)
          .onAreaChange((_old: Area, area: Area): void => {
            this.viewportWidth = Number(area.width);
            this.viewportHeight = Number(area.height);
          })
          .onClick((event: ClickEvent): void => { this.closeIfOutside(event.x, event.y); })
      } else if (this.loading) {
        Column({ space: 10 }) {
          LoadingProgress().width(28).height(28).color('#FFFFFF')
          Text('正在加载图片…').fontSize(12).fontColor('#D7D9DE')
        }
      } else {
        Column({ space: 12 }) {
          Text(this.error || '图片不可用').fontSize(14).fontColor('#F2F3F5')
          Button('重试', { type: ButtonType.Normal }).height(40).fontSize(13).borderRadius(10)
            .backgroundColor('#303136').fontColor('#FFFFFF')
            .onClick((): void => { this.load(); })
        }
      }
      Row({ space: 8 }) {
        Text(this.attachment.name || '图片').fontSize(14).fontWeight(FontWeight.Medium).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor('#FFFFFF')
        if (this.saving) {
          LoadingProgress().width(20).height(20).color('#FFFFFF')
        }
        Button({ type: ButtonType.Circle }) {
          DSHIcon({ glyph: 'close-outline', glyphSize: 17, color: '#FFFFFF' })
        }.width(40).height(40).backgroundColor('#303136').accessibilityText('关闭图片预览')
          .onClick((): void => { this.onClose(); })
      }.width('100%').height(58 + this.safeTop)
        .padding({ left: 8 + this.safeLeft, right: 8 + this.safeRight, top: 10 + this.safeTop })
        .position({ x: 0, y: 0 })
    }.width('100%').height('100%')
      .padding({ bottom: this.safeBottom })
      .backgroundColor('#F5000000')
      .transition(NativeMotion.previewTransition())
  }
}
