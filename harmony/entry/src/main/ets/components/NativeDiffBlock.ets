import { pasteboard } from '@kit.BasicServicesKit';
import { NativeDiffDocument, NativeDiffRow, nativeDiffText } from '../services/NativeDiff';
import { DSHIcon } from './DSHIcon';
import { NativeExperience } from '../services/NativeExperience';
import { NativeMotion } from '../services/NativeMotion';

@Component
export struct NativeDiffBlock {
  @Prop document: NativeDiffDocument = new NativeDiffDocument();
  @StorageLink('nativeDark') private dark: boolean = false;
  @State private expanded: boolean = false;
  @State private wrapped: boolean = false;
  @State private copied: boolean = false;

  private color(kind: string): ResourceColor {
    if (kind === 'add') return this.dark ? '#9BE2B0' : '#187940';
    if (kind === 'del') return this.dark ? '#FFB1B1' : '#B3261E';
    if (kind === 'path') return this.dark ? '#8AB4FF' : '#315ECA';
    if (kind === 'gap') return this.dark ? '#777A80' : '#A1A1AA';
    return this.dark ? '#CFD3D6' : '#61666B';
  }
  private rowBackground(kind: string): ResourceColor {
    if (kind === 'add') return this.dark ? '#173423' : '#ECF8F0';
    if (kind === 'del') return this.dark ? '#3B2022' : '#FDEEEE';
    return Color.Transparent;
  }
  private toggle(): void {
    const update = (): void => { this.expanded = !this.expanded; };
    NativeMotion.animate(this.getUIContext(), 'micro', update);
  }
  private copy(): void {
    pasteboard.getSystemPasteboard().setData(pasteboard.createData(
      pasteboard.MIMETYPE_TEXT_PLAIN, nativeDiffText(this.document.rows)))
      .then(() => { this.copied = true; }).catch(() => { this.copied = false; });
  }
  private shownRows(): NativeDiffRow[] {
    if (this.expanded || this.document.rows.length <= 16) return this.document.rows;
    const rows: NativeDiffRow[] = this.document.rows.slice(0, 8);
    const gap = new NativeDiffRow(); gap.kind = 'gap';
    gap.text = '⋯ ' + (this.document.rows.length - 16) + ' 行';
    rows.push(gap);
    return rows.concat(this.document.rows.slice(this.document.rows.length - 8));
  }
  @Builder
  private line(row: NativeDiffRow) {
    Text((row.kind === 'add' ? '+ ' : row.kind === 'del' ? '- ' : row.kind === 'context' ? '  ' : '') + row.text)
      .fontSize(11).lineHeight('18fp').fontFamily('Noto Sans Mono, monospace')
      .fontColor(this.color(row.kind)).backgroundColor(this.rowBackground(row.kind))
      .width(this.wrapped ? '100%' : undefined).wordBreak(WordBreak.BREAK_WORD)
      .padding({ left: 7, right: 7, top: 1, bottom: 1 })
  }
  build() {
    Column({ space: 0 }) {
      Row({ space: 2 }) {
        Text(this.document.path || '变更').fontSize(11).fontWeight(FontWeight.Medium).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor(this.dark ? '#8AB4FF' : '#315ECA')
        Button({ type: ButtonType.Normal }) {
          DSHIcon({ glyph: 'code-outline', glyphSize: 13, color: this.dark ? '#93969B' : '#8A8D91' })
        }.width(28).height(28).borderRadius(7).backgroundColor(Color.Transparent)
          .accessibilityText(this.wrapped ? '关闭自动换行' : '自动换行')
          .onClick(() => { this.wrapped = !this.wrapped; })
        Button({ type: ButtonType.Normal }) {
          DSHIcon({ glyph: this.copied ? 'check-outline' : 'copy-outline', glyphSize: 13,
            color: this.dark ? '#93969B' : '#8A8D91' })
        }.width(28).height(28).borderRadius(7).backgroundColor(Color.Transparent)
          .accessibilityText(this.copied ? '已复制 Diff' : '复制 Diff').onClick(() => { this.copy(); })
        if (this.document.rows.length > 16) {
          Button({ type: ButtonType.Normal }) {
            DSHIcon({ glyph: 'chevron-left-outline', glyphSize: 12, color: this.dark ? '#93969B' : '#8A8D91' })
              .rotate({ angle: this.expanded ? -90 : 180 })
          }.width(28).height(28).borderRadius(7).backgroundColor(Color.Transparent)
            .accessibilityText(this.expanded ? '收起 Diff' : '展开 Diff').onClick(() => { this.toggle(); })
        }
      }.height(32).width('100%')
      Scroll() {
        Column({ space: 0 }) {
          ForEach(this.shownRows(), (row: NativeDiffRow) => {
            this.line(row)
          }, (_row: NativeDiffRow, index: number) => index.toString())
        }.alignItems(HorizontalAlign.Start).width('100%')
      }.scrollable(ScrollDirection.Horizontal).width('100%')
        .constraintSize({ maxHeight: this.expanded ? 420 : 224 })
    }.padding({ left: 7, right: 7, top: 4, bottom: 7 }).width('100%').borderRadius(9)
      .backgroundColor(this.dark ? '#232324' : '#F7F8FA')
  }
}
