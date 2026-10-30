import { image } from '@kit.ImageKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { NativeFileBytes, NativeFilePage, NativeFileStat, NativeHarnessClient } from '../services/NativeHarnessClient';
import { DSHIcon } from './DSHIcon';
import { NativeExperience } from '../services/NativeExperience';
import { NativeMotion } from '../services/NativeMotion';

/** One compact foreground reader shared by chat links and the file browser. */
@Component
export struct NativeFilePreview {
  client: NativeHarnessClient = new NativeHarnessClient('');
  sessionId: string = '';
  @Prop path: string = '';
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
  @State private hasMore: boolean = false;
  @State private imageMap: image.PixelMap | null = null;
  @State private zoom: number = 1;
  private source: image.ImageSource | null = null;
  private mounted: boolean = false;
  private nextOffset: number = 1;

  aboutToAppear(): void { this.mounted = true; this.load(); }
  aboutToDisappear(): void {
    this.mounted = false;
    this.imageMap?.release();
    this.source?.release();
    this.imageMap = null;
    this.source = null;
  }

  private basename(value: string): string {
    const parts = value.replace(/\\/g, '/').split('/');
    return parts[parts.length - 1] || value || '文件';
  }
  private isImagePath(value: string): boolean {
    return /\.(?:png|jpe?g|webp|gif|bmp|svg)$/i.test(value);
  }
  private animate(action: () => void): void {
    NativeMotion.animate(this.getUIContext(), 'navigation', action);
  }
  private async loadImage(): Promise<boolean> {
    try {
      const value: NativeFileBytes = await this.client.readFileBytes(this.sessionId, this.path, '', 0, 2 * 1024 * 1024);
      if (!this.mounted) return false;
      if (!value.eof && value.bytes > value.data.byteLength) {
        this.error = '图片过大，请在兼容模式中打开';
        return false;
      }
      const source = image.createImageSource(value.data.buffer as ArrayBuffer);
      const bitmap = await source.createPixelMap();
      if (!this.mounted) { bitmap.release(); source.release(); return false; }
      this.source?.release();
      this.imageMap?.release();
      this.source = source;
      this.imageMap = bitmap;
      this.version = value.version;
      this.bytesLabel = value.bytes > 0 ? this.formatBytes(value.bytes) : '';
      return true;
    } catch (_) {
      return false;
    }
  }
  private async loadText(reset: boolean): Promise<NativeFilePage> {
    const page: NativeFilePage = await this.client.file(this.sessionId, this.path,
      reset ? 1 : this.nextOffset, 500);
    if (reset) this.text = page.text;
    else if (page.text) this.text += (this.text ? '\n' : '') + page.text;
    this.nextOffset = page.offset + Math.max(0, page.lines);
    this.hasMore = !page.eof;
    this.lineLabel = '第 ' + page.offset + '–' +
      (page.offset + Math.max(0, page.lines - 1)) + ' 行' + (page.eof ? '' : ' · 可继续加载');
    return page;
  }
  private async more(): Promise<void> {
    if (this.loadingMore || !this.hasMore) return;
    this.loadingMore = true;
    try {
      const page = await this.loadText(false);
      this.version = page.version;
    } catch (_) {
      if (this.mounted) this.error = '读取更多内容失败';
    } finally {
      if (this.mounted) this.loadingMore = false;
    }
  }
  private async load(): Promise<void> {
    if (!this.path || !this.sessionId) { this.error = '无法打开此文件'; this.loading = false; return; }
    this.loading = true; this.error = ''; this.text = ''; this.hasMore = false;
    this.nextOffset = 1; this.title = this.basename(this.path);
    try {
      const stat: NativeFileStat = await this.client.statFile(this.sessionId, this.path);
      if (!this.mounted) return;
      this.version = stat.version;
      this.bytesLabel = stat.bytes >= 0 ? this.formatBytes(stat.bytes) : '';
      if (this.isImagePath(this.path) && await this.loadImage()) return;
      try {
        const page: NativeFilePage = await this.loadText(true);
        if (!this.mounted) return;
        this.version = page.version;
        return;
      } catch (_) {
        if (!await this.loadImage()) this.error = '此文件暂不支持在原生界面预览';
      }
    } catch (_) {
      this.error = '无法读取文件';
    } finally {
      if (this.mounted) this.loading = false;
    }
  }
  private formatBytes(bytes: number): string {
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
    return (bytes / 1024 / 1024).toFixed(1) + ' MB';
  }
  private copy(): void {
    const value = this.imageMap ? this.path : this.text;
    pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value))
      .catch(() => {});
  }

  @Builder
  private header() {
    Row({ space: 4 }) {
      Column({ space: 1 }) {
        Text(this.title).fontSize(14).fontWeight(FontWeight.Medium).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor(this.dark ? '#F9FAFB' : '#17181B')
        if (this.lineLabel || this.bytesLabel) {
          Text([this.lineLabel, this.bytesLabel].filter((value: string) => !!value).join(' · '))
            .fontSize(10).fontColor(this.dark ? '#93969B' : '#8A8D91')
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Button({ type: ButtonType.Normal }) {
        DSHIcon({ glyph: this.text ? 'copy-outline' : 'copy-outline', glyphSize: 15,
          color: this.dark ? '#CFD3D6' : '#61666B' })
      }.width(32).height(32).borderRadius(9).backgroundColor(Color.Transparent)
        .accessibilityText('复制文件路径').onClick(() => { this.copy(); })
      Button({ type: ButtonType.Normal }) {
        DSHIcon({ glyph: 'close-outline', glyphSize: 15, color: this.dark ? '#F9FAFB' : '#17181B' })
      }.width(32).height(32).borderRadius(9).backgroundColor(Color.Transparent)
        .accessibilityText('关闭预览').onClick(() => { this.onClose(); })
    }.width('100%').height(40)
  }
  @Builder
  private body() {
    if (this.loading) {
      Column({ space: 10 }) {
        LoadingProgress().width(24).height(24).color(this.dark ? '#8AB4FF' : '#3964FE')
        Text('正在读取…').fontSize(12).fontColor(this.dark ? '#93969B' : '#8A8D91')
      }.layoutWeight(1).justifyContent(FlexAlign.Center)
    } else if (this.error) {
      Column({ space: 12 }) {
        Text(this.error).fontSize(13).fontColor(this.dark ? '#FFB1B1' : '#B3261E')
        Button({ type: ButtonType.Normal }) {
          DSHIcon({ glyph: 'browse-outline', glyphSize: 16, color: this.dark ? '#F9FAFB' : '#17181B' })
        }.width(36).height(36).borderRadius(18).backgroundColor(this.dark ? '#353638' : '#EBEEF2')
          .accessibilityText('重试').onClick(() => { this.load(); })
        Button('使用兼容模式').height(36).fontSize(12).borderRadius(10)
          .backgroundColor(this.dark ? '#353638' : '#EBEEF2')
          .fontColor(this.dark ? '#F9FAFB' : '#17181B')
          .onClick(() => { this.copy(); this.onClose(); })
      }.layoutWeight(1).justifyContent(FlexAlign.Center)
    } else if (this.imageMap) {
      Scroll() {
        Image(this.imageMap).objectFit(ImageFit.Contain).width('100%')
          .scale({ x: this.zoom, y: this.zoom })
          .gesture(PinchGesture().onActionUpdate((event: GestureEvent) => {
            this.zoom = Math.max(1, Math.min(4, event.scale));
          }))
          .gesture(TapGesture({ count: 2 }).onAction(() => {
            this.animate(() => { this.zoom = 1; });
          }))
      }.scrollable(ScrollDirection.Free).layoutWeight(1).width('100%').align(Alignment.Center)
    } else {
      Scroll() {
        Text(this.text || '空文件').width('100%').fontSize(12).lineHeight('20fp')
          .fontFamily('Noto Sans Mono, monospace').copyOption(CopyOptions.InApp)
          .fontColor(this.dark ? '#F9FAFB' : '#17181B').wordBreak(WordBreak.BREAK_WORD)
      }.layoutWeight(1).width('100%').align(Alignment.Top)
    }
  }
  build() {
    Column({ space: 8 }) {
      this.header()
      this.body()
      if (this.hasMore) {
        Button({ type: ButtonType.Normal }) {
          if (this.loadingMore) {
            LoadingProgress().width(14).height(14).color(this.dark ? '#8AB4FF' : '#3964FE')
          } else {
            DSHIcon({ glyph: 'chevron-left-outline', glyphSize: 12,
              color: this.dark ? '#93969B' : '#8A8D91' }).rotate({ angle: -90 })
          }
        }.width(36).height(28).borderRadius(14)
          .backgroundColor(this.dark ? '#2C2C2E' : '#F1F3F5')
          .enabled(!this.loadingMore).accessibilityText('加载更多文件内容')
          .onClick(() => { this.more(); })
      }
    }.padding({
      left: 12 + this.safeLeft, right: 12 + this.safeRight,
      top: 8 + this.safeTop, bottom: 10 + this.safeBottom
    }).width('100%').height('100%').backgroundColor(this.dark ? '#151517' : '#FFFFFF')
      .transition(NativeMotion.previewTransition())
  }
}
