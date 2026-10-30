import { common } from '@kit.AbilityKit';
import { nativeInlineMarkdown, NativeInlineRun } from '../services/NativeInlineMarkdown';
import { NativeHarnessClient } from '../services/NativeHarnessClient';
import { NativeDirectoryListing, NativeFileStat } from '../services/NativeHarnessClient';
import { nativeFileTarget, nativeLinkKind } from '../services/NativeLinkResolver';
import { NativeFilePreview } from './NativeFilePreview';
import { NativeFileBrowser } from './NativeFileBrowser';
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
  @State private filePreviewOpen: boolean = false;
  @State private filePreviewPath: string = '';
  @State private browserOpen: boolean = false;
  @State private browserPath: string = '';
  @State private remotePreview: boolean = false;
  @State private remoteUrl: string = '';
  @State private remoteTitle: string = '';
  @State private remoteError: string = '';
  @State private resolvingFile: boolean = false;
  private lastOpenHref: string = '';
  private lastOpenAt: number = 0;

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
        await this.openFile(run.href);
      }
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({ message: '无法打开此链接', duration: 1500 });
    }
  }
  private fileTarget(href: string): string {
    return nativeFileTarget(href, this.client.sessionCwd(this.sessionId));
  }
  private async openFile(href: string): Promise<void> {
    if (!this.sessionId) {
      this.getUIContext().getPromptAction().showToast({ message: '请先在会话中打开此链接', duration: 1500 });
      return;
    }
    const path = this.fileTarget(href);
    if (!path) return;
    this.resolvingFile = true;
    try {
      const stat: NativeFileStat = await this.client.statFile(this.sessionId, path);
      if (!stat.version) throw new Error('Invalid file');
      this.filePreviewPath = path; this.filePreviewOpen = true;
    } catch (_) {
      try {
        const listing: NativeDirectoryListing = await this.client.listFiles(this.sessionId, path);
        this.browserPath = listing.path || path; this.browserOpen = true;
      } catch (_) {
        this.getUIContext().getPromptAction().showToast({ message: '无法打开此链接', duration: 1500 });
      }
    } finally { this.resolvingFile = false; }
  }
  private openSingleLink(): void {
    const linked = this.runs.filter((run: NativeInlineRun): boolean => run.href.length > 0);
    if (linked.length === 1) this.open(linked[0]);
  }
  @Builder
  private resolvingOverlay() {
    Column({ space: 10 }) {
      LoadingProgress().width(24).height(24).color(this.dark ? '#8AB4FF' : '#3964FE')
      Text('正在打开…').fontSize(12).fontColor(this.dark ? '#CFD3D6' : '#61666B')
    }.width(132).height(88).justifyContent(FlexAlign.Center).borderRadius(16)
      .backgroundColor(this.dark ? '#2C2C2E' : '#FFFFFF')
      .border({ width: 0.5, color: this.dark ? '#45464B' : '#E2E4E8' })
  }
  @Builder
  private filePreview() {
    NativeFilePreview({ client: this.client, sessionId: this.sessionId, path: this.filePreviewPath,
      onClose: (): void => { this.filePreviewOpen = false; } })
  }
  @Builder
  private fileBrowser() {
    NativeFileBrowser({ client: this.client, sessionId: this.sessionId, path: this.browserPath,
      onClose: (): void => { this.browserOpen = false; } })
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
          .onClick(() => { this.open(run); })
      }, (_run: NativeInlineRun, index: number) => index.toString())
    }.fontSize(this.textSize).lineHeight(this.lineHeight)
      .width('100%').wordBreak(WordBreak.BREAK_WORD)
      .textAlign(this.alignment === 'right' ? TextAlign.End : this.alignment === 'center' ? TextAlign.Center : TextAlign.Start)
      .onClick((): void => { this.openSingleLink(); })
      .bindContentCover(this.resolvingFile, this.resolvingOverlay, {
        modalTransition: ModalTransition.NONE,
        onDisappear: (): void => { this.resolvingFile = false; }
      })
      .bindContentCover(this.filePreviewOpen, this.filePreview, {
        modalTransition: NativeExperience.reducedMotion() ? ModalTransition.NONE : ModalTransition.DEFAULT,
        onDisappear: (): void => { this.filePreviewOpen = false; }
      })
      .bindContentCover(this.browserOpen, this.fileBrowser, {
        modalTransition: NativeExperience.reducedMotion() ? ModalTransition.NONE : ModalTransition.DEFAULT,
        onDisappear: (): void => { this.browserOpen = false; }
      })
      .bindContentCover(this.remotePreview, this.remoteImagePreview, {
        modalTransition: NativeExperience.reducedMotion() ? ModalTransition.NONE : ModalTransition.DEFAULT,
        onDisappear: (): void => { this.remotePreview = false; }
      })
  }
}
