@Entry
@Component
struct QuickCard {
  @LocalStorageProp('headline') headline: string = '连接工作空间';
  @LocalStorageProp('detail') detail: string = '打开应用开始连接';
  @LocalStorageProp('stamp') stamp: string = '尚未同步';

  build() {
    FormLink({ action: 'router', abilityName: 'EntryAbility', params: { pocketRoute: 'workspace' } }) {
      Column({ space: 8 }) {
        Row() {
          Image($r('app.media.app_icon')).width(26).height(26).borderRadius(8)
          Blank()
          Text('↗').fontSize(18).fontColor($r('app.color.widget_secondary'))
        }.width('100%')
        Blank()
        Text(this.headline).fontSize(18).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.widget_primary')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.detail).fontSize(11).fontColor($r('app.color.widget_secondary'))
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('DSH Pocket').fontSize(10).fontColor($r('app.color.widget_secondary'))
      }.width('100%').height('100%').padding(16).alignItems(HorizontalAlign.Start)
        .backgroundColor($r('app.color.widget_background')).borderRadius(24)
    }.width('100%').height('100%').accessibilityText('DSH Pocket，' + this.headline + '，打开工作空间')
  }
}
