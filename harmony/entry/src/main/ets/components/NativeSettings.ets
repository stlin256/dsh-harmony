import { http } from '@kit.NetworkKit';
import { NativeHarnessClient } from '../services/NativeHarnessClient';

class SettingsState {
  themeMode: string = 'system';
  reduceMotion: boolean = false;
  reduceTransparency: boolean = false;
  widgetDetails: boolean = false;
}

@Component
export struct NativeSettings {
  client: NativeHarnessClient = new NativeHarnessClient('');
  invoke: (command: string, value: string) => Promise<string> = async (): Promise<string> => '';
  onReturn: () => void = (): void => {};
  onModes: () => void = (): void => {};
  onLogin: () => void = (): void => {};
  @StorageLink('nativeAppActive') @Watch('activityChanged') private active: boolean = true;
  @StorageLink('nativeDark') private dark: boolean = false;
  @State private themeMode: string = 'system';
  @State private reduceMotion: boolean = false;
  @State private reduceTransparency: boolean = false;
  @State private widgetDetails: boolean = false;
  @State private busy: boolean = true;
  @State private status: string = '';
  private mounted: boolean = false;
  private widgetTimer: number = -1;

  aboutToAppear(): void {
    this.mounted = true;
    this.initialize().catch(() => { this.status = '读取设置失败，请返回后重试'; this.busy = false; });
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
    this.reduceMotion = state.reduceMotion; this.reduceTransparency = state.reduceTransparency; this.widgetDetails = state.widgetDetails;
    this.busy = false;
    await this.syncPassive();
  }
  private async theme(value: string): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try { await this.invoke('themeMode', value); this.themeMode = value; }
    catch (_) { this.status = '外观设置保存失败'; }
    finally { this.busy = false; }
  }
  private async setting(command: string, value: boolean): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try {
      await this.invoke(command, value ? 'true' : 'false');
      if (command === 'reduceMotion') this.reduceMotion = value;
      if (command === 'reduceTransparency') this.reduceTransparency = value;
      if (command === 'widgetDetails') this.widgetDetails = value;
      this.status = '设置已保存';
    } catch (_) { this.status = '设置保存失败，请重试'; }
    finally { this.busy = false; }
  }
  private async action(command: string): Promise<void> {
    if (this.busy) return;
    this.busy = true; this.status = '';
    try {
      const state = await this.client.state();
      if (!state.authenticated) { this.onLogin(); return; }
      if (command === 'enablePush') {
        if (!state.pushConfigured) { this.status = '服务端尚未配置系统通知'; return; }
        if (state.mode === 'none') await this.client.request('/pocket/api/auth/none', http.RequestMethod.POST, '{}');
        const token = await this.invoke('enablePush', '');
        const id = await this.invoke('deviceId', '');
        await this.client.request('/pocket/api/device', http.RequestMethod.POST, JSON.stringify({ id: id, token: token }));
        this.status = '通知已开启';
      } else if (command === 'disablePush') {
        await this.client.request('/pocket/api/device', http.RequestMethod.DELETE, JSON.stringify({ allForSession: true }));
        await this.invoke('disablePush', ''); this.status = '当前登录会话的通知已关闭';
      } else if (command === 'sync') {
        const value = await this.client.request('/pocket/api/overview');
        await this.invoke('widgetSnapshot', value); this.status = '桌面卡片快照已同步';
      } else if (command === 'logout') {
        await this.client.request('/pocket/api/logout', http.RequestMethod.POST, '{}');
        await this.invoke('clearSession', '');
      }
    } catch (_) { this.status = '操作失败，请检查登录状态和网络后重试'; }
    finally { this.busy = false; }
  }

  @Builder
  private heading(title: string, detail: string) {
    Text(title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.dark ? '#F9FAFB' : '#0F1115')
    Text(detail).fontSize(12).lineHeight('20fp').fontColor(this.dark ? '#CFD3D6' : '#61666B')
  }
  @Builder
  private actionButton(label: string, command: string) {
    Button(label, { type: ButtonType.Normal }).height(44).fontSize(13).borderRadius(12)
      .backgroundColor(this.dark ? '#353638' : '#F5F6F7').fontColor(this.dark ? '#F9FAFB' : '#0F1115')
      .enabled(!this.busy).onClick(() => { this.action(command); })
  }
  build() {
    Scroll() {
      Column({ space: 16 }) {
        Row() {
          Text('应用设置').fontSize(22).fontWeight(FontWeight.Medium).layoutWeight(1)
            .fontColor(this.dark ? '#F9FAFB' : '#0F1115')
          Button('返回', { type: ButtonType.Normal }).height(44).fontSize(13).borderRadius(12)
            .backgroundColor(Color.Transparent).fontColor(this.dark ? '#CFD3D6' : '#61666B').onClick(this.onReturn)
        }.width('100%')
        this.heading('界面模式', '原生模式使用 ArkUI 组件；完整插件界面和高级交互可在兼容模式中使用。')
        Button('切换界面模式', { type: ButtonType.Normal }).height(44).fontSize(13).borderRadius(12)
          .backgroundColor(this.dark ? '#353638' : '#F5F6F7').fontColor(this.dark ? '#F9FAFB' : '#0F1115').onClick(this.onModes)
        Divider().color(this.dark ? '#353638' : '#EBEEF2')
        this.heading('外观与动效', '保持 Harness 中性设计，系统减少动态效果始终优先。')
        Row({ space: 8 }) {
          ForEach(['system', 'light', 'dark'], (mode: string) => {
            Button((this.themeMode === mode ? '✓ ' : '') + (mode === 'system' ? '跟随系统' : mode === 'light' ? '浅色' : '深色'), { type: ButtonType.Normal })
              .height(44).fontSize(12).borderRadius(12).layoutWeight(1)
              .backgroundColor(this.dark ? '#353638' : '#F5F6F7').fontColor(this.dark ? '#F9FAFB' : '#0F1115')
              .enabled(!this.busy).onClick(() => { this.theme(mode); })
          }, (mode: string) => mode)
        }.width('100%')
        Row() {
          Text('减少透明效果').fontSize(14).layoutWeight(1).fontColor(this.dark ? '#F9FAFB' : '#0F1115')
          Toggle({ type: ToggleType.Switch, isOn: this.reduceTransparency }).enabled(!this.busy)
            .accessibilityText('减少透明效果').onChange((value: boolean) => { this.setting('reduceTransparency', value); })
        }.width('100%').constraintSize({ minHeight: 44 })
        Row() {
          Text('减少动态效果').fontSize(14).layoutWeight(1).fontColor(this.dark ? '#F9FAFB' : '#0F1115')
          Toggle({ type: ToggleType.Switch, isOn: this.reduceMotion }).enabled(!this.busy)
            .accessibilityText('减少动态效果').onChange((value: boolean) => { this.setting('reduceMotion', value); })
        }.width('100%').constraintSize({ minHeight: 44 })
        Divider().color(this.dark ? '#353638' : '#EBEEF2')
        this.heading('通知', '任务完成、失败和需要审批时提醒。关闭操作会撤销当前登录会话的通知注册。')
        Row({ space: 8 }) { this.actionButton('开启通知', 'enablePush'); this.actionButton('关闭通知', 'disablePush') }
        Divider().color(this.dark ? '#353638' : '#EBEEF2')
        this.heading('桌面卡片', '长按桌面 DSH Harmony 图标添加 2×2 入口或 2×4 概览。卡片只保留带时间的匿名快照。')
        Row() {
          Text('显示匿名任务数量').fontSize(14).layoutWeight(1).fontColor(this.dark ? '#F9FAFB' : '#0F1115')
          Toggle({ type: ToggleType.Switch, isOn: this.widgetDetails }).enabled(!this.busy)
            .accessibilityText('卡片显示匿名任务数量').onChange((value: boolean) => { this.setting('widgetDetails', value); })
        }.width('100%').constraintSize({ minHeight: 44 })
        this.actionButton('同步桌面卡片', 'sync')
        Divider().color(this.dark ? '#353638' : '#EBEEF2')
        this.heading('连接管理', '退出会撤销登录和通知注册，并清除本机网页数据及桌面快照。')
        this.actionButton('退出当前连接', 'logout')
        if (this.status) { Text(this.status).fontSize(12).lineHeight('20fp').fontColor(this.dark ? '#CFD3D6' : '#61666B') }
        Text('DSH Harmony · 原生模式（实验）').fontSize(11).fontColor(this.dark ? '#CFD3D6' : '#61666B')
      }.padding(24).width('100%').constraintSize({ maxWidth: 680 }).alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').backgroundColor(this.dark ? '#151517' : '#FFFFFF')
  }
}
