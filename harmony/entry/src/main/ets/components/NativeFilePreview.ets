import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { NativeFilePage, NativeFileStat, NativeHarnessClient } from '../services/NativeHarnessClient';
import { NativeFileContent, NativeFileTransfer } from '../services/NativeFileTransfer';
import { NativeDocumentDescriptor, nativeDocumentDescriptor } from '../services/NativeDocumentModel';
import { DSHIcon } from './DSHIcon';
import { NativeMotion } from '../services/NativeMotion';
import { NativeDocumentModeSwitch } from './NativeDocumentModeSwitch';
import { NativeCodeViewer } from './NativeCodeViewer';
import { NativeMarkdownPreview } from './NativeMarkdownPreview';

const previewImageLimit: number = 128 * 1024 * 1024;

/** One compact foreground reader shared by chat links and the file browser. */
@Component
export struct NativeFilePreview {
  client: NativeHarnessClient = new NativeHarnessClient('');
  sessionId: string = '';
  @Prop @Watch('pathChanged') path: string = '';
  onClose: () => void = (): void => {};
  @StorageLink('nativeDark') private dark: boolean = false;
  @StorageLink('nativeSafeTop') private safeTop: number = 0;
  @StorageLink('nativeSafeBottom') private safeBottom: number = 0;
  @StorageLink('nativeSafeLeft') private safeLeft: number = 0;
  @StorageLink('nativeSafeRight') private safeRight: number = 0;
  @State private text: string = '';
  @State private title: string = '';
  @State private version: string = '';
  @State private lineLabel: string = '';
  @State private bytesLabel: string = '';
  @State private error: string = '';
  @State private loading: boolean = true;
  @State private loadingMore: boolean = false;
  @State private downloading: boolean = false;
  @State private hasMore: boolean = false;
  @State private imageMap: image.PixelMap | null = null;
  @State private zoom: number = 1;
  @State private offsetX: number = 0;
  @State private offsetY: number = 0;
  @State private documentKind: string = 'unknown';
  @State private language: string = '';
  @State private mode: string = 'code';
  @State private canToggle: boolean = false;
  @State private lineStart: number = 1;
  private source: image.ImageSource | null = null;
  private mounted: boolean = false;
  private textLoaded: boolean = false;
  private nextOffset: number = 1;
  private generation: number = 0;
  private expectedBytes: number = -1;
  private imageWidth: number = 1;
  private imageHeight: number = 1;
  private viewportWidth: number = 1;
  private viewportHeight: number = 1;
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
  private lastPinchEndedAt: number = 0;

  aboutToAppear(): void {
    this.mounted = true;
    this.reload();
  }
  aboutToDisappear(): void {
    this.mounted = false;
    this.generation++;
    this.releaseImage();
  }
  private pathChanged(): void {
    if (this.mounted) this.reload();
  }
  private reload(): void {
    this.generation++;
    this.releaseImage();
    this.text = ''; this.textLoaded = false; this.nextOffset = 1; this.lineStart = 1;
    this.hasMore = false; this.error = ''; this.loading = true; this.loadingMore = false;
    this.title = this.basename(this.path);
    this.expectedBytes = -1;
    this.zoom = 1;
    this.offsetX = 0;
    this.offsetY = 0;
    this.applyDescriptor(nativeDocumentDescriptor(this.path));
    this.load(this.generation);
  }
  private applyDescriptor(value: NativeDocumentDescriptor): void {
    this.documentKind = value.kind;
    this.language = value.language;
    this.mode = value.defaultMode;
    this.canToggle = value.canToggle;
  }
  private basename(value: string): string {
    const parts = value.replace(/\\/g, '/').split('/');
    return parts[parts.length - 1] || value || '文件';
  }
  private releaseImage(): void {
    this.imageMap?.release();
    this.source?.release();
    this.imageMap = null;
    this.source = null;
  }
  private animate(action: () => void): void {
    NativeMotion.animate(this.getUIContext(), 'navigation', action);
  }
  private resetImageZoom(): void {
    if (this.touchMode === 'pinch' || Date.now() - this.lastPinchEndedAt < 450) return;
    this.animate((): void => {
      this.zoom = 1;
      this.offsetX = 0;
      this.offsetY = 0;
    });
  }
  private clampOffset(value: number, viewport: number, content: number): number {
    const limit = Math.max(0, (content - viewport) / 2);
    return Math.max(-limit, Math.min(limit, value));
  }
  private clampTranslation(x: number, y: number, zoom: number): void {
    const width = Math.max(1, this.viewportWidth);
    const height = Math.max(1, this.viewportHeight);
    const fit = Math.min(width / Math.max(1, this.imageWidth),
      height / Math.max(1, this.imageHeight));
    this.offsetX = this.clampOffset(x, width, this.imageWidth * fit * zoom);
    this.offsetY = this.clampOffset(y, height, this.imageHeight * fit * zoom);
  }
  private beginImagePinch(first: TouchObject, second: TouchObject): void {
    this.touchMode = 'pinch';
    this.pinchStartZoom = this.zoom;
    this.pinchStartOffsetX = this.offsetX;
    this.pinchStartOffsetY = this.offsetY;
    this.pinchStartDistance = Math.max(1, Math.hypot(second.x - first.x, second.y - first.y));
    this.pinchStartMidX = (first.x + second.x) / 2;
    this.pinchStartMidY = (first.y + second.y) / 2;
    this.touchMoved = true;
  }
  private updateImagePinchTouches(first: TouchObject, second: TouchObject): void {
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
  }
  private beginImagePan(point: TouchObject): void {
    this.touchMode = 'pan';
    this.touchLastX = point.x;
    this.touchLastY = point.y;
  }
  private updateImagePan(point: TouchObject): void {
    const dx = point.x - this.touchLastX;
    const dy = point.y - this.touchLastY;
    this.touchLastX = point.x;
    this.touchLastY = point.y;
    if (this.zoom <= 1.001) return;
    this.clampTranslation(this.offsetX + dx, this.offsetY + dy, this.zoom);
  }
  private activeTouches(event: TouchEvent): TouchObject[] {
    const values: TouchObject[] = [];
    for (const point of event.touches) {
      if (point.type !== TouchType.Up && point.type !== TouchType.Cancel) values.push(point);
    }
    return values;
  }
  private finishImageTouch(event: TouchEvent, points: TouchObject[]): void {
    if (points.length >= 2) {
      this.beginImagePinch(points[0], points[1]);
      return;
    }
    if (points.length === 1) {
      this.lastPinchEndedAt = Date.now();
      this.beginImagePan(points[0]);
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
        this.resetImageZoom();
        return;
      }
      this.lastTapAt = now;
      this.lastTapX = this.touchStartX;
      this.lastTapY = this.touchStartY;
    }
    this.touchMode = 'none';
  }
  private handleImageTouch(event: TouchEvent): void {
    event.stopPropagation();
    const points = this.activeTouches(event);
    if (event.type === TouchType.Down) {
      if (points.length >= 2) {
        this.lastTapAt = 0;
        this.beginImagePinch(points[0], points[1]);
      } else if (points.length === 1) {
        if (this.touchMode !== 'pan') {
          this.touchStartAt = Date.now();
          this.touchStartX = points[0].x;
          this.touchStartY = points[0].y;
          this.touchMoved = false;
          this.beginImagePan(points[0]);
        }
      }
      return;
    }
    if (event.type === TouchType.Move) {
      if (points.length >= 2) {
        if (this.touchMode !== 'pinch') this.beginImagePinch(points[0], points[1]);
        this.touchMoved = true;
        this.updateImagePinchTouches(points[0], points[1]);
      } else if (points.length === 1) {
        if (this.touchMode !== 'pan') {
          this.beginImagePan(points[0]);
          return;
        }
        if (Math.abs(points[0].x - this.touchStartX) > 7 ||
          Math.abs(points[0].y - this.touchStartY) > 7) this.touchMoved = true;
        this.updateImagePan(points[0]);
      }
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.finishImageTouch(event, points);
    }
  }
  private async load(generation: number): Promise<void> {
    if (!this.path || !this.sessionId) {
      this.error = '无法打开此文件';
      this.loading = false;
      return;
    }
    // Size metadata is non-blocking. Content carries its own version and starts
    // on the same frame as this call.
    this.loadMetadata(generation);
    try {
      if (this.documentKind === 'image' || (this.documentKind === 'svg' && this.mode === 'preview')) {
        if (!await this.loadImageWithRetry(generation)) this.error = '无法预览此图片';
      } else {
        try {
          await this.loadText(true, generation);
          if (this.documentKind === 'unknown') {
            this.documentKind = 'text';
            this.mode = 'code';
          }
        } catch (_) {
          if (generation === this.generation) this.error = '此文件仅支持下载';
        }
      }
    } catch (_) {
      if (this.mounted && generation === this.generation) this.error = '无法读取文件';
    } finally {
      if (this.mounted && generation === this.generation) this.loading = false;
    }
  }
  private async loadMetadata(generation: number): Promise<void> {
    try {
      const stat: NativeFileStat = await this.client.statFile(this.sessionId, this.path);
      if (!this.mounted || generation !== this.generation) return;
      this.expectedBytes = stat.bytes;
      if (!this.version) this.version = stat.version;
      this.bytesLabel = stat.bytes >= 0 ? this.formatBytes(stat.bytes) : '';
    } catch (_) {
      // Content loading owns the user-visible success or failure state.
    }
  }
  private async loadImage(generation: number, expectedVersion: string = this.version,
    expectedBytes: number = this.expectedBytes): Promise<boolean> {
    let pending: image.ImageSource | null = null;
    let stage = 'read';
    try {
      const content: NativeFileContent = await NativeFileTransfer.readComplete(
        this.client, this.sessionId, this.path, previewImageLimit, expectedVersion, expectedBytes);
      if (!this.mounted || generation !== this.generation || !content.bytes.byteLength) return false;
      stage = 'source';
      pending = image.createImageSource(content.bytes.buffer as ArrayBuffer);
      stage = 'info';
      const info = await pending.getImageInfo();
      const width = Math.max(1, info.size.width);
      const height = Math.max(1, info.size.height);
      const scale = Math.min(1, 4096 / Math.max(width, height));
      stage = 'decode';
      const bitmap = await pending.createPixelMap({
        desiredSize: {
          width: Math.max(1, Math.round(width * scale)),
          height: Math.max(1, Math.round(height * scale))
        }
      });
      if (!this.mounted || generation !== this.generation) {
        bitmap.release();
        pending.release();
        return false;
      }
      this.releaseImage();
      this.source = pending;
      this.imageMap = bitmap;
      this.imageWidth = width;
      this.imageHeight = height;
      this.zoom = 1;
      this.offsetX = 0;
      this.offsetY = 0;
      this.version = content.version;
      this.bytesLabel = content.totalBytes >= 0 ? this.formatBytes(content.totalBytes) : this.bytesLabel;
      this.error = '';
      return true;
    } catch (error) {
      console.error('NativeFilePreview image ' + stage + ' failed: ' +
        (error instanceof Error ? error.message : String(error)));
      pending?.release();
      return false;
    }
  }
  private async loadImageWithRetry(generation: number): Promise<boolean> {
    if (await this.loadImage(generation)) return true;
    if (!this.mounted || generation !== this.generation) return false;
    await new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, 120);
    });
    if (!this.mounted || generation !== this.generation) return false;
    return this.loadImage(generation);
  }
  private async loadText(reset: boolean, generation: number = this.generation): Promise<NativeFilePage> {
    const page: NativeFilePage = await this.client.file(this.sessionId, this.path,
      reset ? 1 : this.nextOffset, 500);
    if (!this.mounted || generation !== this.generation) return page;
    if (reset) {
      this.text = page.text;
      this.lineStart = page.offset;
    } else if (page.text) {
      this.text += (this.text ? '\n' : '') + page.text;
    }
    this.textLoaded = true;
    this.nextOffset = page.offset + Math.max(0, page.lines);
    this.hasMore = !page.eof;
    const end = page.offset + Math.max(0, page.lines - 1);
    this.lineLabel = '第 ' + page.offset + '–' + end + ' 行' + (page.eof ? '' : ' · 可继续加载');
    return page;
  }
  private async more(): Promise<void> {
    if (this.loadingMore || !this.hasMore) return;
    const generation = this.generation;
    this.loadingMore = true;
    try {
      const page = await this.loadText(false, generation);
      if (generation === this.generation) this.version = page.version;
    } catch (_) {
      if (this.mounted && generation === this.generation) this.error = '读取更多内容失败';
    } finally {
      if (this.mounted && generation === this.generation) this.loadingMore = false;
    }
  }
  private changeMode(next: string): void {
    if (!this.canToggle || next === this.mode) return;
    const generation = this.generation;
    this.animate((): void => { this.mode = next; this.error = ''; });
    if (next === 'code' && !this.textLoaded) {
      this.loading = true;
      this.loadText(true, generation)
        .catch((): void => { if (generation === this.generation) this.error = '无法读取源代码'; })
        .finally((): void => { if (this.mounted && generation === this.generation) this.loading = false; });
    } else if (next === 'preview' && (this.documentKind === 'svg') && !this.imageMap) {
      this.loading = true;
      this.loadImageWithRetry(generation)
        .then((ok: boolean): void => { if (!ok && generation === this.generation) this.error = '无法预览此图片'; })
        .finally((): void => { if (this.mounted && generation === this.generation) this.loading = false; });
    }
  }
  private formatBytes(bytes: number): string {
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
    return (bytes / 1024 / 1024).toFixed(1) + ' MB';
  }
  private copy(): void {
    pasteboard.getSystemPasteboard().setData(
      pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.path)).catch((): void => {});
  }
  private async download(): Promise<void> {
    if (this.downloading) return;
    this.downloading = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const saved = await NativeFileTransfer.download(context, this.client, this.sessionId, this.path);
      if (saved && this.mounted) {
        this.getUIContext().getPromptAction().showToast({ message: '文件已保存', duration: 1300 });
      }
    } catch (_) {
      if (this.mounted) this.getUIContext().getPromptAction().showToast({ message: '保存文件失败', duration: 1500 });
    } finally {
      if (this.mounted) this.downloading = false;
    }
  }

  @Builder
  private header() {
    Column({ space: 5 }) {
      Row({ space: 4 }) {
        Column({ space: 1 }) {
          Text(this.title).fontSize(14).fontWeight(FontWeight.Medium).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor(this.dark ? '#F9FAFB' : '#17181B')
          if (this.lineLabel || this.bytesLabel) {
            Text([this.lineLabel, this.bytesLabel].filter((value: string) => !!value).join(' · '))
              .fontSize(10).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontColor(this.dark ? '#93969B' : '#8A8D91')
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button({ type: ButtonType.Normal }) {
          DSHIcon({ glyph: 'copy-outline', glyphSize: 15,
            color: this.dark ? '#CFD3D6' : '#61666B' })
        }.width(32).height(32).borderRadius(9).backgroundColor(Color.Transparent)
          .accessibilityText('复制文件路径').onClick((): void => { this.copy(); })
        Button({ type: ButtonType.Normal }) {
          if (this.downloading) {
            LoadingProgress().width(14).height(14).color(this.dark ? '#8AB4FF' : '#3964FE')
          } else {
            DSHIcon({ glyph: 'download-outline', glyphSize: 15,
              color: this.dark ? '#CFD3D6' : '#61666B' })
          }
        }.width(32).height(32).borderRadius(9).backgroundColor(Color.Transparent)
          .enabled(!this.downloading).accessibilityText('下载文件')
          .onClick((): void => { this.download(); })
        Button({ type: ButtonType.Normal }) {
          DSHIcon({ glyph: 'close-outline', glyphSize: 15,
            color: this.dark ? '#F9FAFB' : '#17181B' })
        }.width(32).height(32).borderRadius(9).backgroundColor(Color.Transparent)
          .accessibilityText('关闭预览').onClick((): void => { this.onClose(); })
      }.width('100%').height(40)
      if (this.canToggle) {
        Row() {
          NativeDocumentModeSwitch({ mode: this.mode,
            onMode: (value: string): void => { this.changeMode(value); } })
          Blank()
        }.width('100%').height(32)
      }
    }.width('100%')
  }
  @Builder
  private imageBody() {
    Stack({ alignContent: Alignment.Center }) {
      Image(this.imageMap).objectFit(ImageFit.Contain).width('100%').height('100%')
        .scale({ x: this.zoom, y: this.zoom })
        .translate({ x: this.offsetX, y: this.offsetY })
    }.layoutWeight(1).width('100%').clip(true)
      .onAreaChange((_old: Area, area: Area): void => {
        this.viewportWidth = Number(area.width);
        this.viewportHeight = Number(area.height);
        this.clampTranslation(this.offsetX, this.offsetY, this.zoom);
      })
      .onTouch((event: TouchEvent): void => { this.handleImageTouch(event); })
  }
  @Builder
  private textBody() {
    if (this.documentKind === 'markdown' && this.mode === 'preview') {
      Scroll() {
        NativeMarkdownPreview({ client: this.client, sessionId: this.sessionId,
          source: this.text })
          .width('100%')
      }.layoutWeight(1).width('100%').scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Auto).edgeEffect(EdgeEffect.None)
    } else {
      NativeCodeViewer({ code: this.text || (this.loading ? '' : '空文件'),
        language: this.language, startNumber: this.lineStart })
    }
  }
  @Builder
  private body() {
    if (this.loading) {
      Column({ space: 10 }) {
        LoadingProgress().width(24).height(24).color(this.dark ? '#8AB4FF' : '#3964FE')
        Text('正在读取…').fontSize(12).fontColor(this.dark ? '#93969B' : '#8A8D91')
      }.layoutWeight(1).justifyContent(FlexAlign.Center)
    } else if (this.error && !this.imageMap && !this.textLoaded) {
      Column({ space: 12 }) {
        Text(this.error).fontSize(13).textAlign(TextAlign.Center)
          .fontColor(this.dark ? '#FFB1B1' : '#B3261E')
        Button({ type: ButtonType.Normal }) {
          Row({ space: 5 }) {
            DSHIcon({ glyph: 'browse-outline', glyphSize: 15,
              color: this.dark ? '#F9FAFB' : '#17181B' })
            Text('重试').fontSize(12).fontColor(this.dark ? '#F9FAFB' : '#17181B')
          }.padding({ left: 8, right: 10 })
        }.height(36).borderRadius(10).backgroundColor(this.dark ? '#353638' : '#EBEEF2')
          .accessibilityText('重试').onClick((): void => { this.reload(); })
      }.layoutWeight(1).justifyContent(FlexAlign.Center)
    } else if (this.imageMap) {
      this.imageBody()
    } else {
      this.textBody()
    }
  }
  build() {
    Column({ space: 8 }) {
      this.header()
      this.body()
      if (this.hasMore) {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 5 }) {
            if (this.loadingMore) {
              LoadingProgress().width(14).height(14).color(this.dark ? '#8AB4FF' : '#3964FE')
            } else {
              DSHIcon({ glyph: 'chevron-left-outline', glyphSize: 12,
                color: this.dark ? '#93969B' : '#8A8D91' }).rotate({ angle: -90 })
            }
            Text('加载更多').fontSize(11).fontColor(this.dark ? '#93969B' : '#8A8D91')
          }
        }.height(30).borderRadius(9).padding({ left: 9, right: 11 })
          .backgroundColor(this.dark ? '#2C2C2E' : '#F1F3F5')
          .enabled(!this.loadingMore).accessibilityText('加载更多文件内容')
          .onClick((): void => { this.more(); })
      }
    }.padding({
      left: 12 + this.safeLeft, right: 12 + this.safeRight,
      top: 8 + this.safeTop, bottom: 10 + this.safeBottom
    }).width('100%').height('100%').backgroundColor(this.dark ? '#151517' : '#FFFFFF')
      .transition(NativeMotion.previewTransition())
  }
}
