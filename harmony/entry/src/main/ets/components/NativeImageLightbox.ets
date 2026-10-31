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
  @State private offsetX: number = 0;
  @State private offsetY: number = 0;
  @State private saving: boolean = false;
  @State private viewportWidth: number = 0;
  @State private viewportHeight: number = 0;
  private mounted: boolean = false;
  private pinchStartZoom: number = 1;
  private pinchStartOffsetX: number = 0;
  private pinchStartOffsetY: number = 0;
  private pinchStartDistance: number = 0;
  private pinchStartMidX: number = 0;
  private pinchStartMidY: number = 0;
  private touchMode: string = 'none';
  private touchLastX: number = 0;
  private touchLastY: number = 0;
  private touchStartAt: number = 0;
  private touchStartX: number = 0;
  private touchStartY: number = 0;
  private touchMoved: boolean = false;
  private lastTapAt: number = 0;
  private lastTapX: number = 0;
  private lastTapY: number = 0;
  private longPressTimer: number = -1;
  private lastPinchEndedAt: number = 0;
  private suppressClickUntil: number = 0;
  private bytes: Uint8Array | null = null;
  private context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;

  aboutToAppear(): void {
    this.mounted = true;
    this.load();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.clearLongPress();
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
      this.offsetX = 0;
      this.offsetY = 0;
    } catch (_) {
      if (this.mounted) this.error = '图片加载失败';
    } finally {
      source?.release();
      if (this.mounted) this.loading = false;
    }
  }

  private resetZoom(): void {
    // Some platform versions synthesize a double tap at the end of a two-finger
    // pinch. A reset must only follow a deliberate two-tap sequence.
    if (this.touchMode === 'pinch' || Date.now() - this.lastPinchEndedAt < 450) return;
    NativeMotion.animate(this.getUIContext(), 'micro', (): void => {
      this.zoom = 1;
      this.offsetX = 0;
      this.offsetY = 0;
    });
  }

  private markGestureActivity(): void {
    // A completed drag/pinch commonly emits a click at the release point. Do not
    // reinterpret that synthetic click as a background-tap dismissal.
    this.suppressClickUntil = Date.now() + 350;
  }

  private clampOffset(value: number, viewport: number, content: number): number {
    const limit = Math.max(0, (content - viewport) / 2);
    return Math.max(-limit, Math.min(limit, value));
  }

  private clampTranslation(x: number, y: number, zoom: number): void {
    const width = Math.max(1, this.viewportWidth);
    const height = Math.max(1, this.viewportHeight);
    const sourceWidth = Math.max(1, this.attachment.width);
    const sourceHeight = Math.max(1, this.attachment.height);
    const fit = Math.min(width / sourceWidth, height / sourceHeight);
    this.offsetX = this.clampOffset(x, width, sourceWidth * fit * zoom);
    this.offsetY = this.clampOffset(y, height, sourceHeight * fit * zoom);
  }

  private beginPinch(first: TouchObject, second: TouchObject): void {
    this.clearLongPress();
    this.touchMode = 'pinch';
    this.pinchStartZoom = this.zoom;
    this.pinchStartOffsetX = this.offsetX;
    this.pinchStartOffsetY = this.offsetY;
    this.pinchStartDistance = Math.max(1, Math.hypot(second.x - first.x, second.y - first.y));
    this.pinchStartMidX = (first.x + second.x) / 2;
    this.pinchStartMidY = (first.y + second.y) / 2;
    this.touchMoved = true;
    this.markGestureActivity();
  }

  private updatePinchTouches(first: TouchObject, second: TouchObject): void {
    const distance = Math.max(1, Math.hypot(second.x - first.x, second.y - first.y));
    const midpointX = (first.x + second.x) / 2;
    const midpointY = (first.y + second.y) / 2;
    const nextZoom = Math.max(1, Math.min(5, this.pinchStartZoom * distance / this.pinchStartDistance));
    const startZoom = Math.max(0.001, this.pinchStartZoom);
    const startFocusX = this.pinchStartMidX - this.viewportWidth / 2;
    const startFocusY = this.pinchStartMidY - this.viewportHeight / 2;
    const focusX = midpointX - this.viewportWidth / 2;
    const focusY = midpointY - this.viewportHeight / 2;
    const ratio = nextZoom / startZoom;
    this.zoom = nextZoom;
    this.clampTranslation(
      focusX - (startFocusX - this.pinchStartOffsetX) * ratio,
      focusY - (startFocusY - this.pinchStartOffsetY) * ratio,
      nextZoom);
    this.markGestureActivity();
  }

  private beginPan(point: TouchObject): void {
    this.touchMode = 'pan';
    this.touchLastX = point.x;
    this.touchLastY = point.y;
  }

  private updatePan(point: TouchObject): void {
    const dx = point.x - this.touchLastX;
    const dy = point.y - this.touchLastY;
    this.touchLastX = point.x;
    this.touchLastY = point.y;
    if (this.zoom <= 1.001) return;
    this.clampTranslation(this.offsetX + dx, this.offsetY + dy, this.zoom);
    this.markGestureActivity();
  }

  private activeTouches(event: TouchEvent): TouchObject[] {
    const values: TouchObject[] = [];
    for (const point of event.touches) {
      if (point.type !== TouchType.Up && point.type !== TouchType.Cancel) values.push(point);
    }
    return values;
  }

  private clearLongPress(): void {
    if (this.longPressTimer >= 0) {
      clearTimeout(this.longPressTimer);
      this.longPressTimer = -1;
    }
  }

  private scheduleLongPress(): void {
    this.clearLongPress();
    this.longPressTimer = setTimeout((): void => {
      this.longPressTimer = -1;
      if (this.touchMode === 'pan' && !this.touchMoved && this.mounted) {
        this.markGestureActivity();
        this.saveToGallery();
      }
    }, 520);
  }

  private finishTouch(event: TouchEvent, points: TouchObject[]): void {
    this.clearLongPress();
    if (points.length >= 2) {
      this.beginPinch(points[0], points[1]);
      return;
    }
    if (points.length === 1) {
      this.lastPinchEndedAt = Date.now();
      this.beginPan(points[0]);
      return;
    }
    if (this.touchMode === 'pinch') this.lastPinchEndedAt = Date.now();
    if (!this.touchMoved && event.type === TouchType.Up) {
      const now = Date.now();
      if (now - this.touchStartAt < 300 &&
        now - this.lastTapAt < 320 &&
        Math.abs(this.touchStartX - this.lastTapX) < 32 &&
        Math.abs(this.touchStartY - this.lastTapY) < 32) {
        this.lastTapAt = 0;
        this.touchMode = 'none';
        this.resetZoom();
        return;
      }
      this.lastTapAt = now;
      this.lastTapX = this.touchStartX;
      this.lastTapY = this.touchStartY;
      const changed = event.changedTouches.length ? event.changedTouches[0] : null;
      this.touchMode = 'none';
      if (changed) this.closeIfOutside(changed.x, changed.y);
      return;
    }
    this.touchMode = 'none';
  }

  private handleTouch(event: TouchEvent): void {
    const points = this.activeTouches(event);
    if (event.type === TouchType.Down) {
      if (points.length >= 2) {
        this.lastTapAt = 0;
        this.beginPinch(points[0], points[1]);
      } else if (points.length === 1) {
        if (this.touchMode !== 'pan') {
          this.touchStartAt = Date.now();
          this.touchStartX = points[0].x;
          this.touchStartY = points[0].y;
          this.touchMoved = false;
          this.beginPan(points[0]);
          this.scheduleLongPress();
        }
      }
      return;
    }
    if (event.type === TouchType.Move) {
      if (points.length >= 2) {
        if (this.touchMode !== 'pinch') this.beginPinch(points[0], points[1]);
        this.touchMoved = true;
        this.updatePinchTouches(points[0], points[1]);
      } else if (points.length === 1) {
        if (this.touchMode !== 'pan') {
          this.beginPan(points[0]);
          return;
        }
        if (Math.abs(points[0].x - this.touchStartX) > 7 ||
          Math.abs(points[0].y - this.touchStartY) > 7) {
          this.touchMoved = true;
          this.clearLongPress();
        }
        this.updatePan(points[0]);
      }
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.finishTouch(event, points);
    }
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
    if (Date.now() < this.suppressClickUntil) return;
    const width = Math.max(1, this.viewportWidth);
    const height = Math.max(1, this.viewportHeight);
    const sourceWidth = Math.max(1, this.attachment.width);
    const sourceHeight = Math.max(1, this.attachment.height);
    const fit = Math.min(width / sourceWidth, height / sourceHeight);
    const imageWidth = sourceWidth * fit * this.zoom;
    const imageHeight = sourceHeight * fit * this.zoom;
    const left = (width - imageWidth) / 2 + this.offsetX;
    const top = (height - imageHeight) / 2 + this.offsetY;
    const inside = x >= left && x <= left + imageWidth && y >= top && y <= top + imageHeight;
    if (!inside) this.onClose();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.bitmap) {
        Stack({ alignContent: Alignment.Center }) {
          Image(this.bitmap).objectFit(ImageFit.Contain).width('100%').height('100%')
            .scale({ x: this.zoom, y: this.zoom })
            .translate({ x: this.offsetX, y: this.offsetY })
            .accessibilityText('长按可保存图片')
        }.width('100%').height('100%')
          .onAreaChange((_old: Area, area: Area): void => {
            this.viewportWidth = Number(area.width);
            this.viewportHeight = Number(area.height);
            this.clampTranslation(this.offsetX, this.offsetY, this.zoom);
          })
          .onTouch((event: TouchEvent): void => { this.handleTouch(event); })
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
