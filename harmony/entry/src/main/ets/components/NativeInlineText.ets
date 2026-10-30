import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { nativeInlineMarkdown, NativeInlineRun } from '../services/NativeInlineMarkdown';
import { NativeFilePage, NativeHarnessClient } from '../services/NativeHarnessClient';

@Component
export struct NativeInlineText {
  @Prop @Watch('changed') text: string = '';
  @Prop textSize: number = 14;
  @Prop muted: boolean = false;
  @Prop alignment: string = 'left';
  client: NativeHarnessClient = new NativeHarnessClient('');
  sessionId: string = '';
  @StorageLink('nativeDark') private dark: boolean = false;
  @State private runs: NativeInlineRun[] = [];
  @State private previewOpen: boolean = false;
  @State private previewLoading: boolean = false;
  @State private previewError: string = '';
  @State private previewTitle: string = '';
  @State private previewText: string = '';
  @State private previewLines: string = '';

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
    try {
      if (/^(?:https?|mailto):/i.test(run.href)) {
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
        await context.startAbility({ action: 'ohos.want.action.viewData', uri: run.href });
      } else {
        await this.openFile(run.href);
      }
    } catch (_) {}
  }
  private fileTarget(href: string): string {
    let target = href.startsWith('<') && href.endsWith('>') ? href.slice(1, -1) : href;
    if (target.startsWith('dsh-resource://file/session/')) {
      const suffix = target.slice('dsh-resource://file/session/'.length);
      const split = suffix.indexOf('/');
      if (split > 0) target = suffix.slice(split + 1);
    }
    const hash = target.lastIndexOf('#L');
    if (hash >= 0 && /^#L\d+(?:-L?\d+)?$/i.test(target.slice(hash))) target = target.slice(0, hash);
    return decodeURIComponent(target);
  }
  private async openFile(href: string): Promise<void> {
    if (!this.sessionId) {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, href));
      this.getUIContext().getPromptAction().showToast({ message: '链接已复制', duration: 1500 });
      return;
    }
    const path = this.fileTarget(href);
    if (!path) return;
    this.previewTitle = path.split(/[\\/]/).pop() || '文件预览';
    this.previewText = ''; this.previewError = ''; this.previewLines = '';
    this.previewOpen = true; this.previewLoading = true;
    try {
      const page: NativeFilePage = await this.client.file(this.sessionId, path, 1, 240);
      this.previewText = page.text;
      this.previewLines = '第 ' + page.offset + '–' + (page.offset + Math.max(0, page.lines - 1)) +
        ' 行' + (page.eof ? '' : ' · 已截取此页');
    } catch (_) { this.previewError = '无法预览此文件'; }
    finally { this.previewLoading = false; }
  }
  @Builder
  private filePreview() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(this.previewTitle).fontSize(17).fontWeight(FontWeight.Medium).layoutWeight(1)
          .fontColor(this.dark ? '#F9FAFB' : '#17181B')
        Button('关闭').height(40).onClick(() => { this.previewOpen = false; })
      }.width('100%')
      if (this.previewLoading) { LoadingProgress().width(26).height(26).margin({ top: 32 }) }
      else if (this.previewError) {
        Text(this.previewError).fontSize(13).fontColor(this.dark ? '#FF9393' : '#C53737')
      } else {
        Scroll() {
          Text(this.previewText).width('100%').fontSize(13).lineHeight('21fp')
            .fontFamily('Noto Sans Mono, monospace').copyOption(CopyOptions.InApp)
            .fontColor(this.dark ? '#F9FAFB' : '#17181B').wordBreak(WordBreak.BREAK_WORD)
        }.layoutWeight(1).width('100%').align(Alignment.Top)
        Text(this.previewLines).fontSize(11).fontColor(this.dark ? '#93969B' : '#8A8D91')
      }
    }.padding(16).width('100%').height('100%').backgroundColor(this.dark ? '#151517' : '#FFFFFF')
  }
  build() {
    Text() {
      ForEach(this.runs, (run: NativeInlineRun) => {
        Span(run.text).fontSize(run.code ? this.textSize - 1 : this.textSize)
          .fontWeight(run.bold ? FontWeight.Medium : FontWeight.Normal)
          .fontStyle(run.italic ? FontStyle.Italic : FontStyle.Normal)
          .fontFamily(run.code ? 'Noto Sans Mono, monospace' : 'HarmonyOS Sans')
          .fontColor(this.runColor(run)).textBackgroundStyle(this.runBackground(run))
          .decoration({ type: run.strike ? TextDecorationType.LineThrough : run.href ? TextDecorationType.Underline : TextDecorationType.None })
          .onClick(() => { this.open(run); })
      }, (_run: NativeInlineRun, index: number) => index.toString())
    }.fontSize(this.textSize).lineHeight('22fp').copyOption(CopyOptions.InApp)
      .width('100%').wordBreak(WordBreak.BREAK_WORD)
      .textAlign(this.alignment === 'right' ? TextAlign.End : this.alignment === 'center' ? TextAlign.Center : TextAlign.Start)
      .bindContentCover(this.previewOpen, this.filePreview, { modalTransition: ModalTransition.DEFAULT,
        onDisappear: (): void => { this.previewOpen = false; } })
  }
}
