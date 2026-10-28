import { http } from '@kit.NetworkKit';
import { NativeHarnessClient } from '../services/NativeHarnessClient';
import { NativeExperience } from '../services/NativeExperience';
import { AboutSettings } from './AboutSettings';

class NotificationPreferences {
  completed: boolean = true;
  failed: boolean = true;
  approval: boolean = true;
}

class PushDeviceRegistration {
  id: string = '';
  token: string = '';
  notifications: NotificationPreferences = new NotificationPreferences();
}

class SettingsState {
  themeMode: string = 'system';
  reduceMotion: boolean = false;
  reduceTransparency: boolean = false;
  widgetDetails: boolean = true;
  supportsPush: boolean = true;
  pushEnabled: boolean = false;
  backgroundMonitor: boolean = false;
  notifyCompleted: boolean = true;
  notifyFailed: boolean = true;
  notifyApproval: boolean = true;
}

@Component
export struct NativeSettings {
  client: NativeHarnessClient = new NativeHarnessClient('');
  invoke: (command: string, value: string) => Promise<string> = async (): Promise<string> => '';
  onReturn: () => void = (): void => {};
  onModes: () => void = (): void => {};
  onConnection: () => void = (): void => {};
  onLogin: () => void = (): void => {};
  onLogout: () => Promise<void> = async (): Promise<void> => {};
  @StorageLink('nativeAppActive') @Watch('activityChanged') private active: boolean = true;
  @StorageLink('nativeDark') private dark: boolean = false;
  @State private themeMode: string = 'system';
  @State private reduceMotion: boolean = false;
  @State private reduceTransparency: boolean = false;
  @State private widgetDetails: boolean = true;
  @State private supportsPush: boolean = true;
  @State private pushEnabled: boolean = false;
  @State private backgroundMonitor: boolean = false;
  @State private notifyCompleted: boolean = true;
  @State private notifyFailed: boolean = true;
  @State private notifyApproval: boolean = true;
  @State private aboutOpen: boolean = false;
  @State private busy: boolean = true;
  @State private status: string = '';
  private mounted: boolean = false;
  private widgetTimer: number = -1;

  aboutToAppear(): void {
    this.mounted = true;
    this.initialize().catch(() => { this.status = '读取设置失败'; this.busy = false; });
  }
  aboutToDisappear(): void { this.mounted = false; clearTimeout(this.widgetTimer); }
  private activityChanged(): void {
    clearTimeout(this.widgetTimer);
    if (this.active) this.syncPassive();
  }
  private async syncPassive(): Promise<void> {
    clearTimeout(this.widgetTimer);
    if (!this.mounted || !this.active) return;
    try {
      const state = await this.client.state();
      if (!this.mounted || !this.active) return;
      if (!state.authenticated) { this.onLogin(); return; }
      const value = await this.client.request('/pocket/api/overview');
      if (this.mounted && this.active) await this.invoke('widgetSnapshot', value);
    } catch (_) {}
    finally { if (this.mounted && this.active) this.widgetTimer = setTimeout(() => { this.syncPassive(); }, 60000); }
  }
  private async initialize(): Promise<void> {
    const state = JSON.parse(await this.invoke('nativeState', '')) as SettingsState;
    this.themeMode = state.themeMode || 'system';
    this.reduceMotion = state.reduceMotion; this.reduceTransparency = state.reduceTransparency;
    this.widgetDetails = state.widgetDetails; this.supportsPush = state.supportsPush;
    this.pushEnabled = state.pushEnabled; this.backgroundMonitor = state.backgroundMonitor;
    this.notifyCompleted = state.notifyCompleted; this.notifyFailed = state.notifyFailed;
    this.notifyApproval = state.notifyApproval;
    this.busy = false;
    await this.syncPassive();
  }
  private async theme(value: string): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try {
      await this.invoke('themeMode', value);
      const update = (): void => { this.themeMode = value; };
      if (NativeExperience.reducedMotion()) update();
      else this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, update);
    }
    catch (_) { this.status = '外观保存失败'; }
    finally { this.busy = false; }
  }
  private async setting(command: string, value: boolean): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try {
      if (command === 'reduceMotion') this.reduceMotion = value;
      if (command === 'reduceTransparency') this.reduceTransparency = value;
      if (command === 'widgetDetails') this.widgetDetails = value;
      if (command === 'notifyCompleted') this.notifyCompleted = value;
      if (command === 'notifyFailed') this.notifyFailed = value;
      if (command === 'notifyApproval') this.notifyApproval = value;
      if (command === 'backgroundMonitor') this.backgroundMonitor = value;
      await this.invoke(command, value ? 'true' : 'false');
      if (command.startsWith('notify') || command === 'backgroundMonitor') await this.saveNotificationOptions();
      this.status = '已保存';
    } catch (_) { this.status = '保存失败'; }
    finally { this.busy = false; }
  }
  private async saveNotificationOptions(): Promise<void> {
    const notifications = new NotificationPreferences();
    notifications.completed = this.notifyCompleted; notifications.failed = this.notifyFailed; notifications.approval = this.notifyApproval;
    await this.invoke('notificationLevels', JSON.stringify(notifications));
    if (!this.supportsPush || !this.pushEnabled) return;
    const state = await this.client.state();
    if (!state.pushConfigured) return;
    const token = await this.invoke('enablePush', '');
    const id = await this.invoke('deviceId', '');
    const device = new PushDeviceRegistration(); device.id = id; device.token = token; device.notifications = notifications;
    await this.client.request('/pocket/api/device', http.RequestMethod.POST, JSON.stringify(device));
  }
  private async action(command: string): Promise<void> {
    if (command === 'connection') { this.onConnection(); return; }
    if (command === 'about') { this.setAbout(true); return; }
    if (this.busy) return;
    this.busy = true; this.status = '';
    try {
      if (command === 'logout') { await this.onLogout(); return; }
      const state = await this.client.state();
      if (!state.authenticated) { this.onLogin(); return; }
      if (command === 'enablePush') {
        if (!this.supportsPush) return;
        if (!state.pushConfigured) { this.status = '服务器未配置 Push Kit'; return; }
        if (state.mode === 'none') await this.client.request('/pocket/api/auth/none', http.RequestMethod.POST, '{}');
        const token = await this.invoke('enablePush', '');
        const id = await this.invoke('deviceId', '');
        const notifications = new NotificationPreferences();
        notifications.completed = this.notifyCompleted; notifications.failed = this.notifyFailed; notifications.approval = this.notifyApproval;
        const device = new PushDeviceRegistration(); device.id = id; device.token = token; device.notifications = notifications;
        await this.client.request('/pocket/api/device', http.RequestMethod.POST, JSON.stringify(device));
        await this.invoke('pushEnabled', 'true'); this.pushEnabled = true; this.status = '已开启';
      } else if (command === 'disablePush') {
        await this.client.request('/pocket/api/device', http.RequestMethod.DELETE, JSON.stringify({ allForSession: true }));
        await this.invoke('disablePush', ''); await this.invoke('pushEnabled', 'false');
        this.pushEnabled = false; this.status = '已关闭';
      } else if (command === 'sync') {
        const value = await this.client.request('/pocket/api/overview');
        await this.invoke('widgetSnapshot', value); this.status = '已同步';
      }
    } catch (_) { this.status = '操作失败'; }
    finally { this.busy = false; }
  }

  private setAbout(open: boolean): void {
    const update = (): void => { this.aboutOpen = open; };
    if (NativeExperience.reducedMotion()) update();
    else this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, update);
  }

  @Builder
  private sectionHeader(icon: string, title: string, detail: string) {
    Row({ space: 11 }) {
      Text(icon).fontSize(15).fontColor(this.dark ? '#AFC3FF' : '#426FE8')
        .width(34).height(34).textAlign(TextAlign.Center).borderRadius(11)
        .backgroundColor(this.dark ? '#303747' : '#EEF2FF')
      Column({ space: 3 }) {
        Text(title).fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor(this.dark ? '#F4F4F5' : '#202124')
        Text(detail).fontSize(11).lineHeight(16).fontColor(this.dark ? '#A1A1AA' : '#858990')
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
    }.width('100%').padding({ bottom: 8 })
  }

  @Builder
  private toggleRow(title: string, detail: string, enabled: boolean, command: string) {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(title).fontSize(13).fontWeight(FontWeight.Medium)
          .fontColor(this.dark ? '#E7E7E9' : '#25262A')
        Text(detail).fontSize(11).lineHeight(16).fontColor(this.dark ? '#929298' : '#888B91')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: enabled }).enabled(!this.busy)
        .onChange((value: boolean) => { this.setting(command, value); })
    }.width('100%').padding({ top: 10, bottom: 10 })
  }

  @Builder
  private actionRow(title: string, detail: string, command: string, destructive: boolean) {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(title).fontSize(13).fontWeight(FontWeight.Medium)
          .fontColor(destructive ? (this.dark ? '#FF8B8B' : '#C53737') : (this.dark ? '#E7E7E9' : '#25262A'))
        Text(detail).fontSize(11).lineHeight(16).fontColor(this.dark ? '#929298' : '#888B91')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text('›').fontSize(22).fontColor(this.dark ? '#77777D' : '#A0A2A7')
    }.width('100%').padding({ top: 12, bottom: 12 })
      .opacity(this.busy && command !== 'connection' && command !== 'about' ? 0.55 : 1)
      .onClick(() => { this.action(command); })
  }

  build() {
    if (this.aboutOpen) {
      AboutSettings({ onBack: (): void => { this.setAbout(false); } })
        .transition(NativeExperience.reducedMotion() ? TransitionEffect.IDENTITY : TransitionEffect.OPACITY)
    } else {
      Scroll() {
        Column({ space: 13 }) {
          Row() {
            Column({ space: 3 }) {
              Text('设置').fontSize(21).fontWeight(FontWeight.Medium)
                .fontColor(this.dark ? '#F9FAFB' : '#17181B')
              Text('DSH Harmony').fontSize(11).fontColor(this.dark ? '#929298' : '#888B91')
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Button('×', { type: ButtonType.Normal }).width(38).height(38).fontSize(23).borderRadius(19)
              .backgroundColor(this.dark ? '#2D2D30' : '#ECEDEF').fontColor(this.dark ? '#E4E4E7' : '#5E6065')
              .onClick(this.onReturn)
          }.width('100%')
          Column() {
            this.sectionHeader('◐', '外观', '跟随系统，或选择固定显示模式')
            Row({ space: 7 }) {
              ForEach(['system', 'light', 'dark'], (mode: string) => {
                Button(mode === 'system' ? '自动' : mode === 'light' ? '浅色' : '深色', { type: ButtonType.Normal })
                  .height(38).fontSize(12).borderRadius(10).layoutWeight(1)
                  .backgroundColor(this.themeMode === mode ? (this.dark ? '#3B4D76' : '#EAF0FF') : (this.dark ? '#303033' : '#F4F5F6'))
                  .fontColor(this.themeMode === mode ? (this.dark ? '#C4D2FF' : '#315FCB') : (this.dark ? '#D4D4D8' : '#55585D'))
                  .enabled(!this.busy).onClick(() => { this.theme(mode); })
              }, (mode: string) => mode)
            }.width('100%').padding({ top: 5, bottom: 8 })
            Divider().color(this.dark ? '#39393D' : '#ECEDEF')
            this.toggleRow('减少动态效果', '遵循系统动画偏好', this.reduceMotion, 'reduceMotion')
            Divider().color(this.dark ? '#39393D' : '#ECEDEF')
            this.toggleRow('减少透明效果', '降低背景材质与透明效果', this.reduceTransparency, 'reduceTransparency')
          }.padding(16).width('100%').borderRadius(17)
            .backgroundColor(this.dark ? '#222225' : '#FFFFFF')
            .border({ width: 1, color: this.dark ? '#353538' : '#E8E9EC' })
          Column() {
            this.sectionHeader('◉', '通知', '按任务状态接收提醒')
            this.toggleRow('需要确认', '权限申请与等待操作', this.notifyApproval, 'notifyApproval')
            Divider().color(this.dark ? '#39393D' : '#ECEDEF')
            this.toggleRow('任务失败', '任务发生错误或运行失败', this.notifyFailed, 'notifyFailed')
            Divider().color(this.dark ? '#39393D' : '#ECEDEF')
            this.toggleRow('任务完成', '后台任务结束时提醒', this.notifyCompleted, 'notifyCompleted')
            Divider().color(this.dark ? '#39393D' : '#ECEDEF')
            if (this.supportsPush) {
              this.actionRow(this.pushEnabled ? '关闭系统推送' : '开启系统推送',
                this.pushEnabled ? '此设备已注册远程通知' : '通过服务端接收通知', this.pushEnabled ? 'disablePush' : 'enablePush', false)
            } else {
              this.toggleRow('后台任务监控', '无 Push Kit 时保持任务监控', this.backgroundMonitor, 'backgroundMonitor')
            }
          }.padding(16).width('100%').borderRadius(17)
            .backgroundColor(this.dark ? '#222225' : '#FFFFFF')
            .border({ width: 1, color: this.dark ? '#353538' : '#E8E9EC' })
          Column() {
            this.sectionHeader('▦', '桌面卡片', '管理 HarmonyOS 桌面信息')
            this.toggleRow('显示任务名称', '在卡片中展示当前任务', this.widgetDetails, 'widgetDetails')
            Divider().color(this.dark ? '#39393D' : '#ECEDEF')
            this.actionRow('立即同步', '刷新桌面卡片内容', 'sync', false)
          }.padding(16).width('100%').borderRadius(17)
            .backgroundColor(this.dark ? '#222225' : '#FFFFFF')
            .border({ width: 1, color: this.dark ? '#353538' : '#E8E9EC' })
          Column() {
            this.sectionHeader('⌘', '服务', '工作空间连接与应用信息')
            this.actionRow('服务与登录', '管理地址和认证方式', 'connection', false)
            Divider().color(this.dark ? '#39393D' : '#ECEDEF')
            this.actionRow('退出当前连接', '清除此设备的登录状态', 'logout', true)
            Divider().color(this.dark ? '#39393D' : '#ECEDEF')
            this.actionRow('关于 DSH Harmony', '版本、维护者与项目链接', 'about', false)
          }.padding(16).width('100%').borderRadius(17)
            .backgroundColor(this.dark ? '#222225' : '#FFFFFF')
            .border({ width: 1, color: this.dark ? '#353538' : '#E8E9EC' })
          if (this.status) {
            Text(this.status).fontSize(12).fontColor(this.dark ? '#A1A1AA' : '#74777D')
              .width('100%').textAlign(TextAlign.Center).padding({ top: 2, bottom: 4 })
              .transition(NativeExperience.reducedMotion() ? TransitionEffect.IDENTITY : TransitionEffect.OPACITY)
          }
        }.padding({ left: 18, right: 18, top: 16, bottom: 26 }).width('100%')
          .constraintSize({ maxWidth: 680 }).alignItems(HorizontalAlign.Start)
      }.width('100%').height('100%').backgroundColor(this.dark ? '#171719' : '#F5F6F8')
        .transition(NativeExperience.reducedMotion() ? TransitionEffect.IDENTITY : TransitionEffect.OPACITY)
    }
  }
}
