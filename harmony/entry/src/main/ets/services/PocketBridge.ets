import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { WindowAppearance } from './WindowAppearance';
import { NativeExperience } from './NativeExperience';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { OverviewSnapshot, WidgetStore, WidgetTask } from './WidgetStore';
import { PushKitAdapter } from 'entry/PushKitAdapter';
import { BackgroundMonitor } from './BackgroundMonitor';
import { notificationManager } from '@kit.NotificationKit';

class LocalNotificationMessage {
  sessionId: string = '';
  state: string = '';
  title: string = '';
}

class NotificationLevels {
  version: number = 1;
  completed: string = 'quiet';
  failed: string = 'standard';
  approval: string = 'standard';
  connection: string = 'off';
}

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

  private async persist(name: string, key: string, value: string | boolean): Promise<void> {
    const store = preferences.getPreferencesSync(this.context, { name });
    const existed = store.hasSync(key);
    const previous = store.getSync(key, typeof value === 'string' ? '' : false);
    store.putSync(key, value);
    try { await store.flush(); }
    catch (error) {
      if (existed) store.putSync(key, previous); else store.deleteSync(key);
      throw error as Error;
    }
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
      await this.persist('dsh-pocket', 'uiMode', value);
      AppStorage.setOrCreate<string>('uiMode', value);
      return '';
    }
    if (command === 'openSettings') {
      AppStorage.setOrCreate<string>('requestedPocketRoute', 'settings');
      return '';
    }
    if (command === 'themeMode') {
      if (!['system', 'light', 'dark'].includes(value)) throw new Error('Invalid theme');
      await this.persist('pocket-native-experience', 'themeMode', value);
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
      const notices = preferences.getPreferencesSync(this.context, { name: 'dsh-notifications' });
      const levels = PocketBridge.levels(notices.getSync('levels', '') as string);
      state['uiMode'] = AppStorage.get<string>('uiMode') || 'compatibility';
      state['widgetDetails'] = WidgetStore.detailsEnabled(this.context);
      state['supportsPush'] = PushKitAdapter.supported;
      state['pushEnabled'] = notices.getSync('pushEnabled', false) === true;
      state['notificationsEnabled'] = false;
      state['notificationPermissionKnown'] = false;
      try {
        state['notificationsEnabled'] = await notificationManager.isNotificationEnabled();
        state['notificationPermissionKnown'] = true;
      } catch (_) {}
      state['backgroundMonitor'] = notices.getSync('backgroundMonitor', false) === true;
      AppStorage.setOrCreate<boolean>('nativeBackgroundMonitor', state['backgroundMonitor'] as boolean);
      state['notifyCompleted'] = levels.completed;
      state['notifyFailed'] = levels.failed;
      state['notifyApproval'] = levels.approval;
      state['notifyConnection'] = levels.connection;
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
    if (command === 'notificationLevels') {
      const levels = JSON.parse(value) as Record<string, Object>;
      if (!PocketBridge.validLevels(levels)) {
        throw new Error('Invalid notification levels');
      }
      const normalized = PocketBridge.levels(JSON.stringify(levels));
      await this.persist('dsh-notifications', 'levels', JSON.stringify(normalized));
      return '';
    }
    if (command === 'pushEnabled' || command === 'backgroundMonitor') {
      if (value !== 'true' && value !== 'false') throw new Error('Invalid notification preference');
      const enabled = value === 'true';
      const store = preferences.getPreferencesSync(this.context, { name: 'dsh-notifications' });
      if (command === 'backgroundMonitor' && enabled && !PushKitAdapter.supported) {
        await notificationManager.requestEnableNotification(this.context);
        if (!await notificationManager.isNotificationEnabled()) {
          throw new Error('Notification permission was not granted');
        }
      }
      await this.persist('dsh-notifications', command, enabled);
      if (command === 'backgroundMonitor') AppStorage.setOrCreate<boolean>('nativeBackgroundMonitor', enabled);
      return '';
    }
    if (command === 'publishLocalNotification') {
      const message = JSON.parse(value) as LocalNotificationMessage;
      const sessionId = message.sessionId;
      const state = message.state;
      const title = message.title;
      if (typeof sessionId !== 'string' || !/^[A-Za-z0-9_-]{1,160}$/.test(sessionId) ||
        !['completed', 'failed', 'waiting', 'connection'].includes(state) || typeof title !== 'string') throw new Error('Invalid notification');
      // Task lifecycle notifications use the local background bridge only in
      // the no-Push build. A real live-socket failure can notify locally in
      // either build while this process is running.
      if (state !== 'connection' &&
        (PushKitAdapter.supported || AppStorage.get<boolean>('nativeBackgroundMonitor') !== true)) return '';
      const category = state === 'completed' ? 'completed' : state === 'failed' ? 'failed' :
        state === 'connection' ? 'connection' : 'approval';
      const notices = preferences.getPreferencesSync(this.context, { name: 'dsh-notifications' });
      const levels = PocketBridge.levels(notices.getSync('levels', '') as string);
      const level = category === 'completed' ? levels.completed : category === 'failed' ? levels.failed :
        category === 'connection' ? levels.connection : levels.approval;
      if (level === 'off') return '';
      const body = state === 'completed' ? '任务已完成' : state === 'failed' ? '任务执行失败' :
        state === 'connection' ? '服务连接中断' : '有任务需要确认';
      await BackgroundMonitor.notify(sessionId, title.slice(0, 80), body,
        BackgroundMonitor.notificationId(sessionId, state), level);
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
      if (Array.isArray(snapshot.tasks)) {
        safe.tasks = snapshot.tasks.filter((item: WidgetTask) => item && /^[A-Za-z0-9_-]{1,160}$/.test(item.sessionId) &&
          typeof item.title === 'string' && item.title.length > 0 && item.title.length <= 160 &&
          ['running', 'waiting', 'completed', 'failed', 'unknown'].includes(item.state))
          .slice(0, 6).map((item: WidgetTask) => {
            const task = new WidgetTask();
            task.sessionId = item.sessionId; task.title = item.title.slice(0, 120);
            task.state = item.state; task.updatedAt = Number.isFinite(item.updatedAt) ? item.updatedAt : 0;
            return task;
          });
      }
      await WidgetStore.update(this.context, safe);
      return '';
    }
    if (command === 'widgetDisconnected') { await WidgetStore.clear(this.context); return ''; }
    if (command === 'appearanceDark' || command === 'appearanceLight') {
      AppStorage.setOrCreate<boolean>('nativeWebThemeKnown', true);
      AppStorage.setOrCreate<boolean>('nativeWebDark', command === 'appearanceDark');
      if (AppStorage.get<boolean>('nativeShellForeground') === false) WindowAppearance.applyBars(command === 'appearanceDark');
      return '';
    }
    if (command === 'enablePush') {
      return await PushKitAdapter.getToken(this.context);
    }
    if (command === 'disablePush') { await PushKitAdapter.deleteToken(); return ''; }
    if (command === 'testNotification') {
      await notificationManager.requestEnableNotification(this.context);
      if (!await notificationManager.isNotificationEnabled()) {
        throw new Error('Notification permission was not granted');
      }
      await BackgroundMonitor.notify('test-notification', 'DSH Harmony 测试通知', '通知已连接',
        BackgroundMonitor.notificationId('test', 'notification'), 'prominent');
      return '';
    }
    if (command === 'openNotificationSettings') {
      await notificationManager.openNotificationSettings(this.context);
      return '';
    }
    if (command === 'clearSession') {
      this.closed = true;
      // The web side revokes its endpoint and authenticated cookie first.
      await BackgroundMonitor.stop(this.context);
      await WidgetStore.clear(this.context);
      try { await PushKitAdapter.deleteToken(); } catch (_) {}
      try {
        const notices = preferences.getPreferencesSync(this.context, { name: 'dsh-notifications' });
        notices.clearSync();
        await notices.flush();
      } catch (_) {}
      AppStorage.setOrCreate<boolean>('nativeBackgroundMonitor', false);
      await webview.WebCookieManager.clearAllCookies();
      webview.WebStorage.deleteAllData();
      AppStorage.setOrCreate<boolean>('pocketPageThemeKnown', false);
      await this.onLogout();
      return '';
    }
    throw new Error('Unknown command');
  }

  private static validLevel(value: Object | undefined): boolean {
    return typeof value === 'string' && ['off', 'quiet', 'standard', 'prominent'].includes(value);
  }

  private static validLevels(value: Record<string, Object>): boolean {
    return (value.version === undefined || value.version === 1) &&
      ['completed', 'failed', 'approval', 'connection'].every((key: string): boolean =>
        value[key] === undefined || typeof value[key] === 'boolean' || PocketBridge.validLevel(value[key]));
  }

  private static levels(raw: string): NotificationLevels {
    const value = new NotificationLevels();
    try {
      const saved = JSON.parse(raw) as Record<string, Object>;
      const normalize = (level: Object | undefined, fallback: string): string => {
        if (typeof level === 'boolean') return level ? 'standard' : 'off';
        return typeof level === 'string' && ['off', 'quiet', 'standard', 'prominent'].includes(level) ? level : fallback;
      };
      value.completed = normalize(saved.completed, 'quiet');
      value.failed = normalize(saved.failed, 'standard');
      value.approval = normalize(saved.approval, 'standard');
      value.connection = normalize(saved.connection, 'off');
    } catch (_) {}
    return value;
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
