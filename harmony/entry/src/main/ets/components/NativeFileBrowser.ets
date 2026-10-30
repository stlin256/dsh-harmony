import { NativeDirectoryEntry, NativeDirectoryListing, NativeHarnessClient } from '../services/NativeHarnessClient';
import { DSHIcon } from './DSHIcon';
import { NativeFilePreview } from './NativeFilePreview';
import { NativeExperience } from '../services/NativeExperience';

class NativePathPart {
  label: string = '';
  path: string = '';
}

/** Workspace-scoped directory browser. Paths are Host workspace paths. */
@Component
export struct NativeFileBrowser {
  client: NativeHarnessClient = new NativeHarnessClient('');
  sessionId: string = '';
  @Prop path: string = '';
  onClose: () => void = (): void => {};
  @StorageLink('nativeDark') private dark: boolean = false;
  @StorageLink('nativeSafeTop') private safeTop: number = 0;
  @StorageLink('nativeSafeBottom') private safeBottom: number = 0;
  @StorageLink('nativeSafeLeft') private safeLeft: number = 0;
  @StorageLink('nativeSafeRight') private safeRight: number = 0;
  @State private current: string = '';
  @State private entries: NativeDirectoryEntry[] = [];
  @State private loading: boolean = true;
  @State private error: string = '';
  @State private truncated: boolean = false;
  @State private previewPath: string = '';
  private mounted: boolean = false;

  aboutToAppear(): void { this.mounted = true; this.current = this.path; this.load(); }
  aboutToDisappear(): void { this.mounted = false; }
  private animate(action: () => void): void {
    if (NativeExperience.reducedMotion()) action();
    else this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, action);
  }
  private async load(next: string = this.current): Promise<void> {
    this.loading = true; this.error = '';
    try {
      const value: NativeDirectoryListing = await this.client.listFiles(this.sessionId, next);
      if (!this.mounted) return;
      this.current = value.path; this.entries = value.entries; this.truncated = value.truncated;
    } catch (_) { if (this.mounted) this.error = '无法打开此文件夹'; }
    finally { if (this.mounted) this.loading = false; }
  }
  private parent(): void {
    const clean = this.current.replace(/\/+$/, '');
    const split = clean.lastIndexOf('/');
    this.load(split > 0 ? clean.slice(0, split) : '');
  }
  private child(entry: NativeDirectoryEntry): string {
    if (!this.current) return entry.name;
    return this.current.replace(/\/+$/, '') + '/' + entry.name;
  }
  private open(entry: NativeDirectoryEntry): void {
    if (entry.type === 'directory') {
      this.animate(() => { this.load(this.child(entry)); });
    } else if (entry.type === 'file') {
      this.animate(() => { this.previewPath = this.child(entry); });
    }
  }
  private crumbs(): NativePathPart[] {
    const clean = this.current.replace(/\\/g, '/').replace(/\/+$/, '');
    if (!clean) return [];
    const segments = clean.split('/').filter((value: string): boolean => !!value);
    const absolute = clean.startsWith('/');
    return segments.map((value: string, index: number): NativePathPart => {
      const row = new NativePathPart(); row.label = value;
      row.path = (absolute ? '/' : '') + segments.slice(0, index + 1).join('/');
      return row;
    });
  }
  private formatBytes(bytes: number): string {
    if (bytes < 0) return '';
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
    return (bytes / 1024 / 1024).toFixed(1) + ' MB';
  }

  @Builder
  private header() {
    Row({ space: 4 }) {
      Button({ type: ButtonType.Normal }) {
        DSHIcon({ glyph: 'chevron-left-outline', glyphSize: 17,
          color: this.dark ? '#F9FAFB' : '#17181B' })
      }.width(32).height(32).borderRadius(9).backgroundColor(Color.Transparent)
        .accessibilityText('上一级').enabled(!!this.current).onClick(() => { this.parent(); })
      Column({ space: 1 }) {
        Text(this.current || '工作区').fontSize(14).fontWeight(FontWeight.Medium).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor(this.dark ? '#F9FAFB' : '#17181B')
        Text(this.current ? '文件夹' : '工作区根目录').fontSize(10)
          .fontColor(this.dark ? '#93969B' : '#8A8D91')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Button({ type: ButtonType.Normal }) {
        DSHIcon({ glyph: 'browse-outline', glyphSize: 15,
          color: this.dark ? '#CFD3D6' : '#61666B' })
      }.width(32).height(32).borderRadius(9).backgroundColor(Color.Transparent)
        .accessibilityText('在工作区根目录中查找文件').onClick(() => {
          if (this.current) this.load('');
        })
      Button({ type: ButtonType.Normal }) {
        DSHIcon({ glyph: 'close-outline', glyphSize: 15,
          color: this.dark ? '#F9FAFB' : '#17181B' })
      }.width(32).height(32).borderRadius(9).backgroundColor(Color.Transparent)
        .accessibilityText('关闭文件浏览器').onClick(() => { this.onClose(); })
    }.width('100%').height(40)
  }
  @Builder
  private breadcrumb() {
    Scroll() {
      Row({ space: 2 }) {
        Button(this.current ? '工作区' : '根目录', { type: ButtonType.Normal })
          .height(26).fontSize(10).borderRadius(7).padding({ left: 6, right: 6 })
          .backgroundColor(Color.Transparent).fontColor(this.dark ? '#93969B' : '#8A8D91')
          .enabled(!!this.current).onClick(() => { this.load(''); })
        ForEach(this.crumbs(), (part: NativePathPart, index: number) => {
          Text('/').fontSize(10).fontColor(this.dark ? '#777A80' : '#A1A1AA')
          Button(part.label, { type: ButtonType.Normal })
            .height(26).fontSize(10).borderRadius(7).padding({ left: 5, right: 5 })
            .backgroundColor(Color.Transparent)
            .fontColor(index === this.crumbs().length - 1 ?
              this.dark ? '#F9FAFB' : '#17181B' : this.dark ? '#93969B' : '#8A8D91')
            .onClick(() => { this.load(part.path); })
        }, (part: NativePathPart) => part.path)
      }.constraintSize({ minWidth: '100%' }).justifyContent(FlexAlign.Start)
    }.scrollable(ScrollDirection.Horizontal).width('100%').height(28)
  }
  @Builder
  private fileIcon(entry: NativeDirectoryEntry) {
    DSHIcon({
      glyph: entry.type === 'directory' ? 'browse-outline' : entry.type === 'file' ? 'code-outline' : 'question-outline',
      glyphSize: 16, color: entry.type === 'directory' ? this.dark ? '#8AB4FF' : '#3964FE' :
        this.dark ? '#CFD3D6' : '#61666B'
    })
  }
  @Builder
  private entryRow(entry: NativeDirectoryEntry) {
    Row({ space: 9 }) {
      this.fileIcon(entry)
      Column({ space: 1 }) {
        Text(entry.name).fontSize(13).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor(this.dark ? '#F9FAFB' : '#17181B')
        if (entry.type === 'file' && entry.size >= 0 || entry.type === 'other') {
          Text(entry.type === 'other' ? '不支持预览' : this.formatBytes(entry.size)).fontSize(10)
            .fontColor(this.dark ? '#93969B' : '#8A8D91')
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (entry.type === 'directory') {
        DSHIcon({ glyph: 'chevron-left-outline', glyphSize: 12,
          color: this.dark ? '#777A80' : '#A1A1AA' }).rotate({ angle: 180 })
      }
    }.width('100%').height(48).padding({ left: 8, right: 8 }).borderRadius(10)
      .enabled(entry.type !== 'other').accessibilityText(entry.name + '，' + entry.type)
      .onClick(() => { this.open(entry); })
      .backgroundColor(entry.type === 'directory' && this.dark ? '#202124' : Color.Transparent)
      .animation({ duration: NativeExperience.reducedMotion() ? 0 : 100, curve: Curve.EaseOut })
  }
  @Builder
  private content() {
    if (this.loading) {
      Column({ space: 10 }) {
        LoadingProgress().width(24).height(24).color(this.dark ? '#8AB4FF' : '#3964FE')
        Text('正在读取…').fontSize(12).fontColor(this.dark ? '#93969B' : '#8A8D91')
      }.layoutWeight(1).justifyContent(FlexAlign.Center)
    } else if (this.error) {
      Column({ space: 10 }) {
        Text(this.error).fontSize(13).fontColor(this.dark ? '#FFB1B1' : '#B3261E')
        Button({ type: ButtonType.Normal }) {
          DSHIcon({ glyph: 'browse-outline', glyphSize: 15, color: this.dark ? '#F9FAFB' : '#17181B' })
        }.width(36).height(36).borderRadius(18).backgroundColor(this.dark ? '#353638' : '#EBEEF2')
          .accessibilityText('重试').onClick(() => { this.load(this.current); })
      }.layoutWeight(1).justifyContent(FlexAlign.Center)
    } else if (!this.entries.length) {
      Text('此文件夹为空').fontSize(12).fontColor(this.dark ? '#93969B' : '#8A8D91')
        .layoutWeight(1).textAlign(TextAlign.Center)
    } else {
      List({ space: 2 }) {
        ForEach(this.entries, (entry: NativeDirectoryEntry) => {
          ListItem() { this.entryRow(entry) }
        }, (entry: NativeDirectoryEntry) => entry.name + ':' + entry.type)
        if (this.truncated) {
          ListItem() {
            Text('文件过多，仅显示前一部分').fontSize(11).padding(10)
              .fontColor(this.dark ? '#93969B' : '#8A8D91')
          }
        }
      }.layoutWeight(1).width('100%').cachedCount(8)
    }
  }
  build() {
    Stack() {
      Column({ space: 6 }) {
        this.header()
        this.breadcrumb()
        this.content()
      }.padding({
        left: 10 + this.safeLeft, right: 10 + this.safeRight,
        top: 8 + this.safeTop, bottom: 10 + this.safeBottom
      }).width('100%').height('100%').backgroundColor(this.dark ? '#151517' : '#FFFFFF')
      if (this.previewPath) {
        NativeFilePreview({ client: this.client, sessionId: this.sessionId, path: this.previewPath,
          onClose: (): void => { this.previewPath = ''; } })
          .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.98, y: 0.98 })))
      }
    }.width('100%').height('100%')
      .transition(NativeExperience.reducedMotion() ? TransitionEffect.IDENTITY :
        TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.98, y: 0.98 })))
  }
}
