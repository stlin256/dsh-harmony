import { DSHIcon } from './DSHIcon';
import { NativePlanDocument, NativePlanItem, nativePlanProgress } from '../services/NativePlan';

@Component
export struct NativePlanView {
  @Prop document: NativePlanDocument = new NativePlanDocument();
  @Prop showHeader: boolean = true;
  @StorageLink('nativeDark') private dark: boolean = false;

  private statusLabel(status: string): string {
    if (status === 'completed') return '已完成';
    if (status === 'in_progress') return '进行中';
    return '待处理';
  }

  @Builder
  private statusMark(item: NativePlanItem) {
    Stack() {
      if (item.status === 'completed') {
        DSHIcon({ glyph: 'check-outline', glyphSize: 9,
          color: this.dark ? '#9BE2B0' : '#187940' })
      } else if (item.status === 'in_progress') {
        Text('●').fontSize(8)
          .fontColor(this.dark ? '#8AB4FF' : '#3964FE')
      } else {
        Text('○').fontSize(12)
          .fontColor(this.dark ? '#63666B' : '#B8BBC0')
      }
    }.width(16).height(16)
  }

  build() {
    Column({ space: 5 }) {
      if (this.showHeader) {
        Row({ space: 7 }) {
          DSHIcon({ glyph: 'plan-outline', glyphSize: 15,
            color: this.dark ? '#93969B' : '#777A80' })
          Text('任务计划').fontSize(12).fontWeight(FontWeight.Medium)
            .fontColor(this.dark ? '#E7E7E9' : '#202124')
          Text(nativePlanProgress(this.document)).fontSize(11).layoutWeight(1).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor(this.dark ? '#93969B' : '#777A80')
        }.width('100%')
        Divider().color(this.dark ? '#353538' : '#E5E6E8')
      }
      Column({ space: 5 }) {
        ForEach(this.document.items, (item: NativePlanItem, index: number) => {
          Row({ space: 7 }) {
            this.statusMark(item)
            Text(item.content).fontSize(11).lineHeight(16).layoutWeight(1)
              .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontColor(item.status === 'completed' ?
                (this.dark ? '#AEB1B5' : '#6A6E73') :
                (this.dark ? '#D7D9DC' : '#363A3F'))
          }.width('100%').alignItems(VerticalAlign.Top)
            .accessibilityText(this.statusLabel(item.status) + '：' + item.content)
        }, (item: NativePlanItem, index: number) =>
          index.toString() + ':' + item.status + ':' + item.content)
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
