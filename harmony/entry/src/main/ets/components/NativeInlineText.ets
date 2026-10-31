import { common } from '@kit.AbilityKit';
import { nativeInlineMarkdown, NativeInlineRun } from '../services/NativeInlineMarkdown';
import { NativeHarnessClient } from '../services/NativeHarnessClient';
import { NativeDirectoryListing, NativeFileStat } from '../services/NativeHarnessClient';
import { nativeBareFileName, nativeFileTarget, nativeLinkKind } from '../services/NativeLinkResolver';
import { NativeFileViewRequest } from '../services/NativeSessionModel';
import { DSHIcon } from './DSHIcon';
import { NativeExperience } from '../services/NativeExperience';

@Component
export struct NativeInlineText {
  @Prop @Watch('changed') text: string = '';
  @Prop textSize: number = 14;
  @Prop muted: boolean = false;
  @Prop alignment: string = 'left';
  @Prop lineHeight: string = '22fp';
  @Prop baseWeight: FontWeight = FontWeight.Normal;
  client: NativeHarnessClient = new NativeHarnessClient('');
  sessionId: string = '';
  @StorageLink('nativeDark') private dark: boolean = false;
  @StorageLink('nativeSafeTop') private safeTop: number = 0;
  @StorageLink('nativeSafeBottom') private safeBottom: number = 0;
  @StorageLink('nativeSafeLeft') private safeLeft: number = 0;
  @StorageLink('nativeSafeRight') private safeRight: number = 0;
  @State private runs: NativeInlineRun[] = [];
  @State private remotePreview: boolean = false;
  @State private remoteUrl: string = '';
  @State private remoteTitle: string = '';
  @State private remoteError: string = '';
  private lastOpenHref: string = '';
  private lastOpenAt: number = 0;
  private fileRequestSequence: number = 0;

  aboutToAppear(): void { this.changed(); }
  private changed(): void { this.runs = nativeInlineMarkdown(this.text); }
  private runColor(run: NativeInlineRun): ResourceColor {
    if (run.href) return this.dark ? '#8AB4FF' : '#3964FE';
    if (this.muted) return this.dark ? '#CFD3D6' : '#61666B';
    return this.dark ? '#F9FAFB' : '#0F1115';
  }
  private runBackground(run: NativeInlineRun): TextBackgroundStyle {
    return { color: run.code ? this.dark ? '#353638' : '#EBEEF2' : Color.Transparent, radius: run.code ? 3 : 0 };
  }
  private async open(run: NativeInlineRun): Promise<void> {
    if (!run.href) return;
    const now = Date.now();
    if (run.href === this.lastOpenHref && now - this.lastOpenAt < 350) return;
    this.lastOpenHref = run.href;
    this.lastOpenAt = now;
    try {
      const kind = nativeLinkKind(run.href);
      if (kind === 'http' && run.isImage) {
        this.remoteUrl = run.href; this.remoteTitle = run.alt || '图片'; this.remoteError = '';
        this.remotePreview = true;
        return;
      }
      if (kind === 'http' || kind === 'external') {
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
        await context.startAbility({ action: 'ohos.want.action.viewData', uri: run.href });
      } else {
        this.openFile(run.href);
      }
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({ message: '无法打开此链接', duration: 1500 });
    }
  }
  private fileTarget(href: string): string {
    return nativeFileTarget(href, this.client.sessionCwd(this.sessionId));
  }
  private fileRequestId(): string {
    this.fileRequestSequence++;
    return Date.now().toString(36) + ':' + this.fileRequestSequence;
  }
  private openFileView(kind: string, path: string, requestId: string): void {
    const request = new NativeFileViewRequest();
    request.kind = kind;
    request.sessionId = this.sessionId;
    request.path = path;
    request.requestId = requestId;
    AppStorage.setOrCreate<string>('nativeFileViewPayload', JSON.stringify(request));
    AppStorage.setOrCreate<number>('nativeFileViewRevision',
      (AppStorage.get<number>('nativeFileViewRevision') || 0) + 1);
  }
  private fileRequestActive(requestId: string): boolean {
    try {
      const raw = AppStorage.get<string>('nativeFileViewPayload') || '';
      if (!raw) return false;
      const current = JSON.parse(raw) as NativeFileViewRequest;
      return current.requestId === requestId;
    } catch (_) {
      return false;
    }
  }
  private openFile(href: string): void {
    if (!this.sessionId) {
      this.getUIContext().getPromptAction().showToast({ message: '请先在会话中打开此链接', duration: 1500 });
      return;
    }
    const path = this.fileTarget(href);
    if (!path) return;
    const requestId = this.fileRequestId();
    // Mount the reader before network validation so a slow stat or directory
    // search never looks like an ignored tap.
    this.openFileView('file', path, requestId);
    this.resolveFile(path, requestId);
  }
  private async resolveFile(path: string, requestId: string): Promise<void> {
    try {
      const stat: NativeFileStat = await this.client.statFile(this.sessionId, path);
      if (stat.version) return;
    } catch (_) {
      // The immediate file shell remains responsible for the final error.
    }
    if (!this.fileRequestActive(requestId)) return;
    const basename = nativeBareFileName(path);
    if (basename) {
      const resolved = await this.client.findWorkspaceFile(this.sessionId, basename);
      if (resolved && this.fileRequestActive(requestId)) {
        this.openFileView('file', resolved, requestId);
        return;
      }
    }
    try {
      const listing: NativeDirectoryListing = await this.client.listFiles(this.sessionId, path);
      if (listing && this.fileRequestActive(requestId)) this.openFileView('browser', path, requestId);
    } catch (_) {
      // The mounted preview displays the concise unavailable-file state.
    }
  }
  @Builder
  private remoteImagePreview() {
    Column({ space: 8 }) {
      Row({ space: 4 }) {
        Text(this.remoteTitle || '图片').fontSize(14).fontWeight(FontWeight.Medium).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor(this.dark ? '#F9FAFB' : '#17181B')
        Button({ type: ButtonType.Normal }) {
          DSHIcon({ glyph: 'close-outline', glyphSize: 15, color: this.dark ? '#F9FAFB' : '#17181B' })
        }.width(32).height(32).borderRadius(9).backgroundColor(Color.Transparent)
          .accessibilityText('关闭图片预览').onClick(() => { this.remotePreview = false; })
      }.height(40).width('100%')
      if (this.remoteError) {
        Text(this.remoteError).fontSize(13).layoutWeight(1).textAlign(TextAlign.Center)
          .fontColor(this.dark ? '#FFB1B1' : '#B3261E')
      } else {
        Scroll() {
          Image(this.remoteUrl).objectFit(ImageFit.Contain).width('100%')
            .onError(() => { this.remoteError = '图片加载失败'; })
        }.scrollable(ScrollDirection.Free).layoutWeight(1).width('100%').align(Alignment.Center)
      }
    }.padding({
      left: 12 + this.safeLeft, right: 12 + this.safeRight,
      top: 8 + this.safeTop, bottom: 10 + this.safeBottom
    }).width('100%').height('100%').backgroundColor(this.dark ? '#151517' : '#FFFFFF')
  }
  build() {
    Text() {
      ForEach(this.runs, (run: NativeInlineRun) => {
        Span(run.text).fontSize(run.code ? this.textSize - 1 : this.textSize)
          .fontWeight(run.bold ? FontWeight.Medium : this.baseWeight)
          .fontStyle(run.italic ? FontStyle.Italic : FontStyle.Normal)
          .fontFamily(run.code ? 'Noto Sans Mono, monospace' : 'HarmonyOS Sans')
          .fontColor(this.runColor(run)).textBackgroundStyle(this.runBackground(run))
          .decoration({ type: run.strike ? TextDecorationType.LineThrough : run.href ? TextDecorationType.Underline : TextDecorationType.None })
          .onClick((): void => {
            if (run.href) this.open(run);
          })
      }, (_run: NativeInlineRun, index: number) => index.toString())
    }.fontSize(this.textSize).lineHeight(this.lineHeight)
      .width('100%').wordBreak(WordBreak.BREAK_WORD)
      .textAlign(this.alignment === 'right' ? TextAlign.End : this.alignment === 'center' ? TextAlign.Center : TextAlign.Start)
      .bindContentCover(this.remotePreview, this.remoteImagePreview, {
        modalTransition: NativeExperience.reducedMotion() ? ModalTransition.NONE : ModalTransition.DEFAULT,
        onDisappear: (): void => { this.remotePreview = false; }
      })
  }
}
