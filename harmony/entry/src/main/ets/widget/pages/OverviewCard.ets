@Entry
@Component
struct OverviewCard {
  @LocalStorageProp('headline') headline: string = '连接工作空间';
  @LocalStorageProp('detail') detail: string = '打开应用开始连接';
  @LocalStorageProp('stamp') stamp: string = '尚未同步';
  @LocalStorageProp('showCounts') showCounts: boolean = false;
  @LocalStorageProp('running') running: string = '—';
  @LocalStorageProp('waiting') waiting: string = '—';
  @LocalStorageProp('completed') completed: string = '—';
  @LocalStorageProp('failed') failed: string = '—';

  @Builder
  metric(value: string, label: string) {
    Column({ space: 2 }) {
      Text(value).fontSize(22).fontWeight(FontWeight.Medium).fontColor($r('app.color.widget_primary'))
      Text(label).fontSize(10).fontColor($r('app.color.widget_secondary'))
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 6 }) {
      Row() {
        Text('DSH Harmony').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.widget_primary'))
        Blank()
        Text(this.stamp).fontSize(10).fontColor($r('app.color.widget_secondary')).maxLines(1)
      }.width('100%')
      if (this.showCounts) {
        Row() {
          this.metric(this.running, '运行中')
          this.metric(this.waiting, '待审批')
          this.metric(this.completed, '近期完成')
          this.metric(this.failed, '近期失败')
        }.width('100%').layoutWeight(1)
      } else {
        Text(this.headline).fontSize(20).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.widget_primary')).layoutWeight(1).maxLines(2)
      }
      Text(this.detail).fontSize(10).fontColor($r('app.color.widget_secondary')).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Row({ space: 8 }) {
        FormLink({ action: 'router', abilityName: 'EntryAbility', params: { pocketRoute: 'workspace' } }) {
          Text('打开工作空间').fontSize(12).fontColor($r('app.color.widget_primary'))
            .width('100%').height(44).textAlign(TextAlign.Center)
            .backgroundColor($r('app.color.widget_action')).borderRadius(12)
        }.layoutWeight(1).accessibilityText('打开 Harness 工作空间')
        FormLink({ action: 'router', abilityName: 'EntryAbility', params: { pocketRoute: 'overview' } }) {
          Text('同步状态').fontSize(12).fontColor($r('app.color.widget_primary'))
            .width('100%').height(44).textAlign(TextAlign.Center)
            .backgroundColor($r('app.color.widget_action')).borderRadius(12)
        }.layoutWeight(1).accessibilityText('打开应用并同步任务状态')
      }.width('100%')
    }.width('100%').height('100%').padding(12).alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.widget_background')).borderRadius(24)
  }
}
