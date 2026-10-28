import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { notificationManager } from '@kit.NotificationKit';
import { pushService } from '@kit.PushKit';
import { WindowAppearance } from './WindowAppearance';
import { NativeExperience } from './NativeExperience';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { OverviewSnapshot, WidgetStore } from './WidgetStore';

export class PocketBridge {
  private context: common.UIAbilityContext;
  private controller: webview.WebviewController;
  private origin: string;
  private closed: boolean = false;
  private onLogout: () => Promise<void>;

  constructor(context: common.UIAbilityContext, controller: webview.WebviewController,
    origin: string, onLogout: () => Promise<void>) {
    this.context = context;
    this.controller = controller;
    this.origin = origin;
    this.onLogout = onLogout;
  }

  request(id: string, command: string, value: string): void {
    const caller = this.controller.getLastJavascriptProxyCallingFrameUrl();
    const top = this.controller.getUrl();
    if (!this.trusted(caller) || !this.trusted(top) || !/^[a-zA-Z0-9_-]{1,80}$/.test(id) || typeof value !== 'string' || value.length > 2048) return;
    this.performNative(command, value).then((value: string) => this.reply(id, true, value))
      .catch(() => this.reply(id, false, '操作失败，请检查应用权限、连接和本机设置'));
  }

  private trusted(url: string): boolean {
    return url === this.origin || url.startsWith(this.origin + '/');
  }

  // Called directly only by trusted ArkTS UI. The JavaScript proxy exposes request alone.
  async performNative(command: string, value: string): Promise<string> {
    if (command === 'nativeAuthenticated') {
      await webview.WebCookieManager.saveCookieAsync();
      AppStorage.setOrCreate<number>('nativeAuthRevision', (AppStorage.get<number>('nativeAuthRevision') || 0) + 1);
      return '';
    }
    if (command === 'uiMode') {
      if (value !== 'compatibility' && value !== 'native') throw new Error('Invalid mode');
      const store = preferences.getPreferencesSync(this.context, { name: 'dsh-pocket' });
      store.putSync('uiMode', value); await store.flush();
      AppStorage.setOrCreate<string>('uiMode', value);
      return '';
    }
    if (command === 'themeMode') {
      if (!['system', 'light', 'dark'].includes(value)) throw new Error('Invalid theme');
      const store = preferences.getPreferencesSync(this.context, { name: 'pocket-native-experience' });
      store.putSync('themeMode', value); await store.flush();
      AppStorage.setOrCreate<string>('nativeThemeMode', value);
      return '';
    }
    if (command === 'deviceId') {
      const store = preferences.getPreferencesSync(this.context, { name: 'pocket-native-device' });
      let id = store.getSync('id', '') as string;
      if (!id) { id = util.generateRandomUUID(); store.putSync('id', id); await store.flush(); }
      return id;
    }
    if (command === 'nativeState') {
      const state = JSON.parse(NativeExperience.state(this.context)) as Record<string, Object>;
      state['uiMode'] = AppStorage.get<string>('uiMode') || 'compatibility';
      state['widgetDetails'] = WidgetStore.detailsEnabled(this.context);
      return JSON.stringify(state);
    }
    if (command === 'reduceTransparency' || command === 'reduceMotion') {
      if (value !== 'true' && value !== 'false') throw new Error('Invalid preference');
      NativeExperience.setPreference(this.context, command, value === 'true');
      return NativeExperience.state(this.context);
    }
    if (command === 'widgetDetails') {
      if (value !== 'true' && value !== 'false') throw new Error('Invalid preference');
      await WidgetStore.setDetails(this.context, value === 'true');
      return '';
    }
    if (command === 'widgetSnapshot') {
      if (this.closed) throw new Error('Session closed');
      const snapshot = JSON.parse(value) as OverviewSnapshot;
      const numbers: number[] = [snapshot.running, snapshot.waiting, snapshot.completed, snapshot.failed, snapshot.unknown];
      if (numbers.some((item: number) => !Number.isInteger(item) || item < 0 || item > 1000000) ||
        !Number.isFinite(snapshot.observedAt) || snapshot.observedAt < 0 ||
        !Number.isFinite(snapshot.generatedAt) || snapshot.generatedAt < 0) throw new Error('Invalid snapshot');
      // Reconstruct the allowlisted fields instead of persisting arbitrary JSON.
      const safe = new OverviewSnapshot();
      safe.running = snapshot.running; safe.waiting = snapshot.waiting;
      safe.completed = snapshot.completed; safe.failed = snapshot.failed;
      safe.unknown = snapshot.unknown; safe.observedAt = snapshot.observedAt; safe.generatedAt = snapshot.generatedAt;
      await WidgetStore.update(this.context, safe);
      return '';
    }
    if (command === 'widgetDisconnected') { await WidgetStore.clear(this.context); return ''; }
    if (command === 'appearanceDark' || command === 'appearanceLight') {
      if (AppStorage.get<string>('uiMode') === 'native' && AppStorage.get<boolean>('nativeAuthSurface') !== true) return '';
      AppStorage.setOrCreate<boolean>('pocketPageThemeKnown', true);
      WindowAppearance.apply(command === 'appearanceDark');
      return '';
    }
    if (command === 'enablePush') {
      await notificationManager.requestEnableNotification(this.context);
      return await pushService.getToken();
    }
    if (command === 'disablePush') { await pushService.deleteToken(); return ''; }
    if (command === 'clearSession') {
      this.closed = true;
      // The web side revokes its endpoint and authenticated cookie first.
      await WidgetStore.clear(this.context);
      try { await pushService.deleteToken(); } catch (_) {}
      await webview.WebCookieManager.clearAllCookies();
      webview.WebStorage.deleteAllData();
      AppStorage.setOrCreate<boolean>('pocketPageThemeKnown', false);
      await this.onLogout();
      return '';
    }
    throw new Error('Unknown command');
  }

  private reply(id: string, ok: boolean, value: string): void {
    try {
      if (!this.trusted(this.controller.getUrl())) return;
    } catch (_) { return; }
    this.controller.runJavaScript('if(location.origin===' + JSON.stringify(this.origin) +
      ')window.__pocketReply?.(' + JSON.stringify(id) + ',' + (ok ? 'true' : 'false') + ',' +
      JSON.stringify(value) + ')').catch(() => {});
  }
}
