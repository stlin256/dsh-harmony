import { WidgetLinkParams } from '../WidgetLinkParams';

@Entry
@Component
struct QuickCard {
  @LocalStorageProp('headline') headline: string = '连接工作空间';
  @LocalStorageProp('detail') detail: string = '打开应用开始连接';
  @LocalStorageProp('stamp') stamp: string = '尚未同步';
  @LocalStorageProp('showCounts') showCounts: boolean = false;
  @LocalStorageProp('waiting') waiting: string = '—';
  @LocalStorageProp('running') running: string = '—';
  @LocalStorageProp('primarySessionId') primarySessionId: string = '';

  build() {
    FormLink({ action: 'router', abilityName: 'EntryAbility',
      params: new WidgetLinkParams(this.primarySessionId, this.primarySessionId ? '' : 'workspace') }) {
      Column({ space: 6 }) {
        Row() {
          Image($r('app.media.app_icon')).width(26).height(26).borderRadius(8)
          Blank()
          Text(this.showCounts ? this.waiting : '↗').fontSize(this.showCounts ? 20 : 18)
            .fontWeight(this.showCounts ? FontWeight.Medium : FontWeight.Normal)
            .fontColor($r('app.color.widget_primary'))
        }.width('100%')
        Blank()
        Text(this.showCounts ? (this.waiting !== '0' && this.waiting !== '—' ? this.waiting + ' 个待确认' :
          this.running === '—' ? this.headline : this.running + ' 个运行中') : this.headline)
          .fontSize(18).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.widget_primary')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.detail).fontSize(11).fontColor($r('app.color.widget_secondary'))
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('DSH Harmony').fontSize(10).fontColor($r('app.color.widget_secondary'))
      }.width('100%').height('100%').padding(16).alignItems(HorizontalAlign.Start)
        .backgroundColor($r('app.color.widget_background')).borderRadius(24)
    }.width('100%').height('100%').accessibilityText('DSH Harmony，' + this.headline + '，打开工作空间')
  }
}
