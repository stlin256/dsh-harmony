import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { BuildInfo } from '../services/BuildInfo';
import { NativeExperience } from '../services/NativeExperience';
import { NativeLaunchPhase } from '../services/NativeLaunchFlow';
import { NativeMotion } from '../services/NativeMotion';
import { DSHIcon } from './DSHIcon';

@Component
export struct NativeLaunchSurface {
  @Prop phase: string = NativeLaunchPhase.booting;
  @Prop address: string = '';
  @Prop accessKey: string = '';
  @Prop mode: string = 'native';
  @Prop showPasskey: boolean = false;
  @Prop busy: boolean = false;
  @Prop errorText: string = '';
  onAddressChange: (value: string) => void = (): void => {};
  onAccessKeyChange: (value: string) => void = (): void => {};
  onModeChange: (value: string) => void = (): void => {};
  onConnect: () => void = (): void => {};
  onOpenGuide: () => void = (): void => {};
  onCloseGuide: () => void = (): void => {};
  onOpenInstall: () => void = (): void => {};
  onCloseInstall: () => void = (): void => {};
  onDirect: () => void = (): void => {};
  onEditAddress: () => void = (): void => {};
  onRetry: () => void = (): void => {};
  @StorageLink('nativeDark') private dark: boolean = false;
  @StorageLink('nativeSafeTop') private safeTop: number = 0;
  @StorageLink('nativeSafeBottom') private safeBottom: number = 0;
  @StorageLink('nativeSafeLeft') private safeLeft: number = 0;
  @StorageLink('nativeSafeRight') private safeRight: number = 0;
  @State private viewportWidth: number = 360;
  @State private viewportHeight: number = 760;
  @State private brandScale: number = 0.88;
  @State private copied: string = '';
  @State private status: string = '';
  private context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;

  aboutToAppear(): void {
    NativeMotion.spring(this.getUIContext(), (): void => { this.brandScale = 1; });
  }

  private primary(): string {
    return this.dark ? '#8AB4FF' : '#3964FE';
  }

  private foreground(): string {
    return this.dark ? '#F6F7F9' : '#17181B';
  }

  private secondary(): string {
    return this.dark ? '#A4A7AD' : '#6E737A';
  }

  private surface(): string {
    return this.dark ? '#202124' : '#FFFFFF';
  }

  private raised(): string {
    return this.dark ? '#292A2E' : '#F1F3F6';
  }

  private subtleStroke(): string {
    return this.dark ? '#383A3F' : '#E3E5E9';
  }

  private logoSize(): number {
    return this.viewportWidth < 360 ? 80 : 92;
  }

  private cornerLogoX(): number {
    return Math.max(12, this.viewportWidth - 174);
  }

  private cornerLogoY(): number {
    return Math.max(this.safeTop + 620, this.viewportHeight - this.safeBottom - 430);
  }

  private logoX(): number {
    if (this.phase === NativeLaunchPhase.guide || this.phase === NativeLaunchPhase.install) {
      return this.cornerLogoX() + 26;
    }
    return Math.max(12, (this.viewportWidth - this.logoSize()) / 2);
  }

  private logoY(): number {
    if (this.phase === NativeLaunchPhase.guide || this.phase === NativeLaunchPhase.install) {
      return this.cornerLogoY() + 26;
    }
    if (this.phase === NativeLaunchPhase.login || this.phase === NativeLaunchPhase.restoring ||
      this.phase === NativeLaunchPhase.error) return this.safeTop + 68;
    return Math.max(this.safeTop + 72, Math.min(210, this.viewportHeight * 0.2));
  }

  private logoOpacity(): number {
    if (this.phase === NativeLaunchPhase.guide || this.phase === NativeLaunchPhase.install) return 0;
    if (this.phase === NativeLaunchPhase.login || this.phase === NativeLaunchPhase.restoring ||
      this.phase === NativeLaunchPhase.error) return 1;
    return this.phase === NativeLaunchPhase.booting ? this.brandScale : 1;
  }

  private async copy(value: string, key: string): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value));
      this.copied = key;
      this.status = '';
      setTimeout((): void => { this.copied = ''; }, 1400);
    } catch (_) {
      this.status = '复制失败';
    }
  }

  private open(url: string): void {
    this.context.startAbility({
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    }).catch((): void => { this.status = '无法打开链接'; });
  }

  @Builder
  private iconButton(glyph: string, label: string, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      DSHIcon({ glyph, glyphSize: 18, color: this.foreground() })
    }
    .width(40).height(40).borderRadius(13)
    .backgroundColor(this.raised())
    .accessibilityText(label)
    .onClick(action)
  }

  @Builder
  private primaryButton(label: string, loading: boolean, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 8 }) {
        if (loading) LoadingProgress().width(17).height(17).color(this.dark ? '#17181B' : '#FFFFFF')
        Text(loading ? '正在连接' : label).fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor(this.dark ? '#17181B' : '#FFFFFF')
      }
    }
    .width('100%').height(48).borderRadius(14)
    .backgroundColor(this.dark ? '#F6F7F9' : '#17181B')
    .enabled(!loading)
    .onClick(action)
  }

  @Builder
  private secondaryButton(label: string, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Text(label).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.foreground())
    }
      .width('100%').height(48).borderRadius(14)
      .backgroundColor(this.raised())
      .onClick(action)
  }

  @Builder
  private welcome() {
    Column({ space: 12 }) {
      Text('DSH Harmony').fontSize(30).fontWeight(FontWeight.Bold).fontColor(this.foreground())
      Text('把 DeepSeek Harness 带到你的手机上').fontSize(14).fontColor(this.secondary())
      Blank()
      if (this.phase === NativeLaunchPhase.booting) {
        Row({ space: 8 }) {
          LoadingProgress().width(15).height(15).color(this.primary())
          Text('正在准备') .fontSize(12).fontColor(this.secondary())
        }.opacity(0.85)
      } else {
        this.primaryButton('开始引导', false, this.onOpenGuide)
        this.secondaryButton('直接进入', this.onDirect)
      }
    }
    .width('100%').height('100%')
    .padding({
      left: 28 + this.safeLeft,
      right: 28 + this.safeRight,
      top: Math.max(this.safeTop + 235, this.viewportHeight * 0.345),
      bottom: this.safeBottom + 30
    })
    .constraintSize({ maxWidth: 520 })
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 8 }))
      .animation(NativeMotion.implicit('surface')))
  }

  @Builder
  private guideStep(index: string, glyph: string, title: string, detail: string) {
    Row({ space: 13 }) {
      Stack({ alignContent: Alignment.Center }) {
        Column().width(40).height(40).borderRadius(20)
          .backgroundColor(this.dark ? '#2D3035' : '#EBEFF5')
        DSHIcon({ glyph, glyphSize: 19, color: this.primary() })
      }.width(40).height(40)
      Column({ space: 2 }) {
        Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.foreground())
        Text(detail).fontSize(12).lineHeight(18).fontColor(this.secondary())
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text(index).fontSize(10).fontWeight(FontWeight.Medium).fontColor(this.secondary())
    }
    .width('100%').padding({ top: 10, bottom: 10 })
    .transition(NativeMotion.navigationTransition())
  }

  @Builder
  private guide() {
    Column() {
      Row({ space: 10 }) {
        this.iconButton('chevron-left-outline', '返回欢迎页', this.onCloseGuide)
        Column({ space: 1 }) {
          Text('连接 DSH').fontSize(21).fontWeight(FontWeight.Bold).fontColor(this.foreground())
          Text('三步完成准备').fontSize(12).fontColor(this.secondary())
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%')
      Scroll() {
        Column({ space: 10 }) {
          Column() {
            this.guideStep('01', 'globe-outline', '打开 DSH 插件', '在侧边栏进入“插件”')
            Divider().strokeWidth(0.5).margin({ left: 53 }).color(this.subtleStroke())
            this.guideStep('02', 'download-outline', '安装 DSH Harmony 插件', '粘贴安装提示词并启用')
            Divider().strokeWidth(0.5).margin({ left: 53 }).color(this.subtleStroke())
            this.guideStep('03', 'check-outline', '连接工作空间', '返回 App，选择登录方式')
          }.width('100%').padding({ left: 14, right: 14 })
            .borderRadius(18).backgroundColor(this.surface())
            .border({ width: 1, color: this.subtleStroke() })
          Button({ type: ButtonType.Normal }) {
            Row({ space: 12 }) {
              Stack({ alignContent: Alignment.Center }) {
                Column().width(36).height(36).borderRadius(18)
                  .backgroundColor(this.dark ? '#25334E' : '#EAF0FF')
                DSHIcon({ glyph: 'copy-outline', glyphSize: 17, color: this.primary() })
              }
              Column({ space: 3 }) {
                Text('复制安装提示词').fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.foreground())
                Text('发送给 DSH 即可继续').fontSize(11).fontColor(this.secondary())
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              DSHIcon({ glyph: this.copied === 'prompt' ? 'check-outline' : 'copy-outline',
                glyphSize: 16, color: this.copied === 'prompt' ? this.primary() : this.secondary() })
            }.width('100%')
          }
          .width('100%').constraintSize({ minHeight: 62 }).padding({ left: 12, right: 12 })
          .borderRadius(16).backgroundColor(this.surface()).border({ width: 1, color: this.subtleStroke() })
          .accessibilityText('复制 DSH Harmony 插件安装提示词')
          .onClick((): void => { this.copy(BuildInfo.pluginInstallPrompt, 'prompt'); })
          Row({ space: 8 }) {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 7 }) {
                DSHIcon({ glyph: 'branch-outline', glyphSize: 15, color: this.secondary() })
                Text('打开仓库').fontSize(12).fontColor(this.foreground())
              }
            }.layoutWeight(1).height(42).borderRadius(12).backgroundColor(this.raised())
              .onClick((): void => { this.open(BuildInfo.repository); })
            Button({ type: ButtonType.Normal }) {
              Text('详细安装说明').fontSize(12).fontColor(this.foreground())
            }.layoutWeight(1).height(42).borderRadius(12).backgroundColor(this.raised())
              .onClick(this.onOpenInstall)
          }.width('100%')
        }.width('100%').padding({ top: 20, bottom: 16 })
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
        .align(Alignment.Top)
      this.primaryButton('继续登录', false, this.onDirect)
      if (this.status) {
        Text(this.status).fontSize(11).fontColor(this.secondary()).margin({ top: 6 })
      }
    }
    .width('100%').height('100%')
    .padding({ left: 18 + this.safeLeft, right: 18 + this.safeRight,
      top: this.safeTop + 12, bottom: this.safeBottom + 18 })
    .constraintSize({ maxWidth: 560 })
    .transition(NativeMotion.navigationTransition())
  }

  @Builder
  private installDetailRow(glyph: string, title: string, detail: string, badge: string) {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        Column().width(38).height(38).borderRadius(19)
          .backgroundColor(this.dark ? '#25334E' : '#EAF0FF')
        DSHIcon({ glyph, glyphSize: 18, color: this.primary() })
      }.width(38).height(38)
      Column({ space: 3 }) {
        Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.foreground())
        Text(detail).fontSize(11).lineHeight(17).fontColor(this.secondary())
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text(badge).fontSize(10).fontWeight(FontWeight.Medium)
        .fontColor(this.primary()).padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .borderRadius(8).backgroundColor(this.dark ? '#25334E' : '#EAF0FF')
    }
    .width('100%').padding({ top: 12, bottom: 12 })
  }

  @Builder
  private detailCopyAction(title: string, detail: string, glyph: string, key: string, value: string) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        Stack({ alignContent: Alignment.Center }) {
          Column().width(38).height(38).borderRadius(19)
            .backgroundColor(this.dark ? '#25334E' : '#EAF0FF')
          DSHIcon({ glyph, glyphSize: 18, color: this.primary() })
        }.width(38).height(38)
        Column({ space: 3 }) {
          Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.foreground())
          Text(detail).fontSize(11).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor(this.secondary())
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        DSHIcon({ glyph: this.copied === key ? 'check-outline' : 'copy-outline',
          glyphSize: 16, color: this.copied === key ? this.primary() : this.secondary() })
      }.width('100%')
    }
    .width('100%').constraintSize({ minHeight: 62 }).padding({ left: 13, right: 13 })
    .borderRadius(15).backgroundColor(this.surface()).border({ width: 1, color: this.subtleStroke() })
    .accessibilityText(title)
    .onClick((): void => { this.copy(value, key); })
  }

  @Builder
  private detailSectionTitle(title: string, caption: string) {
    Row() {
      Column({ space: 2 }) {
        Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.foreground())
        Text(caption).fontSize(11).fontColor(this.secondary())
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').padding({ top: 4, bottom: 2 })
  }

  @Builder
  private installDetails() {
    Column() {
      Row({ space: 10 }) {
        this.iconButton('chevron-left-outline', '返回连接引导', this.onCloseInstall)
        Column({ space: 1 }) {
          Text('详细安装说明').fontSize(21).fontWeight(FontWeight.Bold).fontColor(this.foreground())
          Text('两种安装方式 · 一次版本核对').fontSize(12).fontColor(this.secondary())
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text(BuildInfo.pluginArtifactVersion).fontSize(10).fontWeight(FontWeight.Medium)
          .fontColor(this.secondary()).padding({ left: 9, right: 9, top: 5, bottom: 5 })
          .borderRadius(9).backgroundColor(this.raised())
      }.width('100%')
      Scroll() {
        Column({ space: 12 }) {
          Stack({ alignContent: Alignment.Center }) {
            Image($rawfile('install-plugin-abstract.svg'))
              .width('100%').height(142).objectFit(ImageFit.Contain).opacity(0.96)
          }
          .width('100%').height(154).borderRadius(18)
          .backgroundColor(this.dark ? '#182338' : '#EEF3FF')
          Column({ space: 8 }) {
            this.detailSectionTitle('交给 DSH 自动安装', '推荐 · Agent 会完成下载、启用与版本检查')
            this.detailCopyAction('复制安装提示词', '发送给 DSH Agent', 'agent-preset-outline',
              'detail-prompt', BuildInfo.pluginInstallPrompt)
          }.width('100%').alignItems(HorizontalAlign.Start)
          Column({ space: 8 }) {
            this.detailSectionTitle('手动安装', '适合直接操作 DSH 插件管理器的用户')
            Text('打开 插件 → Add plugin，粘贴安装地址并启用。')
              .fontSize(11).lineHeight(17).fontColor(this.secondary()).width('100%')
            this.detailCopyAction('复制插件安装地址', BuildInfo.pluginArtifactVersion,
              'download-outline', 'detail-artifact', BuildInfo.pluginArtifact)
          }.width('100%').alignItems(HorizontalAlign.Start)
          Column({ space: 8 }) {
            this.detailSectionTitle('确认安装结果', '回到 App 前完成这两项')
            Column() {
              this.installDetailRow('api-outline', '插件已启用', '@dsh-harmony/plugin', '01')
              Divider().strokeWidth(0.5).margin({ left: 50 }).color(this.subtleStroke())
              this.installDetailRow('check-outline', '版本匹配', BuildInfo.pluginArtifactVersion, '02')
            }.width('100%').padding({ left: 14, right: 14 })
              .borderRadius(16).backgroundColor(this.surface())
              .border({ width: 1, color: this.subtleStroke() })
          }.width('100%').alignItems(HorizontalAlign.Start)
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              DSHIcon({ glyph: 'question-outline', glyphSize: 14, color: this.secondary() })
              Text('常见问题').fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.foreground())
            }.width('100%')
            Text('请安装 Release 中的 .tgz，不要把 plugins/dsh-harmony 源码目录直接作为 Git 插件。升级 App 时使用对应的插件版本。')
              .fontSize(11).lineHeight(17).fontColor(this.secondary()).width('100%')
          }.width('100%').padding(13).borderRadius(14).backgroundColor(this.raised())
          if (this.status) {
            Text(this.status).fontSize(11).fontColor(this.secondary())
          }
        }.width('100%').padding({ top: 18, bottom: 16 })
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
        .align(Alignment.Top)
      this.primaryButton('返回连接', false, this.onCloseInstall)
    }
    .width('100%').height('100%')
    .padding({ left: 18 + this.safeLeft, right: 18 + this.safeRight,
      top: this.safeTop + 12, bottom: this.safeBottom + 18 })
    .constraintSize({ maxWidth: 560 })
    .transition(NativeMotion.navigationTransition())
  }

  @Builder
  private formLabel(value: string) {
    Text(value).fontSize(11).fontWeight(FontWeight.Medium)
      .fontColor(this.secondary()).padding({ left: 2 })
  }

  @Builder
  private modeButton(label: string, detail: string, value: string) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text(label).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.foreground())
          if (detail) Text(detail).fontSize(10).fontColor(this.secondary())
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (this.mode === value) {
          DSHIcon({ glyph: 'check-outline', glyphSize: 15, color: this.primary() })
        }
      }.width('100%').padding({ left: 13, right: 13 })
    }
    .width('100%').constraintSize({ minHeight: 50 }).borderRadius(13)
    .backgroundColor(this.mode === value ? this.dark ? '#22314B' : '#EAF0FF' : this.raised())
    .border({ width: 1, color: this.mode === value ? this.primary() : this.subtleStroke() })
    .onClick((): void => { this.onModeChange(value); })
  }

  @Builder
  private loginCard() {
    Column({ space: 13 }) {
      Row({ space: 8 }) {
        this.iconButton('chevron-left-outline', '返回欢迎页', this.onEditAddress)
        Column({ space: 2 }) {
          Text('连接工作空间').fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.foreground())
          Text('登录你的 DeepSeek Harness').fontSize(12).fontColor(this.secondary())
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%')
      Column({ space: 7 }) {
        this.formLabel('服务地址')
        TextInput({ text: this.address, placeholder: 'https://dsh.example.com' })
          .height(48).borderRadius(13).type(InputType.URL)
          .backgroundColor(this.raised()).fontColor(this.foreground())
          .placeholderColor(this.secondary())
          .border({ width: 1, color: this.subtleStroke() })
          .onChange((value: string): void => { this.onAddressChange(value); })
      }.width('100%').alignItems(HorizontalAlign.Start)
      Column({ space: 8 }) {
        this.formLabel('登录方式')
        this.modeButton('访问密钥', '默认 · 局域网与公网', 'native')
        if (this.mode === 'native') {
          TextInput({ text: this.accessKey, placeholder: '输入 Harness 访问密钥' })
            .height(46).borderRadius(13).type(InputType.Password)
            .backgroundColor(this.raised()).fontColor(this.foreground())
            .placeholderColor(this.secondary())
            .border({ width: 1, color: this.subtleStroke() })
            .onChange((value: string): void => { this.onAccessKeyChange(value); })
        }
        if (this.showPasskey) {
          this.modeButton('Pocket ID · Passkey', '需要 HTTPS', 'passkey')
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
      if (this.errorText) {
        Row({ space: 10 }) {
          Column({ space: 3 }) {
            Text('登录失败').fontSize(12).fontWeight(FontWeight.Medium)
              .fontColor(this.dark ? '#FFB4B4' : '#B83A3A')
            Text(this.errorText).fontSize(11).lineHeight(17).maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontColor(this.dark ? '#E3B6B6' : '#874242')
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          this.iconButton(this.copied === 'error' ? 'check-outline' : 'copy-outline', '复制错误',
            (): void => { this.copy(this.errorText, 'error'); })
        }
        .width('100%').padding(10).borderRadius(13)
        .backgroundColor(this.dark ? '#392326' : '#FFF1F1')
        .border({ width: 1, color: this.dark ? '#5B3237' : '#F0CFD1' })
      }
      this.primaryButton('连接工作空间', this.busy, this.onConnect)
    }
    .width('100%').padding(18).borderRadius(22)
    .backgroundColor(this.surface()).border({ width: 1, color: this.subtleStroke() })
    .shadow({ radius: NativeExperience.materialsEnabled() ? 22 : 0,
      color: this.dark ? '#55000000' : '#16000000', offsetY: 8 })
    .constraintSize({ maxWidth: 500 })
  }

  @Builder
  private connectionProgressSurface() {
    Column({ space: 22 }) {
      Image($r('app.media.app_icon'))
        .width(64).height(64).objectFit(ImageFit.Contain).opacity(0.38)
      LoadingProgress().width(24).height(24).color(this.primary())
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
    .padding({ bottom: this.safeBottom })
    .transition(TransitionEffect.OPACITY.animation(NativeMotion.implicit('surface')))
  }

  @Builder
  private errorCard() {
    Column({ space: 14 }) {
      Row({ space: 8 }) {
        this.iconButton('chevron-left-outline', '返回登录', this.onEditAddress)
        Column({ space: 2 }) {
          Text('连接失败').fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.foreground())
          Text(this.address).fontSize(11).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor(this.secondary())
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%')
      Text(this.errorText).fontSize(13).lineHeight(20).fontColor(this.secondary())
        .width('100%').padding(13).borderRadius(13).backgroundColor(this.raised())
      Row({ space: 8 }) {
        this.iconButton(this.copied === 'error' ? 'check-outline' : 'copy-outline', '复制错误',
          (): void => { this.copy(this.errorText, 'error'); })
        Text(this.copied === 'error' ? '错误已复制' : '复制错误')
          .fontSize(12).fontColor(this.secondary()).layoutWeight(1)
      }.width('100%')
      this.primaryButton('重试', this.busy, this.onRetry)
      this.secondaryButton('修改地址', this.onEditAddress)
    }
    .width('100%').padding(18).borderRadius(22).backgroundColor(this.surface())
    .border({ width: 1, color: this.subtleStroke() })
    .constraintSize({ maxWidth: 500 })
  }

  @Builder
  private accountSurface() {
    Scroll() {
      Column() {
        if (this.phase === NativeLaunchPhase.error) this.errorCard()
        else this.loginCard()
      }
      .width('100%').padding({ left: 18 + this.safeLeft, right: 18 + this.safeRight,
        top: this.safeTop + 144, bottom: this.safeBottom + 24 })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%').height('100%').scrollBar(BarState.Off)
    .align(Alignment.Top)
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 8 }))
      .animation(NativeMotion.implicit('surface')))
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column().width('100%').height('100%')
        .linearGradient({
          angle: 160,
          colors: this.dark
            ? [['#151517', 0.0], ['#1A1B1F', 0.58], ['#141619', 1.0]]
            : [['#FFFFFF', 0.0], ['#F7F9FC', 0.58], ['#F0F4FB', 1.0]]
        })
      Column().width(260).height(260).borderRadius(130)
        .backgroundColor(this.dark ? '#101C32' : '#EAF1FF').opacity(0.62)
        .position({ x: this.viewportWidth - 176, y: -84 })
      Column().width(190).height(190).borderRadius(95)
        .backgroundColor(this.dark ? '#13221F' : '#EAF8F5').opacity(0.45)
        .position({ x: -78, y: this.viewportHeight * 0.56 })
      if (this.phase !== NativeLaunchPhase.restoring &&
        this.phase !== NativeLaunchPhase.entering) {
        Image($r('app.media.app_icon'))
          .width(this.logoSize()).height(this.logoSize())
          .objectFit(ImageFit.Contain)
          .position({ x: this.logoX(), y: this.logoY() })
          .opacity(this.logoOpacity())
          .accessibilityLevel('no')
      }
      Image($r('app.media.app_icon'))
        .width(144).height(144).objectFit(ImageFit.Contain)
        .position({ x: this.cornerLogoX(), y: this.cornerLogoY() })
        .opacity(this.phase === NativeLaunchPhase.guide || this.phase === NativeLaunchPhase.install
          ? 0.10 : 0)
        .animation(NativeMotion.implicit('brand'))
        .accessibilityLevel('no')
      if (this.phase === NativeLaunchPhase.booting || this.phase === NativeLaunchPhase.intro) {
        this.welcome()
      } else if (this.phase === NativeLaunchPhase.guide) {
        this.guide()
      } else if (this.phase === NativeLaunchPhase.install) {
        this.installDetails()
      } else if (this.phase === NativeLaunchPhase.restoring ||
        this.phase === NativeLaunchPhase.entering) {
        this.connectionProgressSurface()
      } else {
        this.accountSurface()
      }
    }
    .width('100%').height('100%')
    .clip(true)
    .onAreaChange((_old: Area, area: Area): void => {
      if (Number(area.width) > 0) this.viewportWidth = Number(area.width);
      if (Number(area.height) > 0) this.viewportHeight = Number(area.height);
    })
  }
}
