import { http } from '@kit.NetworkKit';
import { NativeHarnessClient } from '../services/NativeHarnessClient';
import { NativeExperience } from '../services/NativeExperience';
import { AboutSettings } from './AboutSettings';
import { DSHIcon } from './DSHIcon';
import { NativeChatPreferences, NativeSettingsDescription } from '../services/NativeHostSettings';

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
  serverOrigin: string = '';
  invoke: (command: string, value: string) => Promise<string> = async (): Promise<string> => '';
  onReturn: () => void = (): void => {};
  onModes: () => void = (): void => {};
  onConnection: () => void = (): void => {};
  onLogin: () => void = (): void => {};
  onLogout: () => Promise<void> = async (): Promise<void> => {};
  @StorageLink('nativeAppActive') @Watch('activityChanged') private active: boolean = true;
  @StorageLink('nativeDark') private dark: boolean = false;
  @StorageLink('nativeHostSettingsRevision') @Watch('hostChanged') private hostRevision: number = 0;
  @State private host: NativeSettingsDescription = new NativeSettingsDescription();
  @State private chat: NativeChatPreferences = new NativeChatPreferences();
  @State private tab: string = 'general';
  @State private hostBusy: boolean = false;
  @State private hostError: string = '';
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
  @StorageLink('nativeSettingsPage') private settingsPage: string = 'root';
  @State private busy: boolean = true;
  @State private status: string = '';
  private mounted: boolean = false;
  private widgetTimer: number = -1;

  aboutToAppear(): void {
    this.mounted = true;
    this.initialize().catch(() => { this.status = '读取设置失败'; this.busy = false; });
    this.refreshHost();
  }
  aboutToDisappear(): void { this.mounted = false; clearTimeout(this.widgetTimer); }
  private hostChanged(): void { this.host = this.client.hostSettings.description; this.chat = this.client.hostSettings.chat(); }
  private async refreshHost(): Promise<void> {
    this.hostBusy = true; this.hostError = '';
    try { await this.client.hostSettings.refresh(); if (this.mounted) this.hostChanged(); }
    catch (_) { if (this.mounted) this.hostError = '读取失败'; }
    finally { if (this.mounted) this.hostBusy = false; }
  }
  private async saveHost(ns: string, field: string, value: string | number): Promise<void> {
    if (this.hostBusy) return;
    this.hostBusy = true; this.hostError = '';
    try { await this.client.hostSettings.set(ns, field, value); if (this.mounted) this.hostChanged(); }
    catch (_) { if (this.mounted) this.hostError = '保存失败，已同步最新设置'; }
    finally { if (this.mounted) this.hostBusy = false; }
  }
  private hasHost(ns: string): boolean { return this.host.namespaces.some((row) => row.ns === ns); }
  @Builder
  private hostChoice(title: string, field: string, values: string[], labels: string[], current: string, ns: string = 'ui-chat') {
    Row({ space: 8 }) {
      Text(title).fontSize(14).layoutWeight(1).fontColor(this.dark ? '#F9FAFB' : '#17181B')
      Select(labels.map((value: string): SelectOption => ({ value }))).selected(Math.max(0, values.indexOf(current)))
        .value(labels[Math.max(0, values.indexOf(current))]).font({ size: 13 }).height(36).borderRadius(10)
        .backgroundColor(this.dark ? '#2C2C2E' : '#F5F6F7').fontColor(this.dark ? '#F9FAFB' : '#17181B')
        .enabled(!this.hostBusy && this.host.writable).onSelect((index: number) => { this.saveHost(ns, field, values[index]); })
    }.width('100%').constraintSize({ minHeight: 52 })
  }
  @Builder
  private hostGeneral() {
    Column() {
      if (this.hasHost('ui-chat')) {
        this.hostChoice('工作步骤展示', 'transcriptView', ['compact','standard','detailed','verbose'], ['简洁','标准','详细','完全展开'], this.chat.mode)
        Divider().strokeWidth(0.5).color(this.dark ? '#353638' : '#E8E9EC')
        this.hostChoice('过程收起时机', 'collapseTiming', ['completion','next-input'], ['完成时','下次发送时'], this.chat.collapseTiming)
        if (this.chat.mode !== 'verbose') {
          Divider().strokeWidth(0.5).color(this.dark ? '#353638' : '#E8E9EC')
          this.hostChoice('收起后显示回复', 'foldedReplies', ['all','final'], ['全部回复','仅最终回答'], this.chat.foldedReplies)
        }
      }
      if (this.hasHost('ui-conversation')) {
        Divider().strokeWidth(0.5).color(this.dark ? '#353638' : '#E8E9EC')
        this.hostChoice('运行时发送', 'busyEnter', ['queue','steer'], ['排队','立即干预'], this.chat.busyEnter, 'ui-conversation')
      }
      if (this.hostBusy) { LoadingProgress().width(20).height(20).margin({ top: 12 }) }
      if (this.hostError) { Row() {
        Text(this.hostError).fontSize(12).layoutWeight(1).fontColor(this.dark ? '#FF9393' : '#C53737')
        Button('重试', { type: ButtonType.Normal }).height(36).fontSize(12).onClick(() => { this.refreshHost(); })
      }.width('100%') }
      if (!this.hostBusy && !this.hostError && !this.host.namespaces.length) { Text('此服务未提供通用设置').fontSize(13).padding({ top: 16 }).fontColor(this.dark ? '#93969B' : '#8A8D91') }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
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
    if (command === 'connection') { this.openPage('connection'); return; }
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
    this.openPage(open ? 'about' : 'root');
  }
  private openPage(page: string): void {
    const update = (): void => { this.settingsPage = page; };
    if (NativeExperience.reducedMotion()) update();
    else this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, update);
  }

  @Builder
  private connectionPage() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) {
          DSHIcon({ glyph: 'chevron-left-outline', color: this.dark ? '#F9FAFB' : '#17181B' })
        }.width(36).height(36).backgroundColor(Color.Transparent)
          .accessibilityText('返回设置').onClick(() => { this.openPage('root'); })
        Text('服务与登录').fontSize(18).fontWeight(FontWeight.Medium)
          .fontColor(this.dark ? '#F9FAFB' : '#17181B')
      }.width('100%')
      Scroll() {
        Column({ space: 14 }) {
          Text('当前服务').fontSize(12).fontColor(this.dark ? '#93969B' : '#777A80')
          Text(this.serverOrigin).fontSize(14).copyOption(CopyOptions.InApp)
            .fontColor(this.dark ? '#F9FAFB' : '#17181B').width('100%').wordBreak(WordBreak.BREAK_ALL)
          Button('退出当前连接', { type: ButtonType.Normal }).height(42).width('100%').borderRadius(10)
            .backgroundColor(this.dark ? '#4A2224' : '#FDECEC').fontColor(this.dark ? '#FFD7D8' : '#A52025')
            .enabled(!this.busy).onClick(() => { this.action('logout'); })
        }.padding(14).width('100%').alignItems(HorizontalAlign.Start).borderRadius(14)
          .backgroundColor(this.dark ? '#222225' : '#FFFFFF')
      }.width('100%').layoutWeight(1).align(Alignment.Top)
    }.padding(12).width('100%').height('100%').backgroundColor(this.dark ? '#171719' : '#F5F6F8')
  }

  @Builder
  private sectionHeader(icon: string, title: string, detail: string) {
    Row({ space: 11 }) {
      Text(icon).fontSize(15).fontColor(this.dark ? '#A1A1AA' : '#858990')
        .width(24).height(24).textAlign(TextAlign.Center)
      Column({ space: 3 }) {
        Text(title).fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor(this.dark ? '#F4F4F5' : '#202124')
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
    }.width('100%').padding({ bottom: 8 })
  }

  @Builder
  private toggleRow(title: string, detail: string, enabled: boolean, command: string) {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(title).fontSize(13).fontWeight(FontWeight.Medium)
          .fontColor(this.dark ? '#E7E7E9' : '#25262A')
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
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text('›').fontSize(22).fontColor(this.dark ? '#77777D' : '#A0A2A7')
    }.width('100%').padding({ top: 12, bottom: 12 })
      .opacity(this.busy && command !== 'connection' && command !== 'about' ? 0.55 : 1)
      .onClick(() => { this.action(command); })
  }

  @Builder
  private appPreferences() {
    Column({ space: 14 }) {
      Text('外观').fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.dark ? '#93969B' : '#8A8D91')
      Row({ space: 8 }) {
        ForEach(['light', 'dark', 'system'], (mode: string) => {
          Button({ type: ButtonType.Normal }) {
            Column({ space: 8 }) {
              DSHIcon({ glyph: mode === 'light' ? 'light-outline' : mode === 'dark' ? 'dark-outline' : 'followsystem-outline',
                glyphSize: 20, color: this.dark ? '#F9FAFB' : '#17181B' })
              Text(mode === 'system' ? '跟随系统' : mode === 'light' ? '浅色' : '深色').fontSize(12)
            }
          }.height(76).borderRadius(12).layoutWeight(1)
            .backgroundColor(this.dark ? '#232324' : '#F5F6F7')
            .fontColor(this.dark ? '#F9FAFB' : '#17181B')
            .border({ width: this.themeMode === mode ? 1.5 : 0.5, color: this.themeMode === mode ? this.dark ? '#F9FAFB' : '#17181B' : this.dark ? '#353638' : '#E8E9EC', radius: 12 })
            .enabled(!this.busy).onClick(() => { this.theme(mode); })
        }, (mode: string) => mode)
      }.width('100%')
      Column() {
        this.toggleRow('减少动态效果', '', this.reduceMotion, 'reduceMotion')
        Divider().strokeWidth(0.5).color(this.dark ? '#353638' : '#E8E9EC')
        this.toggleRow('减少透明效果', '', this.reduceTransparency, 'reduceTransparency')
      }.width('100%')
      Text('通知').fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.dark ? '#93969B' : '#8A8D91')
      Column() {
        this.toggleRow('需要确认', '', this.notifyApproval, 'notifyApproval')
        Divider().strokeWidth(0.5).color(this.dark ? '#353638' : '#E8E9EC')
        this.toggleRow('任务失败', '', this.notifyFailed, 'notifyFailed')
        Divider().strokeWidth(0.5).color(this.dark ? '#353638' : '#E8E9EC')
        this.toggleRow('任务完成', '', this.notifyCompleted, 'notifyCompleted')
        Divider().strokeWidth(0.5).color(this.dark ? '#353638' : '#E8E9EC')
        if (this.supportsPush) { this.actionRow(this.pushEnabled ? '关闭系统推送' : '开启系统推送', '', this.pushEnabled ? 'disablePush' : 'enablePush', false) }
        else { this.toggleRow('后台任务监控', '', this.backgroundMonitor, 'backgroundMonitor') }
      }.width('100%')
      Text('桌面卡片').fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.dark ? '#93969B' : '#8A8D91')
      Column() {
        this.toggleRow('显示任务名称', '', this.widgetDetails, 'widgetDetails')
        Divider().strokeWidth(0.5).color(this.dark ? '#353638' : '#E8E9EC')
        this.actionRow('立即同步', '', 'sync', false)
      }.width('100%')
      Text('连接').fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.dark ? '#93969B' : '#8A8D91')
      Column() {
        this.actionRow('服务与登录', '', 'connection', false)
        Divider().strokeWidth(0.5).color(this.dark ? '#353638' : '#E8E9EC')
        this.actionRow('退出当前连接', '', 'logout', true)
      }.width('100%')
      if (this.status) { Text(this.status).fontSize(12).fontColor(this.dark ? '#93969B' : '#8A8D91').width('100%').textAlign(TextAlign.Center) }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  build() {
    if (this.settingsPage === 'about') {
      AboutSettings({ onBack: (): void => { this.setAbout(false); } })
        .transition(NativeExperience.reducedMotion() ? TransitionEffect.IDENTITY : TransitionEffect.OPACITY)
    } else if (this.settingsPage === 'connection') {
      this.connectionPage()
    } else {
      Column({ space: 8 }) {
        Row() {
          Text('设置').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1).fontColor(this.dark ? '#F9FAFB' : '#17181B')
          Button({ type: ButtonType.Normal }) {
            DSHIcon({ glyph: 'close-outline', color: this.dark ? '#F9FAFB' : '#17181B' })
          }.width(40).height(40).borderRadius(12).backgroundColor(Color.Transparent).accessibilityText('关闭设置').onClick(this.onReturn)
        }.width('100%').padding({ left: 16, right: 8, top: 8 })
        Scroll() {
          Row({ space: 4 }) {
            Button('通用', { type: ButtonType.Normal }).height(40).width(108).fontSize(14).borderRadius(12)
              .backgroundColor(this.tab === 'general' ? this.dark ? '#353638' : '#EBEEF2' : Color.Transparent)
              .fontColor(this.dark ? '#F9FAFB' : '#17181B').onClick(() => { this.tab = 'general'; })
            Button('应用', { type: ButtonType.Normal }).height(40).width(108).fontSize(14).borderRadius(12)
              .backgroundColor(this.tab === 'app' ? this.dark ? '#353638' : '#EBEEF2' : Color.Transparent)
              .fontColor(this.dark ? '#F9FAFB' : '#17181B').onClick(() => { this.tab = 'app'; })
            Button('关于', { type: ButtonType.Normal }).height(40).width(108).fontSize(14).borderRadius(12)
              .backgroundColor(Color.Transparent).fontColor(this.dark ? '#F9FAFB' : '#17181B').onClick(() => { this.setAbout(true); })
          }.padding({ left: 16, right: 16 })
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%').height(48)
        Divider().strokeWidth(0.5).color(this.dark ? '#353638' : '#E8E9EC')
        Scroll() {
          Column() {
            if (this.tab === 'general') { this.hostGeneral() }
            else { this.appPreferences() }
          }.padding({ left: 16, right: 16, top: 8, bottom: 24 }).width('100%').constraintSize({ maxWidth: 680 })
            .alignItems(HorizontalAlign.Start)
        }.width('100%').layoutWeight(1).align(Alignment.Top)
      }.width('100%').height('100%').backgroundColor(this.dark ? '#151517' : '#FFFFFF')
    }
  }
}
