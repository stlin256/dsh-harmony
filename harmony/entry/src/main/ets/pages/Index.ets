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
import { NativeMetadataCache } from '../services/NativeMetadataCache';
import { NativeTranscriptCache } from '../services/NativeTranscriptCache';
import { NativeAttachmentCache } from '../services/NativeAttachmentCache';
import { NativeMotion } from '../services/NativeMotion';
import { StoreShowcaseClient } from '../services/StoreShowcaseClient';
import { ProductCapabilities } from 'entry/ProductCapabilities';
import { NativeLaunchFlow, NativeLaunchPhase } from '../services/NativeLaunchFlow';
import { NativeLaunchSurface } from '../components/NativeLaunchSurface';

@Entry
@Component
struct Index {
  private controller: webview.WebviewController = new webview.WebviewController();
  private context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
  private store: preferences.Preferences | null = null;
  private bridge: PocketBridge | null = null;
  private presentation: string = '';
  private nativeClient: NativeHarnessClient = new NativeHarnessClient('');
  private showcase: boolean = false;
  @StorageLink('systemDark') @Watch('applyNativeTheme') private systemDark: boolean = false;
  @StorageLink('nativeThemeMode') @Watch('applyNativeTheme') private nativeThemeMode: string = 'system';
  @StorageLink('uiMode') @Watch('modeChanged') private uiMode: string = 'compatibility';
  @StorageLink('nativeAuthRevision') @Watch('authenticated') private authRevision: number = 0;
  @State private authSurface: boolean = false;
  @State private compatibilitySurface: boolean = false;
  @State private compatibilityDestination: string = '';
  @State @Watch('settingsChanged') private nativeSettings: boolean = false;
  @State private settingsCached: boolean = false;
  @State private settingsLayer: boolean = false;
  @State private settingsOpacity: number = 0;
  @State private settingsShift: number = 16;
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
  @State private launchPhase: string = NativeLaunchPhase.booting;
  @State private launchOpacity: number = 1;
  @State private launchError: string = '';
  @State private onboardingSeen: boolean = false;
  private launchStartedAt: number = 0;
  private settingsExitTimer: number = -1;
  private launchFinishTimer: number = -1;
  private exitGestureArmedAt: number = 0;
  @StorageLink('requestedSession') @Watch('openNotification') private requestedSession: string = '';

  aboutToAppear(): void {
    this.launchStartedAt = Date.now();
    this.launchPhase = NativeLaunchPhase.booting;
    this.initialize().catch((error: Error) => {
      this.failLaunch(error.message || '启动失败');
    });
  }

  aboutToDisappear(): void {
    clearTimeout(this.settingsExitTimer);
    clearTimeout(this.launchFinishTimer);
  }

  private async initialize(): Promise<void> {
    this.presentation = util.TextDecoder.create('utf-8').decodeToString(
      await this.context.resourceManager.getRawFileContent('presentation.js'));
    this.store = await preferences.getPreferences(this.context, { name: 'dsh-pocket' });
    if (AppStorage.get<boolean>('storeShowcase') === true) {
      this.showcase = true;
      this.uiMode = 'native';
      const showcaseTheme = AppStorage.get<string>('storeShowcaseTheme');
      this.nativeThemeMode = showcaseTheme === 'dark' || showcaseTheme === 'light' ? showcaseTheme : 'system';
      this.nativeClient = new StoreShowcaseClient();
      this.address = '';
      this.origin = '';
      this.error = '';
      this.ready = true;
      this.settingsCached = true;
      this.launchOpacity = 0;
      this.launchPhase = NativeLaunchPhase.hidden;
      this.applyNativeTheme();
      if (AppStorage.get<string>('storeShowcaseScreen') === 'settings') this.openSettings();
      return;
    }
    const savedMode = this.store.getSync('uiMode', 'compatibility') as string;
    this.uiMode = savedMode === 'native' ? 'native' : 'compatibility';
    this.address = this.store.getSync('origin', '') as string;
    this.onboardingSeen = this.store.getSync('onboardingSeen', false) === true;
    const savedLoginMode = this.store.getSync('mode', 'native') as string;
    this.mode = ProductCapabilities.supportsPasskey && savedLoginMode === 'passkey' ? 'passkey' : 'native';
    if (!ProductCapabilities.supportsPasskey && savedLoginMode === 'passkey') {
      this.store.putSync('mode', 'native');
      await this.store.flush();
    }
    const next = this.normalize(this.address);
    const phase = NativeLaunchFlow.afterPreferences(next.length > 0, this.onboardingSeen);
    if (phase === NativeLaunchPhase.intro) {
      await this.revealLaunch();
      this.launchPhase = NativeLaunchPhase.intro;
      return;
    }
    this.launchPhase = NativeLaunchPhase.restoring;
    try {
      await this.connect(true);
      await this.revealLaunch();
      this.finishLaunch();
    } catch (error) {
      await this.revealLaunch();
      this.failLaunch(NativeLaunchFlow.safeMessage(
        error instanceof Error ? error : null, '无法恢复上次连接'));
    }
  }

  private async revealLaunch(): Promise<void> {
    const minimum = NativeExperience.reducedMotion() ? 80 : 520;
    const remaining = minimum - (Date.now() - this.launchStartedAt);
    if (remaining > 0) {
      await new Promise<void>((resolve: () => void): void => {
        setTimeout(resolve, remaining);
      });
    }
  }

  private failLaunch(message: string): void {
    this.ready = false;
    this.busy = false;
    this.error = '';
    this.launchError = NativeLaunchFlow.safeMessage(null, message);
    this.launchPhase = NativeLaunchFlow.needsLogin(this.launchError)
      ? NativeLaunchPhase.login : NativeLaunchPhase.error;
    this.applyNativeTheme();
  }

  private attemptConnect(): void {
    if (this.busy) return;
    const failurePhase = this.launchPhase === NativeLaunchPhase.error
      ? NativeLaunchPhase.error : NativeLaunchPhase.login;
    this.launchError = '';
    this.connect(false).then((): void => {
      this.finishLaunch();
    }).catch((error: Error): void => {
      this.launchError = NativeLaunchFlow.safeMessage(error, '连接失败');
      this.launchPhase = NativeLaunchFlow.needsLogin(this.launchError)
        ? NativeLaunchPhase.login : failurePhase;
    });
  }

  private async setOnboardingSeen(value: boolean): Promise<void> {
    this.onboardingSeen = value;
    this.store?.putSync('onboardingSeen', value);
    try { await this.store?.flush(); } catch (_) {}
  }

  private skipOnboarding(): void {
    this.setOnboardingSeen(true).catch((): void => {});
    NativeMotion.animate(this.getUIContext(), 'brand', (): void => {
      this.launchError = '';
      this.launchPhase = NativeLaunchPhase.login;
    });
  }

  private openGuide(): void {
    NativeMotion.animate(this.getUIContext(), 'brand', (): void => {
      this.launchPhase = NativeLaunchPhase.guide;
    });
  }

  private backGuide(): void {
    NativeMotion.animate(this.getUIContext(), 'brand', (): void => {
      this.launchPhase = NativeLaunchPhase.intro;
    });
  }

  private openInstallDetails(): void {
    NativeMotion.animate(this.getUIContext(), 'navigation', (): void => {
      this.launchPhase = NativeLaunchPhase.install;
    });
  }

  private closeInstallDetails(): void {
    NativeMotion.animate(this.getUIContext(), 'navigation', (): void => {
      this.launchPhase = NativeLaunchPhase.guide;
    });
  }

  private finishGuide(): void {
    this.skipOnboarding();
  }

  private finishLaunch(): void {
    clearTimeout(this.launchFinishTimer);
    this.launchError = '';
    this.setOnboardingSeen(true).catch((): void => {});
    this.launchPhase = NativeLaunchPhase.entering;
    this.launchOpacity = 1;
    NativeMotion.animate(this.getUIContext(), 'surface', (): void => {
      this.launchOpacity = 0;
    });
    this.launchFinishTimer = setTimeout((): void => {
      this.launchPhase = NativeLaunchPhase.hidden;
      this.launchOpacity = 0;
      this.applyNativeTheme();
    }, NativeMotion.enabled() ? NativeMotion.duration('surface') + 20 : 0);
    this.applyNativeTheme();
  }

  private normalize(input: string): string {
    const value = input.trim().replace(/\/+$/, '').toLowerCase();
    if (!/^https?:\/\/(?:[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?|\[[0-9a-f:]+\])(?::[0-9]{1,5})?$/.test(value)) return '';
    const port = value.match(/:([0-9]+)$/);
    if (port && (Number(port[1]) < 1 || Number(port[1]) > 65535)) return '';
    return value;
  }

  private async connect(restoring: boolean = false): Promise<void> {
    const next = this.normalize(this.address);
    if (!next) throw new Error('请输入有效的服务地址');
    if (!ProductCapabilities.supportsPasskey && this.mode === 'passkey') this.mode = 'native';
    if (this.mode === 'passkey' && !next.startsWith('https://')) throw new Error('Passkey 登录需要 HTTPS');
    this.busy = true;
    try {
      if (this.origin && this.origin !== next) throw new Error('请先退出当前连接');
      this.origin = next;
      this.nativeClient = new NativeHarnessClient(next);
      let state = await this.nativeClient.state();
      if (this.mode === 'native') {
        if (state.mode !== 'host') throw new Error('此服务需要 Passkey 登录');
        if (!state.authenticated) {
          if (!this.accessKey.trim()) throw new Error(restoring ? '上次登录已失效，请重新连接' : '请输入访问密钥');
          await this.nativeClient.loginNative(this.accessKey.trim());
          state = await this.nativeClient.state();
          if (!state.authenticated) throw new Error('登录失败，请检查访问密钥');
        }
      } else if (state.mode !== 'proxy' && state.mode !== 'passkey') throw new Error('此服务未启用 Passkey 登录');
      this.proxyAuth = state.mode === 'proxy';
      this.authOrigin = this.proxyAuth ? this.normalize(state.authOrigin) : '';
      if (this.authOrigin && !this.authOrigin.startsWith('https://')) throw new Error('认证服务需要 HTTPS');
      if (this.proxyAuth && !this.authOrigin) throw new Error('网关未提供有效的认证服务地址');
      if (this.mode === 'passkey') {
        this.authSurface = true;
        AppStorage.setOrCreate<boolean>('nativeAuthSurface', true);
      }
      this.bridge = new PocketBridge(this.context, this.controller, next, async (): Promise<void> => {
        await this.resetConnectionState();
      });
      this.store?.putSync('origin', next);
      this.store?.putSync('mode', this.mode);
      await this.store?.flush();
      this.error = '';
      this.accessKey = '';
      this.ready = true;
      // Mount the settings tree while hidden so the first open paints from cache.
      this.settingsCached = true;
      if (this.uiMode === 'native') this.openPocketRoute();
      this.applyNativeTheme();
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
      this.openSettings(); this.requestedPocketRoute = ''; return;
    }
    if (this.uiMode === 'native' && !this.authSurface) {
      if (this.requestedPocketRoute !== 'workspace') this.openSettings();
      else this.closeSettings();
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
    this.authSurface = false; AppStorage.setOrCreate<boolean>('nativeAuthSurface', false); this.hideSettingsImmediately();
    this.error = '';
    if (this.uiMode === 'native') {
      this.applyNativeTheme();
      try { this.controller.runJavaScript('window.__pocketSuspendOverview?.()').catch(() => {}); } catch (_) {}
      this.openPocketRoute();
    }
  }
  private applyNativeTheme(): void {
    const shell = !this.ready || this.launchPhase !== NativeLaunchPhase.hidden ||
      this.nativeSettings || this.connectionManager ||
      (this.uiMode === 'native' && !this.authSurface && !this.compatibilitySurface);
    AppStorage.setOrCreate<boolean>('nativeShellForeground', shell);
    AppStorage.setOrCreate<boolean>('pocketPageThemeKnown', true);
    WindowAppearance.apply(this.nativeThemeMode === 'dark' || (this.nativeThemeMode === 'system' && this.systemDark));
    if (!shell && AppStorage.get<boolean>('nativeWebThemeKnown') === true) WindowAppearance.applyBars(AppStorage.get<boolean>('nativeWebDark') === true);
  }
  private loginSurface(): void {
    this.invokeNative('widgetDisconnected', '').catch(() => {});
    AppStorage.setOrCreate<boolean>('nativeAuthSurface', false);
    this.authSurface = false;
    this.launchError = '';
    this.launchOpacity = 1;
    this.launchPhase = NativeLaunchPhase.login;
    this.applyNativeTheme();
  }
  private authenticated(): void {
    if (this.uiMode === 'native') {
      this.authSurface = false;
      AppStorage.setOrCreate<boolean>('nativeAuthSurface', false);
      if (this.launchPhase !== NativeLaunchPhase.hidden) this.finishLaunch();
      else this.applyNativeTheme();
    }
  }
  private async selectMode(mode: string): Promise<void> {
    this.modePicker = false;
    if (this.bridge) await this.bridge.performNative('uiMode', mode);
    else {
      this.uiMode = mode; this.store?.putSync('uiMode', mode); await this.store?.flush();
    }
  }
  private async invokeNative(command: string, value: string): Promise<string> {
    if (this.showcase) {
      if (command === 'nativeState') return StoreShowcaseClient.initialState();
      if (command === 'themeMode') {
        this.nativeThemeMode = value;
        this.applyNativeTheme();
      }
      if (command === 'nativeCompatibilityActive') return '{}';
      return JSON.stringify({ reduceMotion: false, reduceTransparency: false, themeMode: value });
    }
    if (!this.bridge) throw new Error('Not connected');
    return await this.bridge.performNative(command, value);
  }
  private async resetConnectionState(): Promise<void> {
    const retainedAddress = this.origin || this.address;
    if (this.origin) {
      const scope = this.nativeClient.cacheKey();
      NativeMetadataCache.clear(this.context, scope);
      try { await NativeTranscriptCache.clearScope(this.context, scope); } catch (_) {}
      try { await NativeAttachmentCache.clearScope(this.context, scope); } catch (_) {}
    }
    WindowAppearance.apply(this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    this.nativeClient.pause(); this.nativeClient.drafts.clear(); this.nativeClient.images.clear(); this.nativeClient.uncertain.clear();
    AppStorage.setOrCreate<boolean>('nativeBackgroundMonitor', false);
    try {
      const notices = preferences.getPreferencesSync(this.context, { name: 'dsh-notifications' });
      notices.clearSync();
      await notices.flush();
    } catch (_) {}
    this.authSurface = false; AppStorage.setOrCreate<boolean>('nativeAuthSurface', false);
    this.hideSettingsImmediately(); this.settingsCached = false; this.connectionManager = false; this.compatibilitySurface = false;
    AppStorage.setOrCreate<boolean>('nativeCompatibilityActive', false);
    this.ready = false; this.origin = ''; this.authOrigin = ''; this.proxyAuth = false;
    this.address = retainedAddress; this.accessKey = ''; this.error = '';
    this.bridge = null; this.controller = new webview.WebviewController();
    this.nativeClient = new NativeHarnessClient('');
    this.requestedPocketRoute = ''; this.requestedSession = '';
    try { this.store?.putSync('origin', retainedAddress); await this.store?.flush(); } catch (_) {}
    this.onboardingSeen = false;
    try {
      this.store?.putSync('onboardingSeen', false);
      await this.store?.flush();
    } catch (_) {}
    this.launchError = '';
    this.launchOpacity = 1;
    this.launchPhase = NativeLaunchPhase.intro;
    this.applyNativeTheme();
  }
  private async disconnectConnection(): Promise<void> {
    this.busy = true;
    try {
      // Server logout is best effort: a failed or expired login must still be
      // escapable, so local cookies and the saved origin are always cleared.
      try { await this.nativeClient.request('/pocket/api/logout', http.RequestMethod.POST, '{}'); } catch (_) {}
      if (this.bridge) {
        try { await this.bridge.performNative('clearSession', ''); } catch (_) {}
      }
      try { await webview.WebCookieManager.clearAllCookies(); } catch (_) {}
      try { webview.WebStorage.deleteAllData(); } catch (_) {}
      await this.resetConnectionState();
    } finally { this.busy = false; }
  }
  private compatibility(destination: string = ''): void {
    this.compatibilityDestination = destination;
    AppStorage.setOrCreate<boolean>('nativeCompatibilityActive', true);
    this.compatibilitySurface = true;
  }
  private closeCompatibility(): void {
    this.compatibilitySurface = false;
    this.compatibilityDestination = '';
    AppStorage.setOrCreate<boolean>('nativeCompatibilityActive', false);
    this.applyNativeTheme();
  }
  @Builder
  private compatibilitySheet() {
    NativeCompatibilitySurface({ origin: this.origin, sessionId: this.nativeClient.selectedId,
      destination: this.compatibilityDestination, presentation: this.presentation,
      onClose: (): void => { this.closeCompatibility(); } })
  }
  @Builder
  private settingsSheet() {
    NativeSettings({ client: this.nativeClient, serverOrigin: this.origin,
      invoke: (command: string, value: string): Promise<string> => this.invokeNative(command, value),
      onReturn: (): void => { this.closeSettings(); },
      onModes: (): void => { this.modePicker = true; },
      onConnection: (): void => { this.closeSettings(); this.connectionManager = true; },
      onLogin: (): void => { this.closeSettings(); this.loginSurface(); },
      onLogout: (): Promise<void> => this.disconnectConnection() })
  }
  private settingsChanged(): void {
    this.applyNativeTheme();
  }
  private openSettings(): void {
    clearTimeout(this.settingsExitTimer);
    this.settingsCached = true;
    this.settingsLayer = true;
    if (!this.nativeSettings) AppStorage.setOrCreate<string>('nativeSettingsPage', 'root');
    NativeMotion.animate(this.getUIContext(), 'surface', (): void => {
      this.nativeSettings = true;
      this.settingsOpacity = 1;
      this.settingsShift = 0;
    });
    this.applyNativeTheme();
  }
  private closeSettings(): void {
    if (!this.nativeSettings && !this.settingsLayer) return;
    clearTimeout(this.settingsExitTimer);
    NativeMotion.animate(this.getUIContext(), 'surface', (): void => {
      this.nativeSettings = false;
      this.settingsOpacity = 0;
      this.settingsShift = -12;
    });
    this.settingsExitTimer = setTimeout((): void => {
      this.settingsLayer = false;
      this.settingsOpacity = 0;
      this.settingsShift = 16;
      AppStorage.setOrCreate<string>('nativeSettingsPage', 'root');
      this.applyNativeTheme();
    }, NativeMotion.enabled() ? NativeMotion.duration('surface') + 20 : 0);
    this.applyNativeTheme();
  }
  private hideSettingsImmediately(): void {
    clearTimeout(this.settingsExitTimer);
    this.nativeSettings = false;
    this.settingsLayer = false;
    this.settingsOpacity = 0;
    this.settingsShift = 16;
    AppStorage.setOrCreate<string>('nativeSettingsPage', 'root');
    this.applyNativeTheme();
  }
  private changeSettingsPage(page: string): void {
    const update = (): void => { AppStorage.setOrCreate<string>('nativeSettingsPage', page); };
    NativeMotion.animate(this.getUIContext(), 'navigation', update);
  }
  private refreshContent(): void {
    if (this.uiMode === 'native' && !this.authSurface) {
      this.closeSettings();
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
    }.padding(24).width('100%').alignItems(HorizontalAlign.Start)
  }

  onBackPress(): boolean {
    if (this.launchPhase === NativeLaunchPhase.booting ||
      this.launchPhase === NativeLaunchPhase.restoring ||
      this.launchPhase === NativeLaunchPhase.entering) return true;
    if (this.launchPhase === NativeLaunchPhase.install) { this.closeInstallDetails(); return true; }
    if (this.launchPhase === NativeLaunchPhase.guide) { this.backGuide(); return true; }
    if (this.launchPhase === NativeLaunchPhase.login) {
      this.launchPhase = NativeLaunchPhase.intro;
      return true;
    }
    if (this.launchPhase === NativeLaunchPhase.error) {
      this.launchPhase = NativeLaunchPhase.login;
      return true;
    }
    if (!this.ready) return false;
    if (this.modePicker) { this.modePicker = false; return true; }
    if (this.nativeSettings) {
      if ((AppStorage.get<string>('nativeSettingsPage') || 'root') !== 'root') {
        this.changeSettingsPage('root');
      } else this.closeSettings();
      return true;
    }
    if (this.connectionManager) { this.connectionManager = false; return true; }
    if (this.compatibilitySurface) { this.closeCompatibility(); return true; }
    if (this.uiMode === 'native' && !this.authSurface) {
      if (AppStorage.get<boolean>('nativeWorkspaceCanGoBack') === true) {
        AppStorage.setOrCreate<number>('nativeBackRevision', (AppStorage.get<number>('nativeBackRevision') || 0) + 1); return true;
      }
      if (AppStorage.get<boolean>('nativeWorkspaceHasSelection') === true) {
        this.confirmChatExit();
        return true;
      }
      return false;
    }
    if (this.ready && this.controller.accessBackward()) { this.controller.backward(); return true; }
    return false;
  }
  private confirmChatExit(): void {
    const now = Date.now();
    if (now - this.exitGestureArmedAt <= 2000) {
      this.exitGestureArmedAt = 0;
      this.context.terminateSelf().catch((): void => {});
      return;
    }
    this.exitGestureArmedAt = now;
    this.getUIContext().getPromptAction().showToast({
      message: '再次滑动退出',
      duration: 1500
    });
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
      } else if (this.ready &&
        (this.launchPhase === NativeLaunchPhase.entering ||
          this.launchPhase === NativeLaunchPhase.hidden)) {
        if (this.uiMode === 'native' && !this.authSurface) {
          NativeWorkspace({ client: this.nativeClient, context: this.context, supportsPush: PushKitAdapter.supported,
            onLogin: (): void => { this.loginSurface(); },
            onSettings: (): void => { this.openSettings(); },
            onSnapshot: async (value: string): Promise<void> => {
              if (!this.showcase) await this.invokeNative('widgetSnapshot', value);
            },
            onLocalNotification: async (sessionId: string, title: string, state: string): Promise<void> => {
              if (!this.showcase) {
                await this.invokeNative('publishLocalNotification', JSON.stringify({ sessionId, title, state }));
              }
            },
            onCompatibility: (): void => { this.compatibility(); },
            onDestination: (destination: string): void => { this.compatibility(destination); } })
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
      }
      if (this.error && this.launchPhase === NativeLaunchPhase.hidden) {
        Text(this.error).fontColor('#b91c1c').fontSize(13).padding(10)
      }
    }.width('100%').height('100%').backgroundColor(this.nativeDark ? '#151517' : '#FFFFFF')
      .bindSheet(this.compatibilitySurface, this.compatibilitySheet, { height: SheetSize.LARGE, showClose: false,
        onDisappear: (): void => { this.closeCompatibility(); } })
      .visibility(this.nativeSettings || this.settingsLayer ? Visibility.Hidden : Visibility.Visible)
      if (this.ready && this.settingsCached && this.settingsLayer) {
        Column() { this.settingsSheet() }.width('100%').height('100%')
          .opacity(this.settingsOpacity)
          .translate({ x: this.settingsShift })
          .hitTestBehavior(this.nativeSettings ? HitTestMode.Default : HitTestMode.None)
      }
      if (this.launchPhase !== NativeLaunchPhase.hidden) {
        Column() {
          NativeLaunchSurface({
            phase: this.launchPhase,
            address: this.address,
            accessKey: this.accessKey,
            mode: this.mode,
            showPasskey: ProductCapabilities.supportsPasskey,
            busy: this.busy,
            errorText: this.launchError,
            onAddressChange: (value: string): void => { this.address = value; },
            onAccessKeyChange: (value: string): void => { this.accessKey = value; },
            onModeChange: (value: string): void => {
              this.mode = value;
              if (value === 'passkey') this.accessKey = '';
            },
            onConnect: (): void => { this.attemptConnect(); },
            onOpenGuide: (): void => { this.openGuide(); },
            onCloseGuide: (): void => { this.backGuide(); },
            onOpenInstall: (): void => { this.openInstallDetails(); },
            onCloseInstall: (): void => { this.closeInstallDetails(); },
            onDirect: (): void => {
              if (this.launchPhase === NativeLaunchPhase.guide) this.finishGuide();
              else this.skipOnboarding();
            },
            onEditAddress: (): void => {
              this.launchError = '';
              this.launchPhase = this.launchPhase === NativeLaunchPhase.error
                ? NativeLaunchPhase.login : NativeLaunchPhase.intro;
            },
            onRetry: (): void => { this.attemptConnect(); }
          })
        }
        .width('100%').height('100%').opacity(this.launchOpacity)
        .backgroundColor(this.nativeDark ? '#151517' : '#FFFFFF')
        .hitTestBehavior(this.launchOpacity > 0 ? HitTestMode.Default : HitTestMode.None)
      }
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
    .bindSheet(this.modePicker, this.modeSheet, {
      height: SheetSize.FIT_CONTENT,
      showClose: true,
      onDisappear: (): void => { this.modePicker = false; }
    })
    }
  }

}
