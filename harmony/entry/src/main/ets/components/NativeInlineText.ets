import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { nativeInlineMarkdown, NativeInlineRun } from '../services/NativeInlineMarkdown';

@Component
export struct NativeInlineText {
  @Prop @Watch('changed') text: string = '';
  @Prop textSize: number = 14;
  @Prop muted: boolean = false;
  @StorageLink('nativeDark') private dark: boolean = false;
  @State private runs: NativeInlineRun[] = [];

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
      if (/^https?:\/\//i.test(run.href)) {
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
        await context.startAbility({ action: 'ohos.want.action.viewData', uri: run.href });
      } else {
        await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, run.href));
        this.getUIContext().getPromptAction().showToast({ message: '链接已复制', duration: 1500 });
      }
    } catch (_) {}
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
  }
}
