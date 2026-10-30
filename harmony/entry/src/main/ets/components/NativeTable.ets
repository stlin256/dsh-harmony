import { NativeMarkdownTable } from '../services/NativeMarkdownTable';
import { NativeInlineText } from './NativeInlineText';

@Component
export struct NativeTable {
  @Prop table: NativeMarkdownTable = new NativeMarkdownTable();
  @StorageLink('nativeDark') private dark: boolean = false;

  @Builder
  private cell(value: string, header: boolean, align: string) {
    Column() {
      NativeInlineText({ text: value, textSize: 12, muted: !header, alignment: align })
    }.width(148).padding({ left: 10, right: 10, top: 8, bottom: 8 }).alignItems(HorizontalAlign.Start)
      .backgroundColor(header ? this.dark ? '#292A2D' : '#F1F3F5' : Color.Transparent)
  }

  build() {
    Scroll() {
      Column() {
        Row() {
          ForEach(this.table.headers, (value: string, index: number) => {
            this.cell(value, true, this.table.aligns[index])
          }, (_value: string, index: number) => 'h' + index)
        }
        ForEach(this.table.rows, (row: string[], rowIndex: number) => {
          Row() {
            ForEach(row, (value: string, index: number) => {
              this.cell(value, false, this.table.aligns[index])
            }, (_value: string, index: number) => rowIndex + ':' + index)
          }.backgroundColor(rowIndex % 2 ? this.dark ? '#1B1B1D' : '#FAFBFC' : Color.Transparent)
        }, (_row: string[], index: number) => 'r' + index)
      }.alignItems(HorizontalAlign.Start)
    }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Auto).width('100%')
      .border({ width: 0.5, color: this.dark ? '#414247' : '#DDE0E5', radius: 10 })
      .backgroundColor(this.dark ? '#18181A' : '#FFFFFF')
  }
}
