import { pasteboard } from '@kit.BasicServicesKit';
import { NativeCodeToken, nativeHighlightCode } from '../services/NativeCodeHighlight';
import { DSHIcon } from './DSHIcon';

@Component
export struct NativeCodeBlock {
  @Prop @Watch('changed') code: string = '';
  @Prop @Watch('changed') language: string = '';
  @StorageLink('nativeDark') private dark: boolean = false;
  @State private tokens: NativeCodeToken[] = [];
  @State private copied: boolean = false;
  @State private codeHeight: number = 72;
  aboutToAppear(): void { this.changed(); }
  private changed(): void {
    this.tokens = nativeHighlightCode(this.code, this.language);
    const lines = this.code.split(/\r\n|\n|\r/).length;
    this.codeHeight = Math.min(420, Math.max(72, lines * 22 + 8));
  }
  private color(kind: string): ResourceColor {
    if (kind === 'keyword') return this.dark ? '#C6A8FF' : '#7A3EB1';
    if (kind === 'string') return this.dark ? '#A8D8A1' : '#2E7D32';
    if (kind === 'comment') return this.dark ? '#858991' : '#777B82';
    if (kind === 'number' || kind === 'constant') return this.dark ? '#E5B76C' : '#9A5B00';
    if (kind === 'function') return this.dark ? '#8FC5FF' : '#185FA5';
    if (kind === 'type' || kind === 'property') return this.dark ? '#80D0D2' : '#08747A';
    if (kind === 'added') return this.dark ? '#86D59A' : '#137333';
    if (kind === 'removed') return this.dark ? '#FF9A9A' : '#B3261E';
    if (kind === 'punctuation') return this.dark ? '#B8BBC1' : '#5F646B';
    return this.dark ? '#E8E9EB' : '#202124';
  }
  private copy(): void {
    pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.code))
      .then(() => { this.copied = true; setTimeout(() => { this.copied = false; }, 1000); })
      .catch(() => { this.copied = false; });
  }
  build() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        Text(this.language || '代码').fontSize(11).layoutWeight(1)
          .fontColor(this.dark ? '#8F9298' : '#74787F')
        Button({ type: ButtonType.Normal }) {
          DSHIcon({ glyph: this.copied ? 'check-outline' : 'copy-outline', glyphSize: 14,
            color: this.dark ? '#9EA1A7' : '#6E7279' })
        }.width(30).height(30).borderRadius(8).backgroundColor(Color.Transparent)
          .accessibilityText(this.copied ? '代码已复制' : '复制代码').onClick(() => { this.copy(); })
      }.width('100%')
      Scroll() {
        Scroll() {
          Text() {
            ForEach(this.tokens, (token: NativeCodeToken) => {
              Span(token.text).fontColor(this.color(token.kind))
            }, (_token: NativeCodeToken, index: number) => index.toString())
          }.fontSize(12).lineHeight('22fp').fontFamily('Noto Sans Mono, monospace')
            .copyOption(CopyOptions.InApp).textAlign(TextAlign.Start)
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Auto)
      }.width('100%').height(this.codeHeight).scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Auto)
    }.padding({ left: 11, right: 8, top: 6, bottom: 10 }).width('100%').alignItems(HorizontalAlign.Start)
      .borderRadius(12).backgroundColor(this.dark ? '#242529' : '#F3F4F6')
      .border({ width: 0.5, color: this.dark ? '#35363A' : '#E1E3E7' })
  }
}
