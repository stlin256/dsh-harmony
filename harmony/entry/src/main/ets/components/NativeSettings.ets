import { http } from '@kit.NetworkKit';
import { NativeHarnessClient } from '../services/NativeHarnessClient';
import { NativeExperience } from '../services/NativeExperience';
import { NativeChatPreferences, NativeSettingsDescription } from '../services/NativeHostSettings';
import { AboutSettings } from './AboutSettings';
import { DSHIcon } from './DSHIcon';

class NotificationPreferences {
  version: number = 1;
  completed: string = 'quiet';
  failed: string = 'standard';
  approval: string = 'standard';
  connection: string = 'off';
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
  supportsPush: boolean = false;
  pushEnabled: boolean = false;
  notificationsEnabled: boolean = true;
  notificationPermissionKnown: boolean = false;
  backgroundMonitor: boolean = false;
  notifyCompleted: string = 'quiet';
  notifyFailed: string = 'standard';
  notifyApproval: string = 'standard';
  notifyConnection: string = 'off';
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
  @StorageLink('nativeDark') private dark: boolean = false;
  @StorageLink('nativeHostSettingsRevision') @Watch('hostChanged') private hostRevision: number = 0;
  @StorageLink('nativeAppActive') @Watch('activityChanged') private active: boolean = true;
  @StorageLink('nativeSafeTop') private safeTop: number = 0;
  @StorageLink('nativeSafeBottom') private safeBottom: number = 0;
  @StorageLink('nativeSettingsPage') private settingsPage: string = 'root';
  @State private host: NativeSettingsDescription = new NativeSettingsDescription();
  @State private chat: NativeChatPreferences = new NativeChatPreferences();
  @State private hostLoading: boolean = false;
  @State private hostSaving: string[] = [];
  @State private hostError: string = '';
  @State private retryHostNs: string = '';
  @State private retryHostField: string = '';
  @State private retryHostValue: string = '';
  @State private themeMode: string = 'system';
  @State private reduceMotion: boolean = false;
  @State private reduceTransparency: boolean = false;
  @State private widgetDetails: boolean = true;
  @State private supportsPush: boolean = false;
  @State private pushEnabled: boolean = false;
  @State private notificationsEnabled: boolean = true;
  @State private notificationPermissionKnown: boolean = false;
  @State private backgroundMonitor: boolean = false;
  @State private notifyCompleted: string = 'quiet';
  @State private notifyFailed: string = 'standard';
  @State private notifyApproval: string = 'standard';
  @State private notifyConnection: string = 'off';
  @State private initializing: boolean = true;
  @State private pending: string[] = [];
  @State private status: string = '';
  @State private error: string = '';
  private mounted: boolean = false;
  private notificationWrites: Promise<void> = Promise.resolve();

  aboutToAppear(): void {
    this.mounted = true;
    this.hostChanged();
    this.initialize().catch(() => { this.error = '读取设置失败'; this.initializing = false; });
    this.refreshHost();
  }

  aboutToDisappear(): void {
    this.mounted = false;
  }

  private activityChanged(): void {
    if (this.mounted && this.active && !this.initializing) {
      this.refreshNotificationState().catch((): void => {});
    }
  }

  private hostChanged(): void {
    this.host = this.client.hostSettings.description;
    this.chat = this.client.hostSettings.chat();
  }

  private async refreshHost(): Promise<void> {
    this.hostLoading = true;
    this.hostError = '';
    try {
      await this.client.hostSettings.refresh();
      if (this.mounted) this.hostChanged();
    } catch (_) {
      if (this.mounted) this.hostError = 'DSH 设置暂不可用';
    } finally {
      if (this.mounted) this.hostLoading = false;
    }
  }

  private async saveHost(ns: string, field: string, value: string | number): Promise<void> {
    const key = ns + ':' + field;
    if (this.hostSaving.includes(key)) return;
    this.hostSaving = this.hostSaving.concat([key]);
    this.hostError = '';
    this.retryHostNs = '';
    this.retryHostField = '';
    this.retryHostValue = '';
    try {
      await this.client.hostSettings.set(ns, field, value);
      if (this.mounted) this.hostChanged();
    } catch (_) {
      if (this.mounted) {
        this.hostError = '这一项保存失败';
        this.retryHostNs = ns;
        this.retryHostField = field;
        this.retryHostValue = String(value);
      }
    } finally {
      if (this.mounted) this.hostSaving = this.hostSaving.filter((name: string) => name !== key);
    }
  }

  private retryHostWrite(): void {
    if (this.retryHostField) this.saveHost(this.retryHostNs, this.retryHostField, this.retryHostValue);
    else this.refreshHost();
  }

  private hasHost(ns: string): boolean {
    return this.host.namespaces.some((row) => row.ns === ns);
  }

  private pendingFor(key: string): boolean {
    return this.pending.includes(key);
  }

  private pushBusy(): boolean {
    return this.pendingFor('enablePush') || this.pendingFor('disablePush');
  }

  private begin(key: string): boolean {
    if (this.initializing || this.pendingFor(key)) return false;
    this.pending = this.pending.concat([key]);
    this.error = '';
    this.status = '';
    return true;
  }

  private end(key: string): void {
    if (this.mounted) this.pending = this.pending.filter((value: string) => value !== key);
  }

  private openPage(page: string): void {
    const update = (): void => { this.settingsPage = page; };
    if (NativeExperience.reducedMotion()) update();
    else this.getUIContext().animateTo({ duration: 210, curve: Curve.EaseOut }, update);
  }

  private level(value: string, fallback: string): string {
    return ['off', 'quiet', 'standard', 'prominent'].includes(value) ? value : fallback;
  }

  private async initialize(): Promise<void> {
    const state = JSON.parse(await this.invoke('nativeState', '')) as SettingsState;
    this.themeMode = state.themeMode || 'system';
    this.reduceMotion = state.reduceMotion === true;
    this.reduceTransparency = state.reduceTransparency === true;
    this.widgetDetails = state.widgetDetails !== false;
    this.supportsPush = state.supportsPush === true;
    this.pushEnabled = state.pushEnabled === true;
    this.notificationsEnabled = state.notificationsEnabled !== false;
    this.notificationPermissionKnown = state.notificationPermissionKnown === true;
    this.backgroundMonitor = state.backgroundMonitor === true;
    this.notifyCompleted = this.level(state.notifyCompleted, 'quiet');
    this.notifyFailed = this.level(state.notifyFailed, 'standard');
    this.notifyApproval = this.level(state.notifyApproval, 'standard');
    this.notifyConnection = this.level(state.notifyConnection, 'off');
    this.initializing = false;
  }

  private async theme(value: string): Promise<void> {
    if (!this.begin('theme')) return;
    const previous = this.themeMode;
    this.themeMode = value;
    try {
      await this.invoke('themeMode', value);
      this.status = '已保存';
    } catch (_) {
      this.themeMode = previous;
      this.error = '外观保存失败';
    } finally {
      this.end('theme');
    }
  }

  private async setting(command: string, value: boolean): Promise<void> {
    if (!this.begin(command)) return;
    const previous = this.localValue(command);
    this.setLocalValue(command, value);
    try {
      await this.invoke(command, value ? 'true' : 'false');
      this.status = '已保存';
    } catch (_) {
      this.setLocalValue(command, previous);
      this.error = command === 'backgroundMonitor' ? '后台投递启动失败' : '保存失败';
    } finally {
      this.end(command);
    }
  }

  private localValue(command: string): boolean {
    if (command === 'reduceMotion') return this.reduceMotion;
    if (command === 'reduceTransparency') return this.reduceTransparency;
    if (command === 'widgetDetails') return this.widgetDetails;
    if (command === 'backgroundMonitor') return this.backgroundMonitor;
    return false;
  }

  private setLocalValue(command: string, value: boolean): void {
    if (command === 'reduceMotion') this.reduceMotion = value;
    else if (command === 'reduceTransparency') this.reduceTransparency = value;
    else if (command === 'widgetDetails') this.widgetDetails = value;
    else if (command === 'backgroundMonitor') this.backgroundMonitor = value;
  }

  private notificationValue(category: string): string {
    if (category === 'approval') return this.notifyApproval;
    if (category === 'failed') return this.notifyFailed;
    if (category === 'completed') return this.notifyCompleted;
    return this.notifyConnection;
  }

  private setNotificationValue(category: string, value: string): void {
    if (category === 'approval') this.notifyApproval = value;
    else if (category === 'failed') this.notifyFailed = value;
    else if (category === 'completed') this.notifyCompleted = value;
    else this.notifyConnection = value;
  }

  private notificationPreferences(): NotificationPreferences {
    const value = new NotificationPreferences();
    value.completed = this.notifyCompleted;
    value.failed = this.notifyFailed;
    value.approval = this.notifyApproval;
    value.connection = this.notifyConnection;
    return value;
  }

  private async saveNotificationLevel(category: string, levelValue: string): Promise<void> {
    const key = 'notification:' + category;
    if (!this.begin(key)) return;
    const previous = this.notificationValue(category);
    let localSaved = false;
    this.setNotificationValue(category, levelValue);
    try {
      const write = this.notificationWrites.catch((): void => {}).then(async (): Promise<void> => {
        const notifications = this.notificationPreferences();
        await this.invoke('notificationLevels', JSON.stringify(notifications));
        localSaved = true;
        if (this.supportsPush && this.pushEnabled) await this.syncDevice(notifications);
      });
      this.notificationWrites = write;
      await write;
      this.status = '通知偏好已保存';
    } catch (_) {
      if (!localSaved) {
        this.setNotificationValue(category, previous);
        this.error = '通知偏好保存失败';
      } else {
        this.status = '已保存本机，服务端同步待重试';
      }
    } finally {
      this.end(key);
    }
  }

  private async refreshNotificationState(): Promise<void> {
    const state = JSON.parse(await this.invoke('nativeState', '')) as SettingsState;
    this.notificationsEnabled = state.notificationsEnabled !== false;
    this.notificationPermissionKnown = state.notificationPermissionKnown === true;
  }

  private async syncDevice(notifications: NotificationPreferences): Promise<void> {
    const state = await this.client.state();
    if (!state.authenticated || !state.pushConfigured) return;
    const token = await this.invoke('enablePush', '');
    const id = await this.invoke('deviceId', '');
    const device = new PushDeviceRegistration();
    device.id = id;
    device.token = token;
    device.notifications = notifications;
    await this.client.request('/pocket/api/device', http.RequestMethod.POST, JSON.stringify(device));
  }

  private async action(command: string): Promise<void> {
    if (command === 'logout') {
      if (!this.begin('logout')) return;
      try { await this.onLogout(); }
      catch (_) { this.error = '退出失败，请重试'; }
      finally { this.end('logout'); }
      return;
    }
    if (command === 'connection') { this.openPage('connection'); return; }
    if (command === 'modes') { this.onModes(); return; }
    if (command === 'about') { this.openPage('about'); return; }
    if (command === 'notificationSettings') {
      if (!this.begin(command)) return;
      try {
        await this.invoke('openNotificationSettings', '');
      } catch (_) {
        this.error = '无法打开系统通知设置';
      } finally {
        this.end(command);
      }
      return;
    }
    if (!this.begin(command)) return;
    try {
      const state = await this.client.state();
      if (!state.authenticated) { this.onLogin(); return; }
      if (command === 'enablePush') {
        if (!this.supportsPush) throw new Error('Unsupported');
        if (!state.pushConfigured) throw new Error('Server is not configured');
        if (state.mode === 'none') await this.client.request('/pocket/api/auth/none', http.RequestMethod.POST, '{}');
        await this.syncDevice(this.notificationPreferences());
        await this.invoke('pushEnabled', 'true');
        this.pushEnabled = true;
        this.status = '系统推送已开启';
      } else if (command === 'disablePush') {
        await this.client.request('/pocket/api/device', http.RequestMethod.DELETE, JSON.stringify({ allForSession: true }));
        await this.invoke('disablePush', '');
        await this.invoke('pushEnabled', 'false');
        this.pushEnabled = false;
        this.status = '系统推送已关闭';
      } else if (command === 'sync') {
        const value = await this.client.request('/pocket/api/overview');
        await this.invoke('widgetSnapshot', value);
        this.status = '桌面卡片已同步';
      } else if (command === 'testNotification') {
        await this.invoke('testNotification', '');
        await this.refreshNotificationState();
        this.status = '测试通知已发送';
      }
    } catch (_) {
      if (command === 'enablePush') this.error = 'Push 注册失败；请检查证书、服务端凭据和系统通知权限';
      else if (command === 'testNotification') this.error = '测试通知发送失败';
      else this.error = '操作失败，请重试';
    } finally {
      this.end(command);
    }
  }

  @Builder
  private rootHeader() {
    Row({ space: 8 }) {
      Text('设置').fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.dark ? '#F9FAFB' : '#111216')
        .layoutWeight(1)
      Button({ type: ButtonType.Normal }) {
        DSHIcon({ glyph: 'close-outline', glyphSize: 17, color: this.dark ? '#F9FAFB' : '#17181B' })
      }.width(40).height(40).borderRadius(12).backgroundColor(Color.Transparent)
        .accessibilityText('关闭设置').onClick(this.onReturn)
    }.width('100%').height(58)
  }

  @Builder
  private pageHeader(title: string) {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Normal }) {
        DSHIcon({ glyph: 'chevron-left-outline', glyphSize: 17, color: this.dark ? '#F9FAFB' : '#17181B' })
      }.width(40).height(40).borderRadius(12).backgroundColor(Color.Transparent)
        .accessibilityText('返回设置').onClick(() => { this.openPage('root'); })
      Text(title).fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
        .fontColor(this.dark ? '#F9FAFB' : '#17181B')
    }.width('100%').height(58)
  }

  @Builder
  private sectionLabel(title: string) {
    Text(title).fontSize(12).fontWeight(FontWeight.Medium)
      .fontColor(this.dark ? '#8E9197' : '#70747A').padding({ left: 5, top: 8, bottom: 5 })
  }

  private choiceOptions(values: string[], labels: string[], current: string): SelectOption[] {
    const options: SelectOption[] = labels.map((value: string): SelectOption => ({ value }));
    if (!values.includes(current)) options.unshift({ value: '未设置' });
    return options;
  }

  private choiceIndex(values: string[], current: string): number {
    const index = values.indexOf(current);
    return index >= 0 ? index : 0;
  }

  private choiceLabel(values: string[], labels: string[], current: string): string {
    const index = values.indexOf(current);
    return index >= 0 ? labels[index] : '未设置';
  }

  @Builder
  private navigationRow(icon: string, title: string, detail: string, page: string) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        DSHIcon({ glyph: icon, glyphSize: 18, color: this.dark ? '#D5D7DB' : '#52565C' })
        Text(title).fontSize(15).layoutWeight(1).fontColor(this.dark ? '#F2F2F3' : '#1E2024')
        if (detail) {
          Text(detail).fontSize(12).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor(this.dark ? '#85888D' : '#8A8D93')
        }
        DSHIcon({ glyph: 'chevron-left-outline', glyphSize: 13, color: this.dark ? '#686B70' : '#A2A5AA' })
          .rotate({ angle: 180 })
      }.width('100%').height(56).padding({ left: 14, right: 13 })
    }.width('100%').height(56).borderRadius(0).backgroundColor(Color.Transparent)
      .accessibilityText(title + (detail ? '，' + detail : ''))
      .onClick(() => { this.openPage(page); })
  }

  @Builder
  private settingsRoot() {
    Column() {
      this.rootHeader()
      Scroll() {
        Column({ space: 0 }) {
          this.sectionLabel('DSH HARMONY')
          Column() {
            this.navigationRow('personalization-outline', 'DSH 设置', '对话与过程展示', 'dsh')
            Divider().strokeWidth(0.5).margin({ left: 44 }).color(this.dark ? '#323236' : '#E9EAEC')
            this.navigationRow('dark-outline', '外观与动效',
              this.themeMode === 'system' ? '跟随系统' : this.themeMode === 'dark' ? '深色' : '浅色', 'appearance')
          }.width('100%').borderRadius(16).clip(true).backgroundColor(this.dark ? '#232326' : '#FFFFFF')
          this.sectionLabel('应用')
          Column() {
            this.navigationRow('plan-outline', '通知', this.pushEnabled ? '系统推送' : '按级别投递', 'notifications')
            Divider().strokeWidth(0.5).margin({ left: 44 }).color(this.dark ? '#323236' : '#E9EAEC')
            this.navigationRow('browse-outline', '桌面卡片', this.widgetDetails ? '显示任务名称' : '隐私模式', 'cards')
            Divider().strokeWidth(0.5).margin({ left: 44 }).color(this.dark ? '#323236' : '#E9EAEC')
            this.navigationRow('globe-outline', '服务与账户', '连接和登录', 'connection')
            Divider().strokeWidth(0.5).margin({ left: 44 }).color(this.dark ? '#323236' : '#E9EAEC')
            this.navigationRow('sparkle', '关于', '版本与项目信息', 'about')
          }.width('100%').borderRadius(16).clip(true).backgroundColor(this.dark ? '#232326' : '#FFFFFF')
          if (this.initializing) {
            Row({ space: 8 }) {
              LoadingProgress().width(15).height(15).color(this.dark ? '#B8BABE' : '#777B81')
              Text('正在读取本机设置').fontSize(12).fontColor(this.dark ? '#8E9197' : '#777B81')
            }.padding({ top: 14, left: 5 })
          }
          if (this.error) {
            Text(this.error).fontSize(12).padding({ top: 12, left: 5 })
              .fontColor(this.dark ? '#FF9999' : '#B83A3A')
          }
        }.padding({ left: 16, right: 16, top: 2, bottom: this.safeBottom + 28 }).width('100%')
          .constraintSize({ maxWidth: 680 }).alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off)
    }.padding({ top: this.safeTop, left: 4, right: 4 }).width('100%').height('100%')
      .backgroundColor(this.dark ? '#171719' : '#F5F6F8')
      .transition(NativeExperience.reducedMotion() ? TransitionEffect.IDENTITY :
        TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 8 })))
  }

  @Builder
  private hostChoice(title: string, field: string, values: string[], labels: string[], current: string,
    ns: string = 'ui-chat') {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(title).fontSize(14).fontColor(this.dark ? '#F0F1F2' : '#24262A')
        if (!this.host.writable) {
          Text('服务端设置当前为只读').fontSize(11)
            .fontColor(this.dark ? '#C9A66C' : '#8B641F')
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (this.hostSaving.includes(ns + ':' + field)) LoadingProgress().width(14).height(14)
      else {
        Select(this.choiceOptions(values, labels, current))
          .selected(this.choiceIndex(values, current))
          .value(this.choiceLabel(values, labels, current))
          .font({ size: 13 }).height(36).borderRadius(10)
          .backgroundColor(this.dark ? '#303136' : '#F2F3F5')
          .fontColor(this.dark ? '#F2F2F3' : '#24262A')
          .optionFontColor(this.dark ? '#F2F2F3' : '#24262A')
          .selectedOptionFontColor(this.dark ? '#A9C6FF' : '#315DCA')
          .optionBgColor(this.dark ? '#28292C' : '#FFFFFF')
          .selectedOptionBgColor(this.dark ? '#383A40' : '#EBEEF3')
          .menuBackgroundColor(this.dark ? '#28292C' : '#FFFFFF')
          .enabled(!this.hostSaving.includes(ns + ':' + field) && this.host.writable)
          .opacity(this.host.writable ? 1 : 0.55)
          .onSelect((index: number) => {
            const valueIndex = values.includes(current) ? index : index - 1;
            if (valueIndex < 0 || valueIndex >= values.length) return;
            this.saveHost(ns, field, values[valueIndex]);
          })
      }
    }.width('100%').constraintSize({ minHeight: 54 }).padding({ left: 14, right: 12 })
  }

  @Builder
  private dshSettingsPage() {
    Column() {
      this.pageHeader('DSH 设置')
      Scroll() {
        Column({ space: 10 }) {
          if (this.hasHost('ui-chat')) {
            Column() {
              this.hostChoice('工作步骤展示', 'transcriptView',
                ['compact', 'standard', 'detailed', 'verbose'], ['简洁', '标准', '详细', '完全展开'], this.chat.mode)
              Divider().strokeWidth(0.5).margin({ left: 14 }).color(this.dark ? '#323236' : '#E9EAEC')
              this.hostChoice('过程收起时机', 'collapseTiming',
                ['completion', 'next-input'], ['完成时', '下次发送时'], this.chat.collapseTiming)
              if (this.chat.mode !== 'verbose') {
                Divider().strokeWidth(0.5).margin({ left: 14 }).color(this.dark ? '#323236' : '#E9EAEC')
                this.hostChoice('收起后显示回复', 'foldedReplies',
                  ['all', 'final'], ['全部回复', '仅最终回答'], this.chat.foldedReplies)
              }
            }.width('100%').borderRadius(16).clip(true).backgroundColor(this.dark ? '#232326' : '#FFFFFF')
          }
          if (this.hasHost('ui-conversation')) {
            Column() {
              this.hostChoice('运行时发送', 'busyEnter',
                ['queue', 'steer'], ['排队', '立即干预'], this.chat.busyEnter, 'ui-conversation')
            }.width('100%').borderRadius(16).clip(true).backgroundColor(this.dark ? '#232326' : '#FFFFFF')
          }
          if (this.hostLoading) {
            Row({ space: 8 }) {
              LoadingProgress().width(15).height(15)
              Text('正在读取 DSH 设置').fontSize(12).fontColor(this.dark ? '#8E9197' : '#777B81')
            }.padding(14)
          }
          if (!this.hostLoading && !this.host.namespaces.length && !this.hostError) {
            Text('当前 DSH 服务未提供可写设置').fontSize(13).padding(14)
              .fontColor(this.dark ? '#8E9197' : '#777B81')
          }
          if (!this.hostLoading && this.host.namespaces.length && !this.host.writable) {
            Text('当前 DSH 服务未开放设置写入').fontSize(13).padding(14)
              .fontColor(this.dark ? '#8E9197' : '#777B81')
          }
          if (this.hostError) {
            Row({ space: 8 }) {
              Text(this.hostError).fontSize(12).layoutWeight(1)
                .fontColor(this.dark ? '#FF9999' : '#B83A3A')
              Button('重试', { type: ButtonType.Normal }).height(34).fontSize(12)
                .onClick(() => { this.retryHostWrite(); })
            }.padding(14).borderRadius(14).backgroundColor(this.dark ? '#2B2224' : '#FDECEC')
          }
        }.padding({ left: 16, right: 16, top: 4, bottom: this.safeBottom + 28 }).width('100%')
          .constraintSize({ maxWidth: 680 }).alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
    }.padding({ top: this.safeTop, left: 4, right: 4 }).width('100%').height('100%')
      .backgroundColor(this.dark ? '#171719' : '#F5F6F8')
      .transition(NativeExperience.reducedMotion() ? TransitionEffect.IDENTITY :
        TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 8 })))
  }

  @Builder
  private toggleRow(key: string, title: string, detail: string, enabled: boolean,
    unavailable: string = '', showToggle: boolean = true) {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(title).fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor(this.dark ? '#F0F1F2' : '#24262A')
        if (detail) Text(detail).fontSize(11).maxLines(2)
          .fontColor(this.dark ? '#85888D' : '#85888D')
        if (unavailable) Text(unavailable).fontSize(11)
          .fontColor(this.dark ? '#C9A66C' : '#8B641F')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (this.pendingFor(key)) LoadingProgress().width(18).height(18)
      else if (showToggle) {
        Toggle({ type: ToggleType.Switch, isOn: enabled })
          .enabled(!this.initializing && unavailable.length === 0)
          .selectedColor(this.dark ? '#83AFFF' : '#3B66D4')
          .onChange((value: boolean) => { this.setting(key, value); })
      }
    }.width('100%').constraintSize({ minHeight: 54 }).padding({ left: 14, right: 12, top: 7, bottom: 7 })
  }

  @Builder
  private themeChoice(mode: string, icon: string, label: string) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 7 }) {
        DSHIcon({ glyph: icon, glyphSize: 19,
          color: this.themeMode === mode ? this.dark ? '#F9FAFB' : '#17181B' : this.dark ? '#A8ABB0' : '#777B81' })
        Text(label).fontSize(12)
          .fontColor(this.themeMode === mode ? this.dark ? '#F9FAFB' : '#17181B' : this.dark ? '#A8ABB0' : '#777B81')
      }
    }.layoutWeight(1).height(70).borderRadius(12)
      .backgroundColor(this.themeMode === mode ? this.dark ? '#34353A' : '#E8ECF2' :
        this.dark ? '#28292C' : '#F4F5F7')
      .border({ width: this.themeMode === mode ? 1 : 0,
        color: this.themeMode === mode ? this.dark ? '#747A84' : '#9AA3B0' : Color.Transparent })
      .enabled(!this.initializing && !this.pendingFor('theme'))
      .onClick(() => { this.theme(mode); })
  }

  @Builder
  private appearancePage() {
    Column() {
      this.pageHeader('外观与动效')
      Scroll() {
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            this.themeChoice('light', 'light-outline', '浅色')
            this.themeChoice('dark', 'dark-outline', '深色')
            this.themeChoice('system', 'followsystem-outline', '跟随系统')
          }.width('100%').padding(6).borderRadius(16).backgroundColor(this.dark ? '#232326' : '#FFFFFF')
          Column() {
            this.toggleRow('reduceMotion', '减少动态效果', '关闭页面与抽屉动画', this.reduceMotion)
            Divider().strokeWidth(0.5).margin({ left: 14 }).color(this.dark ? '#323236' : '#E9EAEC')
            this.toggleRow('reduceTransparency', '减少透明效果', '使用不透明表面', this.reduceTransparency)
          }.width('100%').borderRadius(16).clip(true).backgroundColor(this.dark ? '#232326' : '#FFFFFF')
          if (this.error) Text(this.error).fontSize(12)
            .fontColor(this.dark ? '#FF9999' : '#B83A3A').padding(12)
          if (this.status) Text(this.status).fontSize(12)
            .fontColor(this.dark ? '#8E9197' : '#777B81').padding(8)
        }.padding({ left: 16, right: 16, top: 4, bottom: this.safeBottom + 28 }).width('100%')
          .constraintSize({ maxWidth: 680 }).alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
    }.padding({ top: this.safeTop, left: 4, right: 4 }).width('100%').height('100%')
      .backgroundColor(this.dark ? '#171719' : '#F5F6F8')
      .transition(NativeExperience.reducedMotion() ? TransitionEffect.IDENTITY :
        TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 8 })))
  }

  @Builder
  private notificationLevelButton(category: string, levelValue: string, label: string) {
    Button(label, { type: ButtonType.Normal }).layoutWeight(1).height(30).fontSize(10).borderRadius(8)
      .backgroundColor(this.notificationValue(category) === levelValue ? this.dark ? '#B8CFFF' : '#254DAB' :
        this.dark ? '#313236' : '#F0F1F3')
      .fontColor(this.notificationValue(category) === levelValue ? this.dark ? '#101216' : '#FFFFFF' :
        this.dark ? '#B5B7BB' : '#5F6369')
      .enabled(!this.initializing && !this.pushBusy() && !this.pendingFor('notification:' + category))
      .onClick(() => { this.saveNotificationLevel(category, levelValue); })
  }

  @Builder
  private notificationRow(title: string, detail: string, category: string) {
    Column({ space: 7 }) {
      Row() {
        Column({ space: 2 }) {
          Text(title).fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor(this.dark ? '#F0F1F2' : '#24262A')
          Text(detail).fontSize(11).fontColor(this.dark ? '#85888D' : '#85888D')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (this.pendingFor('notification:' + category)) LoadingProgress().width(15).height(15)
      }.width('100%')
      Row({ space: 4 }) {
        this.notificationLevelButton(category, 'off', '关闭')
        this.notificationLevelButton(category, 'quiet', '静默')
        this.notificationLevelButton(category, 'standard', '标准')
        this.notificationLevelButton(category, 'prominent', '醒目')
      }.width('100%')
    }.width('100%').padding({ left: 14, right: 12, top: 10, bottom: 10 })
  }

  @Builder
  private actionRow(title: string, detail: string, command: string, destructive: boolean = false) {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(title).fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor(destructive ? this.dark ? '#FF9999' : '#B83A3A' : this.dark ? '#F0F1F2' : '#24262A')
        if (detail) Text(detail).fontSize(11).fontColor(this.dark ? '#85888D' : '#85888D')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (this.pendingFor(command)) LoadingProgress().width(17).height(17)
      else DSHIcon({ glyph: 'chevron-left-outline', glyphSize: 13,
        color: this.dark ? '#686B70' : '#A2A5AA' }).rotate({ angle: 180 })
    }.width('100%').constraintSize({ minHeight: 54 }).padding({ left: 14, right: 13, top: 7, bottom: 7 })
      .enabled(!this.initializing && !this.pendingFor(command))
      .onClick(() => { this.action(command); })
  }

  @Builder
  private notificationsPage() {
    Column() {
      this.pageHeader('通知')
      Scroll() {
        Column({ space: 10 }) {
          this.sectionLabel('通知级别')
          Column() {
            this.notificationRow('需要确认', '等待你批准或选择', 'approval')
            Divider().strokeWidth(0.5).margin({ left: 14 }).color(this.dark ? '#323236' : '#E9EAEC')
            this.notificationRow('任务失败', '任务异常结束', 'failed')
            Divider().strokeWidth(0.5).margin({ left: 14 }).color(this.dark ? '#323236' : '#E9EAEC')
            this.notificationRow('任务完成', '任务正常结束', 'completed')
            Divider().strokeWidth(0.5).margin({ left: 14 }).color(this.dark ? '#323236' : '#E9EAEC')
            this.notificationRow('连接异常', '服务连接中断', 'connection')
          }.width('100%').borderRadius(16).clip(true).backgroundColor(this.dark ? '#232326' : '#FFFFFF')
          this.sectionLabel('投递')
          Column() {
            if (this.supportsPush) {
              this.actionRow(this.pushEnabled ? '关闭系统推送' : '开启系统推送',
                this.pushEnabled ? 'Push Kit 已注册' : '在当前设备上接收后台通知',
                this.pushEnabled ? 'disablePush' : 'enablePush')
              Divider().strokeWidth(0.5).margin({ left: 14 }).color(this.dark ? '#323236' : '#E9EAEC')
              this.actionRow('发送测试通知', '验证通知权限和跳转', 'testNotification')
            } else {
              this.toggleRow('backgroundMonitor', '后台任务监控',
                '商店版本无 Push Kit；任务运行时保持后台连接', this.backgroundMonitor)
              Divider().strokeWidth(0.5).margin({ left: 14 }).color(this.dark ? '#323236' : '#E9EAEC')
              this.actionRow('发送测试通知', '验证本地通知权限', 'testNotification')
            }
            Divider().strokeWidth(0.5).margin({ left: 14 }).color(this.dark ? '#323236' : '#E9EAEC')
            this.actionRow('系统通知设置',
              !this.notificationPermissionKnown ? '通知权限状态未知' :
                this.notificationsEnabled ? '通知权限已开启' : '通知权限已关闭', 'notificationSettings')
          }.width('100%').borderRadius(16).clip(true).backgroundColor(this.dark ? '#232326' : '#FFFFFF')
          if (!this.supportsPush) {
            Text('无 Push Kit · 后台运行受系统限制')
              .fontSize(11).lineHeight(17).padding({ left: 5, right: 5 })
              .fontColor(this.dark ? '#85888D' : '#777B81')
          }
          if (this.error) Text(this.error).fontSize(12).padding(12)
            .fontColor(this.dark ? '#FF9999' : '#B83A3A')
          if (this.status) Text(this.status).fontSize(12).padding(8)
            .fontColor(this.dark ? '#8E9197' : '#777B81')
        }.padding({ left: 16, right: 16, top: 4, bottom: this.safeBottom + 28 }).width('100%')
          .constraintSize({ maxWidth: 680 }).alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
    }.padding({ top: this.safeTop, left: 4, right: 4 }).width('100%').height('100%')
      .backgroundColor(this.dark ? '#171719' : '#F5F6F8')
      .transition(NativeExperience.reducedMotion() ? TransitionEffect.IDENTITY :
        TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 8 })))
  }

  @Builder
  private cardsPage() {
    Column() {
      this.pageHeader('桌面卡片')
      Scroll() {
        Column({ space: 10 }) {
          Column() {
            this.toggleRow('widgetDetails', '显示任务名称', '关闭后仍显示匿名数量和状态', this.widgetDetails)
            Divider().strokeWidth(0.5).margin({ left: 14 }).color(this.dark ? '#323236' : '#E9EAEC')
            this.actionRow('立即同步', '刷新运行、待确认、完成与失败数量', 'sync')
          }.width('100%').borderRadius(16).clip(true).backgroundColor(this.dark ? '#232326' : '#FFFFFF')
          if (this.error) Text(this.error).fontSize(12).padding(12)
            .fontColor(this.dark ? '#FF9999' : '#B83A3A')
          if (this.status) Text(this.status).fontSize(12).padding(8)
            .fontColor(this.dark ? '#8E9197' : '#777B81')
        }.padding({ left: 16, right: 16, top: 4, bottom: this.safeBottom + 28 }).width('100%')
          .constraintSize({ maxWidth: 680 }).alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
    }.padding({ top: this.safeTop, left: 4, right: 4 }).width('100%').height('100%')
      .backgroundColor(this.dark ? '#171719' : '#F5F6F8')
      .transition(NativeExperience.reducedMotion() ? TransitionEffect.IDENTITY :
        TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 8 })))
  }

  @Builder
  private connectionPage() {
    Column() {
      this.pageHeader('服务与账户')
      Scroll() {
        Column({ space: 10 }) {
          Column({ space: 7 }) {
            Text('当前服务').fontSize(12).fontColor(this.dark ? '#85888D' : '#777B81')
            Text(this.serverOrigin).fontSize(14).width('100%').wordBreak(WordBreak.BREAK_ALL)
              .fontColor(this.dark ? '#F0F1F2' : '#24262A').copyOption(CopyOptions.InApp)
          }.padding(14).width('100%').borderRadius(16).backgroundColor(this.dark ? '#232326' : '#FFFFFF')
          Column() {
            this.actionRow('界面模式', '原生或兼容网页', 'modes')
            Divider().strokeWidth(0.5).margin({ left: 14 }).color(this.dark ? '#323236' : '#E9EAEC')
            this.actionRow('退出登录', '清除当前连接与本地会话缓存，返回登录页', 'logout', true)
          }.width('100%').borderRadius(16).clip(true).backgroundColor(this.dark ? '#232326' : '#FFFFFF')
          if (this.error) Text(this.error).fontSize(12).padding(12)
            .fontColor(this.dark ? '#FF9999' : '#B83A3A')
        }.padding({ left: 16, right: 16, top: 4, bottom: this.safeBottom + 28 }).width('100%')
          .constraintSize({ maxWidth: 680 }).alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
    }.padding({ top: this.safeTop, left: 4, right: 4 }).width('100%').height('100%')
      .backgroundColor(this.dark ? '#171719' : '#F5F6F8')
      .transition(NativeExperience.reducedMotion() ? TransitionEffect.IDENTITY :
        TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 8 })))
  }

  build() {
    if (this.settingsPage === 'dsh') this.dshSettingsPage()
    else if (this.settingsPage === 'appearance') this.appearancePage()
    else if (this.settingsPage === 'notifications') this.notificationsPage()
    else if (this.settingsPage === 'cards') this.cardsPage()
    else if (this.settingsPage === 'connection') this.connectionPage()
    else if (this.settingsPage === 'about') {
      Column() {
        this.pageHeader('关于')
        AboutSettings({ embedded: true, onBack: (): void => { this.openPage('root'); } }).layoutWeight(1)
      }.padding({ top: this.safeTop, left: 4, right: 4 }).width('100%').height('100%')
        .backgroundColor(this.dark ? '#171719' : '#F5F6F8')
        .transition(NativeExperience.reducedMotion() ? TransitionEffect.IDENTITY :
          TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 8 })))
    }
    else this.settingsRoot()
  }
}
