import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { notificationManager } from '@kit.NotificationKit';
import { pushService } from '@kit.PushKit';
import { WindowAppearance } from './WindowAppearance';

export class PocketBridge {
  private context: common.UIAbilityContext;
  private controller: webview.WebviewController;
  private origin: string;
  private onLogout: () => Promise<void>;

  constructor(context: common.UIAbilityContext, controller: webview.WebviewController,
    origin: string, onLogout: () => Promise<void>) {
    this.context = context;
    this.controller = controller;
    this.origin = origin;
    this.onLogout = onLogout;
  }

  request(id: string, command: string): void {
    const caller = this.controller.getLastJavascriptProxyCallingFrameUrl();
    const top = this.controller.getUrl();
    if (!this.trusted(caller) || !this.trusted(top) || !/^[a-zA-Z0-9_-]{1,80}$/.test(id)) return;
    this.dispatch(command).then((value: string) => this.reply(id, true, value))
      .catch(() => this.reply(id, false, '操作失败，请检查通知权限和 Push Kit 项目配置'));
  }

  private trusted(url: string): boolean {
    return url === this.origin || url.startsWith(this.origin + '/');
  }

  private async dispatch(command: string): Promise<string> {
    if (command === 'appearanceDark' || command === 'appearanceLight') {
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
      // The web side revokes its endpoint and authenticated cookie first.
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
