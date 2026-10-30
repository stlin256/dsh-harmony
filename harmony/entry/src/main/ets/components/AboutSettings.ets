import { common } from '@kit.AbilityKit';
import { BuildInfo } from '../services/BuildInfo';
import { NativeExperience } from '../services/NativeExperience';
import { NativeMotion } from '../services/NativeMotion';
import { DSHIcon } from './DSHIcon';

@Component
export struct AboutSettings {
  @Prop embedded: boolean = false;
  onBack: () => void = (): void => {};
  @StorageLink('nativeDark') private dark: boolean = false;
  @StorageLink('nativeSafeBottom') private safeBottom: number = 0;
  @State private status: string = '';
  private context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;

  private open(url: string): void {
    this.context.startAbility({
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    }).catch(() => { this.status = '无法打开链接'; });
  }

  build() {
    Scroll() {
      Column({ space: 13 }) {
        if (!this.embedded) {
        Row({ space: 8 }) {
          Button({ type: ButtonType.Normal }) { DSHIcon({ glyph: 'chevron-left-outline', color: this.dark ? '#F9FAFB' : '#33353A' }) }
            .width(38).height(38).borderRadius(12).backgroundColor(Color.Transparent)
            .accessibilityText('返回设置').onClick(this.onBack)
          Column({ space: 2 }) {
            Text('关于').fontSize(19).fontWeight(FontWeight.Medium)
              .fontColor(this.dark ? '#F9FAFB' : '#17181B')
            Text('DSH Harmony').fontSize(11).fontColor(this.dark ? '#929298' : '#888B91')
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        }.width('100%')
        }
        Column({ space: 8 }) {
          Image($r('app.media.app_icon')).width(72).height(72).borderRadius(18)
          Text(BuildInfo.appName).fontSize(20).fontWeight(FontWeight.Medium)
            .fontColor(this.dark ? '#F9FAFB' : '#17181B')
          Text('版本 ' + BuildInfo.version + ' · HarmonyOS').fontSize(12)
            .fontColor(this.dark ? '#A1A1AA' : '#777A80')
        }.width('100%').alignItems(HorizontalAlign.Center).padding({ top: 24, bottom: 24 })
          .borderRadius(18).backgroundColor(this.dark ? '#222225' : '#FFFFFF')
          .border({ width: 1, color: this.dark ? '#353538' : '#E8E9EC' })
        Column({ space: 10 }) {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 12 }) {
              Image($rawfile('maintainer-avatar.png')).width(48).height(48).borderRadius(24).objectFit(ImageFit.Cover)
              Column({ space: 3 }) {
                Text(BuildInfo.author).fontSize(15).fontWeight(FontWeight.Medium)
                  .fontColor(this.dark ? '#F9FAFB' : '#0F1115')
                Text('github.com/' + BuildInfo.author).fontSize(12)
                  .fontColor(this.dark ? '#8AB4FF' : '#3964FE')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Text('↗').fontSize(16).fontColor(this.dark ? '#929298' : '#888B91')
            }.width('100%')
          }.width('100%').constraintSize({ minHeight: 76 }).padding(14).borderRadius(16)
            .backgroundColor(this.dark ? '#222225' : '#FFFFFF')
            .border({ width: 1, color: this.dark ? '#353538' : '#E8E9EC', radius: 14 }).clip(true)
            .accessibilityText('打开作者 ' + BuildInfo.author + ' 的 GitHub 主页')
            .onClick(() => this.open(BuildInfo.authorProfile))
          Button({ type: ButtonType.Normal }) {
            Row() {
              Column({ space: 3 }) {
                Text('项目仓库').fontSize(13).fontWeight(FontWeight.Medium)
                  .fontColor(this.dark ? '#E7E7E9' : '#25262A')
                Text('github.com/stlin256/DSH-Harmony').fontSize(11).fontColor(this.dark ? '#929298' : '#888B91')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Text('↗').fontSize(16).fontColor(this.dark ? '#929298' : '#888B91')
            }.width('100%')
          }.width('100%').constraintSize({ minHeight: 58 }).padding({ left: 14, right: 14, top: 10, bottom: 10 }).borderRadius(14)
            .backgroundColor(this.dark ? '#222225' : '#FFFFFF')
            .border({ width: 1, color: this.dark ? '#353538' : '#E8E9EC', radius: 14 }).clip(true)
            .onClick(() => this.open(BuildInfo.repository))
          Button({ type: ButtonType.Normal }) {
            Row() {
              Column({ space: 3 }) {
                Text('报告问题').fontSize(13).fontWeight(FontWeight.Medium)
                  .fontColor(this.dark ? '#E7E7E9' : '#25262A')
                Text('在 GitHub Issues 提交反馈').fontSize(11).fontColor(this.dark ? '#929298' : '#888B91')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Text('↗').fontSize(16).fontColor(this.dark ? '#929298' : '#888B91')
            }.width('100%')
          }.width('100%').constraintSize({ minHeight: 58 }).padding({ left: 14, right: 14, top: 10, bottom: 10 }).borderRadius(14)
            .backgroundColor(this.dark ? '#222225' : '#FFFFFF')
            .border({ width: 1, color: this.dark ? '#353538' : '#E8E9EC', radius: 14 }).clip(true)
            .onClick(() => this.open(BuildInfo.issues))
        }.width('100%')
        Text(BuildInfo.copyright + ' · AGPL-3.0-only').fontSize(11).lineHeight(18)
          .width('100%').textAlign(TextAlign.Center).padding({ top: 3, bottom: 3 })
          .fontColor(this.dark ? '#85858B' : '#92959A')
        if (this.status) {
          Text(this.status).fontSize(12).fontColor(this.dark ? '#A1A1AA' : '#74777D')
            .width('100%').textAlign(TextAlign.Center).transition(TransitionEffect.OPACITY)
        }
      }.padding({ left: 16, right: 16, top: 12, bottom: this.safeBottom + 24 }).width('100%')
        .constraintSize({ maxWidth: 560 }).alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').align(Alignment.TopStart).backgroundColor(this.dark ? '#171719' : '#F5F6F8')
      .transition(NativeMotion.navigationTransition())
  }
}
