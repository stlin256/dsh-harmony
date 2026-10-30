import { NativeCodeToken, nativeHighlightCode } from '../services/NativeCodeHighlight';
import { NativeSourceLine, nativeSourceLines } from '../services/NativeDocumentModel';

/** Read-only source reader with a stable line-number gutter. */
@Component
export struct NativeCodeViewer {
  @Prop @Watch('changed') code: string = '';
  @Prop @Watch('changed') language: string = '';
  @Prop @Watch('changed') startNumber: number = 1;
  @StorageLink('nativeDark') private dark: boolean = false;
  @State private lines: NativeSourceLine[] = [];

  aboutToAppear(): void { this.changed(); }
  private changed(): void { this.lines = nativeSourceLines(this.code, this.startNumber); }
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
  private tokens(line: string): NativeCodeToken[] {
    return nativeHighlightCode(line, this.language);
  }
  private gutterWidth(): number {
    const digits = Math.max(2, String(this.startNumber + Math.max(0, this.lines.length - 1)).length);
    return digits * 8 + 18;
  }
  private contentHeight(): number {
    return Math.max(44, this.lines.length * 22 + 8);
  }

  build() {
    Scroll() {
      Row() {
        Column({ space: 0 }) {
          ForEach(this.lines, (line: NativeSourceLine) => {
            Text(String(line.number)).width('100%').height(22).lineHeight(22)
              .fontSize(11).fontFamily('Noto Sans Mono, monospace').textAlign(TextAlign.End)
              .fontColor(this.dark ? '#74777D' : '#93969B')
          }, (line: NativeSourceLine) => String(line.number))
        }.width(this.gutterWidth()).height(this.contentHeight())
          .padding({ top: 4, right: 10 })
          .border({ width: { right: 0.5 }, color: this.dark ? '#34363B' : '#E4E6EA' })
        Scroll() {
          Column({ space: 0 }) {
            ForEach(this.lines, (line: NativeSourceLine) => {
              Text() {
                ForEach(this.tokens(line.text), (token: NativeCodeToken) => {
                  Span(token.text).fontColor(this.color(token.kind))
                }, (_token: NativeCodeToken, index: number) => index.toString())
              }.height(22).lineHeight(22).fontSize(12).maxLines(1)
                .fontFamily('Noto Sans Mono, monospace').copyOption(CopyOptions.InApp)
                .fontColor(this.dark ? '#E8E9EB' : '#202124')
            }, (line: NativeSourceLine) => String(line.number))
          }.padding({ left: 10, top: 4, bottom: 4 }).alignItems(HorizontalAlign.Start)
        }.layoutWeight(1).height(this.contentHeight()).scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Auto).edgeEffect(EdgeEffect.None)
      }.width('100%').alignItems(VerticalAlign.Top)
    }.width('100%').layoutWeight(1).scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto).edgeEffect(EdgeEffect.None)
      .backgroundColor(this.dark ? '#111214' : '#F7F8FA')
      .border({ width: 0.5, color: this.dark ? '#2F3136' : '#E6E8EC' })
      .borderRadius(10)
  }
}
