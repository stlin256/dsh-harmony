import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { http } from '@kit.NetworkKit';
import { picker } from '@kit.CoreFileKit';
import { PocketBridge } from '../services/PocketBridge';
import { WindowAppearance } from '../services/WindowAppearance';
import { NativeHarnessClient } from '../services/NativeHarnessClient';
import { NativeWorkspace } from '../components/NativeWorkspace';
import { NativeCompatibilitySurface } from '../components/NativeCompatibilitySurface';
import { NativeSettings } from '../components/NativeSettings';
import { NativeExperience } from '../services/NativeExperience';
import { PushKitAdapter } from 'entry/PushKitAdapter';

@Entry
@Component
struct Index {
  private controller: webview.WebviewController = new webview.WebviewController();
  private context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
  private store: preferences.Preferences | null = null;
  private bridge: PocketBridge | null = null;
  private presentation: string = '';
  private nativeClient: NativeHarnessClient = new NativeHarnessClient('');
  @StorageLink('systemDark') @Watch('applyNativeTheme') private systemDark: boolean = false;
  @StorageLink('nativeThemeMode') @Watch('applyNativeTheme') private nativeThemeMode: string = 'system';
  @StorageLink('uiMode') @Watch('modeChanged') private uiMode: string = 'compatibility';
  @StorageLink('nativeAuthRevision') @Watch('authenticated') private authRevision: number = 0;
  @State private authSurface: boolean = false;
  @State private compatibilitySurface: boolean = false;
  @State @Watch('settingsChanged') private nativeSettings: boolean = false;
  @State private connectionManager: boolean = false;
  @State private modePicker: boolean = false;
  @StorageLink('nativeTitleHeight') private titleHeight: number = 56;
  @StorageLink('nativeDark') private nativeDark: boolean = false;
  @StorageLink('nativeAppActive') @Watch('activityChanged') private appActive: boolean = true;
  @StorageLink('pocketForegroundRevision') @Watch('resumePage') private foregroundRevision: number = 0;
  @StorageLink('requestedPocketRoute') @Watch('openPocketRoute') private requestedPocketRoute: string = '';
  @State private origin: string = '';
  private authOrigin: string = '';
  private proxyAuth: boolean = false;
  @State private address: string = '';
  @State private mode: string = 'native';
  @State private accessKey: string = '';
  @State private ready: boolean = false;
  @State private busy: boolean = false;
  @State private error: string = '';
  @State private progress: number = 0;
  @StorageLink('requestedSession') @Watch('openNotification') private requestedSession: string = '';

  aboutToAppear(): void {
    this.initialize().catch((error: Error) => { this.error = error.message || '连接失败'; });
  }

  private async initialize(): Promise<void> {
    this.presentation = util.TextDecoder.create('utf-8').decodeToString(
      await this.context.resourceManager.getRawFileContent('presentation.js'));
    this.store = await preferences.getPreferences(this.context, { name: 'dsh-pocket' });
    const savedMode = this.store.getSync('uiMode', 'compatibility') as string;
    this.uiMode = savedMode === 'native' ? 'native' : 'compatibility';
    this.address = this.store.getSync('origin', '') as string;
    this.mode = this.store.getSync('mode', 'native') === 'passkey' ? 'passkey' : 'native';
    if (this.normalize(this.address)) await this.connect();
  }

  private normalize(input: string): string {
    const value = input.trim().replace(/\/+$/, '').toLowerCase();
    if (!/^https?:\/\/(?:[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?|\[[0-9a-f:]+\])(?::[0-9]{1,5})?$/.test(value)) return '';
    const port = value.match(/:([0-9]+)$/);
    if (port && (Number(port[1]) < 1 || Number(port[1]) > 65535)) return '';
    return value;
  }

  private async connect(): Promise<void> {
    const next = this.normalize(this.address);
    if (!next) { this.error = '请输入有效的服务地址'; return; }
    if (this.mode === 'passkey' && !next.startsWith('https://')) { this.error = 'Passkey 登录需要 HTTPS'; return; }
    this.busy = true;
    try {
      if (this.origin && this.origin !== next) throw new Error('请先退出当前连接');
      this.origin = next;
      this.nativeClient = new NativeHarnessClient(next);
      let state = await this.nativeClient.state();
      if (this.mode === 'native') {
        if (state.mode !== 'host') throw new Error('此服务需要 Passkey 登录');
        if (!state.authenticated) {
          if (!this.accessKey.trim()) throw new Error('请输入访问密钥');
          await this.nativeClient.loginNative(this.accessKey.trim());
          state = await this.nativeClient.state();
          if (!state.authenticated) throw new Error('登录失败，请检查访问密钥');
        }
      } else if (state.mode !== 'proxy' && state.mode !== 'passkey') throw new Error('此服务未启用 Passkey 登录');
      this.proxyAuth = state.mode === 'proxy';
      this.authOrigin = this.proxyAuth ? this.normalize(state.authOrigin) : '';
      if (this.authOrigin && !this.authOrigin.startsWith('https://')) throw new Error('认证服务需要 HTTPS');
      if (this.proxyAuth && !this.authOrigin) throw new Error('网关未提供有效的认证服务地址');
      this.bridge = new PocketBridge(this.context, this.controller, next, async (): Promise<void> => {
        await this.resetConnectionState();
      });
      this.store?.putSync('origin', next);
      this.store?.putSync('mode', this.mode);
      await this.store?.flush();
      this.error = '';
      this.accessKey = '';
      this.ready = true;
      if (this.uiMode === 'native') this.openPocketRoute();
    } catch (error) {
      this.origin = ''; this.ready = false;
      throw new Error(error instanceof Error ? error.message : '连接失败');
    } finally { this.busy = false; }
  }

  private allowed(url: string): boolean {
    return url === this.origin || url.startsWith(this.origin + '/');
  }
  private allowedNavigation(url: string): boolean {
    return this.allowed(url) || (this.authOrigin.length > 0 && (url === this.authOrigin || url.startsWith(this.authOrigin + '/')));
  }
  private async checkAuthentication(): Promise<void> {
    if (!this.proxyAuth || !this.ready) return;
    try {
      const state = await this.nativeClient.state();
      if (state.authenticated) await this.invokeNative('nativeAuthenticated', '');
    } catch (_) {}
  }

  private openNotification(): void {
    if (this.uiMode === 'native' && !this.authSurface) return;
    if (!this.ready || !this.requestedSession || !this.allowed(this.controller.getUrl())) return;
    // Gateway persists the session hint; it does not invent a Harness SPA route.
    this.controller.loadUrl(this.origin + '/?dshHarmonySession=' + encodeURIComponent(this.requestedSession));
    this.requestedSession = '';
  }

  private resumePage(): void {
    if (!this.ready || (this.uiMode === 'native' && !this.authSurface)) return;
    try {
      if (this.allowed(this.controller.getUrl())) {
        this.controller.runJavaScript('window.__pocketResumeOverview?.()').catch(() => {});
      }
    } catch (_) {}
  }

  private activityChanged(): void {
    if (this.appActive) { this.resumePage(); return; }
    this.nativeClient.pause();
    try { this.controller.runJavaScript('window.__pocketSuspendOverview?.()').catch(() => {}); } catch (_) {}
  }

  private openPocketRoute(): void {
    if (!this.ready || !this.requestedPocketRoute) return;
    if (this.requestedPocketRoute === 'settings') {
      this.nativeSettings = true; this.requestedPocketRoute = ''; return;
    }
    if (this.uiMode === 'native' && !this.authSurface) {
      this.nativeSettings = this.requestedPocketRoute !== 'workspace';
      this.requestedPocketRoute = ''; return;
    }
    try { if (!this.allowed(this.controller.getUrl())) return; } catch (_) { return; }
    const route = this.requestedPocketRoute;
    this.requestedPocketRoute = '';
    const path = route === 'workspace' ? '/' : route === 'overview' ? '/pocket/?section=widgets' : '/pocket/';
    this.controller.loadUrl(this.origin + path);
  }

  private modeChanged(): void {
    this.getUIContext().setKeyboardAvoidMode(this.uiMode === 'native' ? KeyboardAvoidMode.RESIZE : KeyboardAvoidMode.OFFSET);
    this.nativeClient.pause(); this.compatibilitySurface = false;
    AppStorage.setOrCreate<boolean>('nativeCompatibilityActive', false);
    this.authSurface = false; AppStorage.setOrCreate<boolean>('nativeAuthSurface', false); this.nativeSettings = false;
    this.error = '';
    if (this.uiMode === 'native') {
      this.applyNativeTheme();
      try { this.controller.runJavaScript('window.__pocketSuspendOverview?.()').catch(() => {}); } catch (_) {}
      this.openPocketRoute();
    }
  }
  private applyNativeTheme(): void {
    const shell = !this.ready || this.nativeSettings || this.connectionManager ||
      (this.uiMode === 'native' && !this.authSurface && !this.compatibilitySurface);
    AppStorage.setOrCreate<boolean>('nativeShellForeground', shell);
    AppStorage.setOrCreate<boolean>('pocketPageThemeKnown', true);
    WindowAppearance.apply(this.nativeThemeMode === 'dark' || (this.nativeThemeMode === 'system' && this.systemDark));
    if (!shell && AppStorage.get<boolean>('nativeWebThemeKnown') === true) WindowAppearance.applyBars(AppStorage.get<boolean>('nativeWebDark') === true);
  }
  private loginSurface(): void {
    this.invokeNative('widgetDisconnected', '').catch(() => {});
    AppStorage.setOrCreate<boolean>('nativeAuthSurface', true);
    this.authSurface = true;
  }
  private authenticated(): void { if (this.uiMode === 'native') { this.authSurface = false; AppStorage.setOrCreate<boolean>('nativeAuthSurface', false); this.applyNativeTheme(); } }
  private async selectMode(mode: string): Promise<void> {
    this.modePicker = false;
    if (this.bridge) await this.bridge.performNative('uiMode', mode);
    else {
      this.uiMode = mode; this.store?.putSync('uiMode', mode); await this.store?.flush();
    }
  }
  private async invokeNative(command: string, value: string): Promise<string> {
    if (!this.bridge) throw new Error('Not connected');
    return await this.bridge.performNative(command, value);
  }
  private async resetConnectionState(): Promise<void> {
    WindowAppearance.apply(this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    this.nativeClient.pause(); this.nativeClient.drafts.clear(); this.nativeClient.images.clear(); this.nativeClient.uncertain.clear();
    this.authSurface = false; AppStorage.setOrCreate<boolean>('nativeAuthSurface', false);
    this.nativeSettings = false; this.connectionManager = false; this.compatibilitySurface = false;
    AppStorage.setOrCreate<boolean>('nativeCompatibilityActive', false);
    this.ready = false; this.origin = ''; this.authOrigin = ''; this.proxyAuth = false; this.address = ''; this.accessKey = ''; this.error = '';
    this.bridge = null; this.controller = new webview.WebviewController();
    this.nativeClient = new NativeHarnessClient('');
    this.requestedPocketRoute = ''; this.requestedSession = '';
    try { this.store?.putSync('origin', ''); await this.store?.flush(); } catch (_) {}
  }
  private async disconnectConnection(): Promise<void> {
    this.busy = true;
    try {
      // Server logout is best effort: a failed or expired login must still be
      // escapable, so local cookies and the saved origin are always cleared.
      try { await this.nativeClient.request('/pocket/api/logout', http.RequestMethod.POST, '{}'); } catch (_) {}
      if (this.bridge) {
        try { await this.bridge.performNative('clearSession', ''); return; } catch (_) {}
      }
      try { await webview.WebCookieManager.clearAllCookies(); } catch (_) {}
      try { webview.WebStorage.deleteAllData(); } catch (_) {}
      await this.resetConnectionState();
    } finally { this.busy = false; }
  }
  private compatibility(): void {
    AppStorage.setOrCreate<boolean>('nativeCompatibilityActive', true);
    this.compatibilitySurface = true;
  }
  private closeCompatibility(): void {
    this.compatibilitySurface = false;
    AppStorage.setOrCreate<boolean>('nativeCompatibilityActive', false);
    this.applyNativeTheme();
  }
  @Builder
  private compatibilitySheet() {
    NativeCompatibilitySurface({ origin: this.origin, sessionId: this.nativeClient.selectedId,
      onClose: (): void => { this.closeCompatibility(); } })
  }
  @Builder
  private settingsSheet() {
    NativeSettings({ client: this.nativeClient, serverOrigin: this.origin,
      invoke: (command: string, value: string): Promise<string> => this.invokeNative(command, value),
      onReturn: (): void => { this.nativeSettings = false; },
      onModes: (): void => { this.modePicker = true; },
      onConnection: (): void => { this.nativeSettings = false; this.connectionManager = true; },
      onLogin: (): void => { this.loginSurface(); },
      onLogout: (): Promise<void> => this.disconnectConnection() })
  }
  private settingsChanged(): void {
    if (!this.nativeSettings) AppStorage.setOrCreate<string>('nativeSettingsPage', 'root');
    this.applyNativeTheme();
  }
  private refreshContent(): void {
    if (this.uiMode === 'native' && !this.authSurface) {
      this.nativeSettings = false;
      AppStorage.setOrCreate<number>('nativeRefreshRevision', (AppStorage.get<number>('nativeRefreshRevision') || 0) + 1);
    } else this.controller.refresh();
  }

  @Builder
  private modeSheet() {
    Column({ space: 16 }) {
      Text('界面模式').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.nativeDark ? '#F9FAFB' : '#0F1115')
      Button((this.uiMode === 'compatibility' ? '✓  ' : '') + '兼容模式', { type: ButtonType.Normal })
        .width('100%').height(48).borderRadius(12).fontSize(14)
        .backgroundColor(this.nativeDark ? '#353638' : '#F5F6F7').fontColor(this.nativeDark ? '#F9FAFB' : '#0F1115')
        .onClick(() => { this.selectMode('compatibility').catch(() => { this.error = '切换失败，请重试'; }); })
      Text('Harness 原版网页').fontSize(12).fontColor(this.nativeDark ? '#CFD3D6' : '#61666B')
      Button((this.uiMode === 'native' ? '✓  ' : '') + '原生模式（实验）', { type: ButtonType.Normal })
        .width('100%').height(48).borderRadius(12).fontSize(14)
        .backgroundColor(this.nativeDark ? '#353638' : '#F5F6F7').fontColor(this.nativeDark ? '#F9FAFB' : '#0F1115')
        .onClick(() => { this.selectMode('native').catch(() => { this.error = '切换失败，请重试'; }); })
      Text('切换前请保存未发送的内容。')
        .fontSize(12).lineHeight(20).fontColor(this.nativeDark ? '#CFD3D6' : '#61666B')
    }.padding(24).width('100%').alignItems(HorizontalAlign.Start)
  }

  onBackPress(): boolean {
    if (!this.ready) return false;
    if (this.nativeSettings) {
      if ((AppStorage.get<string>('nativeSettingsPage') || 'root') !== 'root') {
        AppStorage.setOrCreate<string>('nativeSettingsPage', 'root');
      } else this.nativeSettings = false;
      return true;
    }
    if (this.connectionManager) { this.connectionManager = false; return true; }
    if (this.compatibilitySurface) { this.closeCompatibility(); return true; }
    if (this.uiMode === 'native' && !this.authSurface) {
      if (AppStorage.get<boolean>('nativeWorkspaceCanGoBack') === true) {
        AppStorage.setOrCreate<number>('nativeBackRevision', (AppStorage.get<number>('nativeBackRevision') || 0) + 1); return true;
      }
      return false;
    }
    if (this.ready && this.controller.accessBackward()) { this.controller.backward(); return true; }
    return false;
  }

  @Builder
  private pageContent() {
    Stack() {
    Column() {
      if (this.connectionManager) {
        Scroll() {
          Column({ space: 16 }) {
            Text('连接管理').fontSize(24).fontWeight(FontWeight.Medium)
              .fontColor(this.nativeDark ? '#F9FAFB' : '#0F1115')
            Text('当前服务').fontSize(13).fontColor(this.nativeDark ? '#CFD3D6' : '#61666B')
            Text(this.origin).fontSize(14).fontColor(this.nativeDark ? '#F9FAFB' : '#0F1115').copyOption(CopyOptions.InApp)
            Text('退出后可更换服务地址。')
              .fontSize(13).lineHeight(20).fontColor(this.nativeDark ? '#CFD3D6' : '#61666B')
            if (this.uiMode !== 'native' || this.authSurface) {
              Button('打开网页设置', { type: ButtonType.Normal }).height(44).fontSize(13).borderRadius(12)
                .backgroundColor(this.nativeDark ? '#353638' : '#F5F6F7').fontColor(this.nativeDark ? '#F9FAFB' : '#0F1115')
                .onClick(() => { this.connectionManager = false; this.controller.loadUrl(this.origin + '/pocket/'); })
            }
            Button(this.busy ? '正在退出…' : '退出当前连接', { type: ButtonType.Normal }).height(48).fontSize(14).borderRadius(12)
              .width('100%').enabled(!this.busy).backgroundColor(this.nativeDark ? '#4A2224' : '#FDECEC')
              .fontColor(this.nativeDark ? '#FFD7D8' : '#A52025')
              .onClick(() => { this.disconnectConnection().catch(() => { this.error = '退出失败，请重试'; }); })
            Button('返回', { type: ButtonType.Normal }).height(44).fontSize(13).borderRadius(12)
              .backgroundColor(Color.Transparent).fontColor(this.nativeDark ? '#CFD3D6' : '#61666B')
              .onClick(() => { this.connectionManager = false; })
          }.padding(24).width('100%').constraintSize({ maxWidth: 600 }).alignItems(HorizontalAlign.Start)
        }.layoutWeight(1).width('100%')
      } else if (this.ready) {
        if (this.uiMode === 'native' && !this.authSurface) {
          NativeWorkspace({ client: this.nativeClient, context: this.context, supportsPush: PushKitAdapter.supported,
            onLogin: (): void => { this.loginSurface(); },
            onSettings: (): void => { this.nativeSettings = true; },
            onSnapshot: async (value: string): Promise<void> => { await this.invokeNative('widgetSnapshot', value); },
            onLocalNotification: async (sessionId: string, title: string, state: string): Promise<void> => {
              await this.invokeNative('publishLocalNotification', JSON.stringify({ sessionId, title, state }));
            },
            onCompatibility: (): void => { this.compatibility(); } })
        } else {
          if (this.progress < 100) { Progress({ value: this.progress, total: 100 }).width('100%').color(this.nativeDark ? '#5686FE' : '#4176E6').height(2) }
          Web({ src: this.origin + '/pocket/?mode=' + this.mode, controller: this.controller })
            .width('100%').layoutWeight(1)
            .javaScriptAccess(true).domStorageAccess(true).databaseAccess(true)
            .keyboardAvoidMode(WebKeyboardAvoidMode.RESIZE_CONTENT)
            .onRenderExited(() => { this.error = '网页渲染已中断，请点击刷新恢复'; })
            .fileAccess(false).mixedMode(MixedMode.None)
            .darkMode(WebDarkMode.Auto).forceDarkAccess(false)
            .backgroundColor(this.nativeDark ? '#151517' : '#FFFFFF')
            .onControllerAttached(() => {
              if (this.bridge !== null) this.controller.registerJavaScriptProxy(this.bridge, 'dshPocket', ['request']);
            })
            .onLoadIntercept((event) => {
              const blocked = !this.allowedNavigation(event.data.getRequestUrl());
              if (blocked) this.error = '已阻止站外跳转；请在系统浏览器打开外部链接';
              return blocked;
            })
            .onWindowNew((event) => {
              if (this.allowedNavigation(event.targetUrl)) this.controller.loadUrl(event.targetUrl);
            })
            .onProgressChange((event) => { this.progress = event.newProgress; })
            .onPageEnd(() => {
              if (this.allowed(this.controller.getUrl())) this.controller.runJavaScript(this.presentation).catch(() => {});
              if (this.allowed(this.controller.getUrl())) this.checkAuthentication();
              this.openNotification();
              this.openPocketRoute();
            })
            .onErrorReceive((event) => {
              if (event.request.isMainFrame()) this.error = '加载失败，请检查网络和 HTTPS 证书，然后点击刷新';
            })
            .onShowFileSelector((event) => {
              const options = new picker.DocumentSelectOptions();
              options.maxSelectNumber = event.fileSelector.getMode() === FileSelectorMode.FileOpenMultipleMode ? 10 : 1;
              new picker.DocumentViewPicker(this.context).select(options)
                .then((uris: string[]) => event.result.handleFileList(uris))
                .catch(() => event.result.handleFileList([]));
              return true;
            })
        }
      } else {
        Scroll() {
          Column({ space: 16 }) {
            Text('DSH Harmony').fontSize(28).fontWeight(FontWeight.Medium)
              .fontColor(this.nativeDark ? '#F9FAFB' : '#0F1115')
            Text('连接你的 DeepSeek Harness 工作空间').fontSize(14)
              .fontColor(this.nativeDark ? '#CFD3D6' : '#61666B')
            TextInput({ text: this.address, placeholder: 'https://dsh.example.com' })
              .height(48).borderRadius(12)
              .backgroundColor(this.nativeDark ? '#2C2C2E' : '#F5F6F7')
              .fontColor(this.nativeDark ? '#F9FAFB' : '#0F1115')
              .type(InputType.URL).onChange((value: string) => { this.address = value; })
            Button((this.mode === 'native' ? '✓  ' : '') + '原生登录', { type: ButtonType.Normal })
              .height(48).borderRadius(12).fontSize(14)
              .backgroundColor(this.nativeDark ? '#2C2C2E' : '#F5F6F7')
              .fontColor(this.nativeDark ? '#F9FAFB' : '#0F1115')
              .border({ width: 1, color: this.mode === 'native' ? '#ADB2B8' : Color.Transparent })
              .width('100%').onClick(() => { this.mode = 'native'; })
            if (this.mode === 'native') {
              TextInput({ text: this.accessKey, placeholder: '访问密钥' }).type(InputType.Password)
                .height(48).borderRadius(12).backgroundColor(this.nativeDark ? '#2C2C2E' : '#F5F6F7')
                .fontColor(this.nativeDark ? '#F9FAFB' : '#0F1115').onChange((value: string) => { this.accessKey = value; })
            }
            Button((this.mode === 'passkey' ? '✓  ' : '') + 'Pocket ID · Passkey', { type: ButtonType.Normal })
              .height(48).borderRadius(12).fontSize(14)
              .backgroundColor(this.nativeDark ? '#2C2C2E' : '#F5F6F7')
              .fontColor(this.nativeDark ? '#F9FAFB' : '#0F1115')
              .border({ width: 1, color: this.mode === 'passkey' ? '#ADB2B8' : Color.Transparent })
              .width('100%').onClick(() => { this.mode = 'passkey'; this.accessKey = ''; })
            Button(this.busy ? '正在连接…' : '连接工作空间', { type: ButtonType.Normal })
              .height(48).borderRadius(12).fontSize(14).width('100%').enabled(!this.busy)
              .backgroundColor(this.nativeDark ? '#F9FAFB' : '#0F1115')
              .fontColor(this.nativeDark ? '#151517' : '#FFFFFF')
              .onClick(() => { this.connect().catch((error: Error) => { this.error = error.message || '连接失败'; }); })
          }.padding(28).width('100%').constraintSize({ maxWidth: 600 })
        }.layoutWeight(1).width('100%')
      }
      if (this.error) { Text(this.error).fontColor('#b91c1c').fontSize(13).padding(10) }
    }.width('100%').height('100%').backgroundColor(this.nativeDark ? '#151517' : '#FFFFFF')
      .bindSheet(this.compatibilitySurface, this.compatibilitySheet, { height: SheetSize.LARGE, showClose: true,
        onDisappear: (): void => { this.closeCompatibility(); } })
      .visibility(this.nativeSettings ? Visibility.Hidden : Visibility.Visible)
      if (this.nativeSettings) { this.settingsSheet() }
    }.width('100%').height('100%').backgroundColor(this.nativeDark ? '#151517' : '#FFFFFF')
  }

  build() {
    WithTheme({ colorMode: this.nativeDark ? ThemeColorMode.DARK : ThemeColorMode.LIGHT }) {
    Navigation() {
      this.pageContent()
    }
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .hideBackButton(true)
    .hideToolBar(true)
    .width('100%').height('100%')
    .backgroundColor(this.nativeDark ? '#151517' : '#FFFFFF')
    .bindSheet(this.modePicker, this.modeSheet, { height: SheetSize.FIT_CONTENT, showClose: true })
    }
  }

}
