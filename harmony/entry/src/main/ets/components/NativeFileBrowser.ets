import { common } from '@kit.AbilityKit';
import { NativeDirectoryEntry, NativeDirectoryListing, NativeHarnessClient } from '../services/NativeHarnessClient';
import { DSHIcon } from './DSHIcon';
import { NativeFilePreview } from './NativeFilePreview';
import { NativeExperience } from '../services/NativeExperience';
import { NativeMotion } from '../services/NativeMotion';
import { NativeFileTransfer } from '../services/NativeFileTransfer';

class NativePathPart {
  label: string = '';
  path: string = '';
}

/** Workspace-scoped directory browser. Paths are Host workspace paths. */
@Component
export struct NativeFileBrowser {
  client: NativeHarnessClient = new NativeHarnessClient('');
  sessionId: string = '';
  workspaceRoot: string = '';
  @Prop path: string = '';
  onClose: () => void = (): void => {};
  @StorageLink('nativeDark') private dark: boolean = false;
  @StorageLink('nativeSafeTop') private safeTop: number = 0;
  @StorageLink('nativeSafeBottom') private safeBottom: number = 0;
  @StorageLink('nativeSafeLeft') private safeLeft: number = 0;
  @StorageLink('nativeSafeRight') private safeRight: number = 0;
  @StorageLink('nativeBackRevision') @Watch('systemBack') private backRevision: number = 0;
  @State private navigationPath: string = '';
  @State private displayPath: string = '';
  @State private entries: NativeDirectoryEntry[] = [];
  @State private loading: boolean = true;
  @State private error: string = '';
  @State private truncated: boolean = false;
  @State private previewPath: string = '';
  @State private downloadingFile: string = '';
  @State private pressedEntry: string = '';
  private mounted: boolean = false;
  private rootExitArmedAt: number = 0;

  aboutToAppear(): void {
    this.mounted = true;
    this.navigationPath = this.workspacePath(this.path);
    this.load();
  }
  aboutToDisappear(): void { this.mounted = false; }
  private animate(action: () => void): void {
    NativeMotion.animate(this.getUIContext(), 'navigation', action);
  }
  private workspacePath(value: string): string {
    return this.client.workspaceRelativePath(this.sessionId, value, this.workspaceRoot);
  }
  private async load(next: string = this.navigationPath): Promise<void> {
    const requested = this.workspacePath(next);
    this.loading = true; this.error = '';
    try {
      const value: NativeDirectoryListing = await this.client.listFiles(this.sessionId, requested);
      if (!this.mounted) return;
      this.navigationPath = requested;
      this.displayPath = value.path;
      this.entries = value.entries;
      this.truncated = value.truncated;
      this.rootExitArmedAt = 0;
      this.client.rememberBrowsePath(this.sessionId, requested);
    } catch (_) { if (this.mounted) this.error = '无法打开此文件夹'; }
    finally { if (this.mounted) this.loading = false; }
  }
  private parent(): void {
    const clean = this.navigationPath.replace(/\/+$/, '');
    const split = clean.lastIndexOf('/');
    this.load(split > 0 ? clean.slice(0, split) : '');
  }
  private child(entry: NativeDirectoryEntry): string {
    if (!this.navigationPath) return entry.name;
    return this.navigationPath.replace(/\/+$/, '') + '/' + entry.name;
  }
  private filePath(entry: NativeDirectoryEntry): string {
    const parent = this.displayPath.replace(/\/+$/, '');
    if (!parent) return this.child(entry);
    return parent + '/' + entry.name;
  }
  private open(entry: NativeDirectoryEntry): void {
    if (entry.type === 'directory') {
      this.animate(() => { this.load(this.child(entry)); });
    } else if (entry.type === 'file') {
      this.client.rememberBrowsePath(this.sessionId, this.navigationPath);
      this.rootExitArmedAt = 0;
      this.animate(() => { this.previewPath = this.filePath(entry); });
    }
  }
  private systemBack(): void {
    if (this.previewPath) {
      this.previewPath = '';
      this.rootExitArmedAt = 0;
      return;
    }
    if (this.loading) return;
    if (this.navigationPath) {
      this.parent();
      return;
    }
    const now = Date.now();
    if (this.rootExitArmedAt && now - this.rootExitArmedAt <= 2000) {
      this.onClose();
      return;
    }
    this.rootExitArmedAt = now;
    this.getUIContext().getPromptAction().showToast({
      message: '再次滑动退出文件浏览',
      duration: 1600
    });
  }
  private async download(entry: NativeDirectoryEntry): Promise<void> {
    if (this.downloadingFile || entry.type !== 'file') return;
    const path = this.filePath(entry);
    this.downloadingFile = path;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const saved = await NativeFileTransfer.download(context, this.client, this.sessionId, path);
      if (saved && this.mounted) {
        this.getUIContext().getPromptAction().showToast({ message: '文件已保存', duration: 1300 });
      }
    } catch (_) {
      if (this.mounted) {
        this.getUIContext().getPromptAction().showToast({ message: '保存文件失败', duration: 1500 });
      }
    } finally {
      if (this.mounted) this.downloadingFile = '';
    }
  }
  private crumbs(): NativePathPart[] {
    const clean = this.navigationPath;
    if (!clean) return [];
    const segments = clean.split('/').filter((value: string): boolean => !!value);
    return segments.map((value: string, index: number): NativePathPart => {
      const row = new NativePathPart(); row.label = value;
      row.path = segments.slice(0, index + 1).join('/');
      return row;
    });
  }
  private formatBytes(bytes: number): string {
    if (bytes < 0) return '';
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
    return (bytes / 1024 / 1024).toFixed(1) + ' MB';
  }
  private entryKey(entry: NativeDirectoryEntry): string {
    return entry.name + ':' + entry.type;
  }
  private byName(left: NativeDirectoryEntry, right: NativeDirectoryEntry): number {
    const a = left.name.toLowerCase();
    const b = right.name.toLowerCase();
    if (a < b) return -1;
    if (a > b) return 1;
    return 0;
  }
  private directoryEntries(): NativeDirectoryEntry[] {
    return this.entries.filter((entry: NativeDirectoryEntry): boolean =>
      entry.type === 'directory').sort((left: NativeDirectoryEntry, right: NativeDirectoryEntry): number =>
      this.byName(left, right));
  }
  private fileEntries(): NativeDirectoryEntry[] {
    return this.entries.filter((entry: NativeDirectoryEntry): boolean =>
      entry.type !== 'directory').sort((left: NativeDirectoryEntry, right: NativeDirectoryEntry): number =>
      this.byName(left, right));
  }

  @Builder
  private header() {
    Row({ space: 4 }) {
      Button({ type: ButtonType.Normal }) {
        DSHIcon({ glyph: 'chevron-left-outline', glyphSize: 17,
          color: this.dark ? '#F9FAFB' : '#17181B' })
      }.width(32).height(32).borderRadius(9).backgroundColor(Color.Transparent)
        .accessibilityText('上一级').enabled(!!this.navigationPath).onClick(() => { this.parent(); })
      Column({ space: 1 }) {
        Text(this.navigationPath || '工作区').fontSize(14).fontWeight(FontWeight.Medium).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor(this.dark ? '#F9FAFB' : '#17181B')
        Text(this.navigationPath ? '文件夹' : '工作区根目录').fontSize(10)
          .fontColor(this.dark ? '#93969B' : '#8A8D91')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Button({ type: ButtonType.Normal }) {
        DSHIcon({ glyph: 'browse-outline', glyphSize: 15,
          color: this.dark ? '#CFD3D6' : '#61666B' })
      }.width(32).height(32).borderRadius(9).backgroundColor(Color.Transparent)
        .accessibilityText('在工作区根目录中查找文件').onClick(() => {
          if (this.navigationPath) this.load('');
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
        Button(this.navigationPath ? '工作区' : '根目录', { type: ButtonType.Normal })
          .height(26).fontSize(10).borderRadius(7).padding({ left: 6, right: 6 })
          .backgroundColor(Color.Transparent).fontColor(this.dark ? '#93969B' : '#8A8D91')
          .enabled(!!this.navigationPath).onClick(() => { this.load(''); })
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
      glyph: entry.type === 'directory' ? 'folder-outline' : entry.type === 'file' ? 'code-outline' : 'question-outline',
      glyphSize: 16, color: entry.type === 'directory' ? this.dark ? '#8AB4FF' : '#3964FE' :
        this.dark ? '#CFD3D6' : '#61666B'
    })
  }
  @Builder
  private entryRow(entry: NativeDirectoryEntry) {
    Row({ space: 9 }) {
      Button({ type: ButtonType.Normal }) {
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
        }.width('100%')
      }.layoutWeight(1).height(48).padding(0).borderRadius(0).backgroundColor(Color.Transparent)
        .stateEffect(false)
        .enabled(entry.type !== 'other')
        .accessibilityText(entry.name + '，' + entry.type)
        .onClick(() => { this.open(entry); })
      if (entry.type === 'directory') {
        DSHIcon({ glyph: 'chevron-left-outline', glyphSize: 12,
          color: this.dark ? '#777A80' : '#A1A1AA' }).rotate({ angle: 180 })
      } else if (entry.type === 'file') {
        Button({ type: ButtonType.Normal }) {
          if (this.downloadingFile === this.filePath(entry)) {
            LoadingProgress().width(14).height(14).color(this.dark ? '#8AB4FF' : '#3964FE')
          } else {
            DSHIcon({ glyph: 'download-outline', glyphSize: 15,
              color: this.dark ? '#93969B' : '#777A80' })
          }
        }.width(44).height(44).padding(0).borderRadius(10).backgroundColor(Color.Transparent)
          .accessibilityText('下载 ' + entry.name)
          .enabled(!this.downloadingFile)
          .onClick((): void => { this.download(entry); })
      }
    }.width('100%').height(48).padding({ left: 8, right: 4 }).borderRadius(10).clip(true)
      .backgroundColor(this.pressedEntry === this.entryKey(entry) ?
        this.dark ? '#353638' : '#EBEEF2' : Color.Transparent)
      .animation({ duration: NativeMotion.enabled() ? NativeMotion.duration('press') : 0,
        curve: Curve.FastOutSlowIn })
      .onTouch((event: TouchEvent): void => {
        this.pressedEntry = event.type === TouchType.Down ? this.entryKey(entry) : '';
      })
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
          .accessibilityText('重试').onClick(() => { this.load(this.navigationPath); })
      }.layoutWeight(1).justifyContent(FlexAlign.Center)
    } else if (!this.entries.length) {
      Text('此文件夹为空').fontSize(12).fontColor(this.dark ? '#93969B' : '#8A8D91')
        .layoutWeight(1).textAlign(TextAlign.Center)
    } else {
      List({ space: 2 }) {
        if (this.directoryEntries().length) {
          ListItem() {
            Text('文件夹').fontSize(11).fontWeight(FontWeight.Medium)
              .fontColor(this.dark ? '#93969B' : '#8A8D91')
              .width('100%').height(26).padding({ left: 8 })
          }
          ForEach(this.directoryEntries(), (entry: NativeDirectoryEntry) => {
            ListItem() { this.entryRow(entry) }
          }, (entry: NativeDirectoryEntry) => this.entryKey(entry))
        }
        if (this.fileEntries().length) {
          ListItem() {
            Text('文件').fontSize(11).fontWeight(FontWeight.Medium)
              .fontColor(this.dark ? '#93969B' : '#8A8D91')
              .width('100%').height(26).padding({ left: 8, top: this.directoryEntries().length ? 4 : 0 })
          }
          ForEach(this.fileEntries(), (entry: NativeDirectoryEntry) => {
            ListItem() { this.entryRow(entry) }
          }, (entry: NativeDirectoryEntry) => this.entryKey(entry))
        }
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
          .transition(NativeMotion.overlayTransition())
      }
    }.width('100%').height('100%')
      .transition(NativeMotion.navigationTransition())
  }
}
