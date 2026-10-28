import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { webview } from '@kit.ArkWeb';
import { picker } from '@kit.CoreFileKit';
import { PocketBridge } from '../services/PocketBridge';

@Entry
@Component
struct Index {
  private controller: webview.WebviewController = new webview.WebviewController();
  private context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
  private store: preferences.Preferences | null = null;
  private bridge: PocketBridge | null = null;
  @State private origin: string = '';
  @State private address: string = '';
  @State private mode: string = 'passkey';
  @State private ready: boolean = false;
  @State private busy: boolean = false;
  @State private error: string = '';
  @State private progress: number = 0;
  @StorageLink('requestedSession') @Watch('openNotification') private requestedSession: string = '';

  aboutToAppear(): void {
    this.initialize().catch(() => { this.error = '无法读取连接配置'; });
  }

  private async initialize(): Promise<void> {
    this.store = await preferences.getPreferences(this.context, { name: 'dsh-pocket' });
    this.address = this.store.getSync('origin', '') as string;
    this.mode = this.store.getSync('mode', 'passkey') as string;
    if (this.normalize(this.address)) await this.connect();
  }

  private normalize(input: string): string {
    const value = input.trim().replace(/\/+$/, '').toLowerCase();
    if (!/^https:\/\/[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?(?::[0-9]{1,5})?$/.test(value)) return '';
    const port = value.match(/:([0-9]+)$/);
    if (port && (Number(port[1]) < 1 || Number(port[1]) > 65535)) return '';
    return value;
  }

  private async connect(): Promise<void> {
    const next = this.normalize(this.address);
    if (!next) { this.error = '请输入 HTTPS 源地址，不包含路径或账号'; return; }
    this.busy = true;
    try {
      if (this.origin && this.origin !== next) throw new Error('请先退出当前连接');
      this.origin = next;
      this.bridge = new PocketBridge(this.context, this.controller, next);
      this.store?.putSync('origin', next);
      this.store?.putSync('mode', this.mode);
      await this.store?.flush();
      this.error = '';
      this.ready = true;
    } finally { this.busy = false; }
  }

  private allowed(url: string): boolean {
    return url === this.origin || url.startsWith(this.origin + '/');
  }

  private openNotification(): void {
    if (!this.ready || !this.requestedSession || !this.allowed(this.controller.getUrl())) return;
    // Gateway persists the session hint; it does not invent a Harness SPA route.
    this.controller.loadUrl(this.origin + '/pocket/?session=' + encodeURIComponent(this.requestedSession));
    this.requestedSession = '';
  }

  private async disconnect(): Promise<void> {
    // Do not silently strand a push endpoint: revoke authenticated device registrations first.
    this.controller.runJavaScript("fetch('/pocket/api/logout',{method:'POST'}).then(r=>{if(!r.ok)throw Error();return true})")
      .then(async () => {
        await webview.WebCookieManager.clearAllCookies();
        webview.WebStorage.deleteAllData();
        this.ready = false;
        this.origin = '';
        this.controller = new webview.WebviewController();
        this.store?.putSync('origin', '');
        await this.store?.flush();
      }).catch(() => { this.error = '退出失败，请在网页通知设置中重试'; });
  }

  onBackPress(): boolean {
    if (this.ready && this.controller.accessBackward()) { this.controller.backward(); return true; }
    return false;
  }

  build() {
    Column() {
      if (this.ready) {
        Row({ space: 12 }) {
          Text('DSH Pocket').fontWeight(FontWeight.Bold).layoutWeight(1)
          Button('通知').onClick(() => this.controller.loadUrl(this.origin + '/pocket/'))
          Button('刷新').onClick(() => { this.error = ''; this.controller.refresh(); })
          Button('退出').onClick(() => { this.disconnect(); })
        }.padding(8).width('100%')
        if (this.progress < 100) { Progress({ value: this.progress, total: 100 }).width('100%') }
        Web({ src: this.origin + '/pocket/?mode=' + this.mode, controller: this.controller })
          .width('100%').layoutWeight(1)
          .javaScriptAccess(true).domStorageAccess(true).databaseAccess(true)
          .fileAccess(false).mixedMode(MixedMode.None)
          .darkMode(WebDarkMode.Auto).forceDarkAccess(false)
          .onControllerAttached(() => {
            if (this.bridge !== null) this.controller.registerJavaScriptProxy(this.bridge, 'dshPocket', ['request']);
          })
          .onLoadIntercept((event) => {
            const blocked = !this.allowed(event.data.getRequestUrl());
            if (blocked) this.error = '已阻止站外跳转；请在系统浏览器打开外部链接';
            return blocked;
          })
          .onWindowNew((event) => {
            if (this.allowed(event.targetUrl)) this.controller.loadUrl(event.targetUrl);
          })
          .onProgressChange((event) => { this.progress = event.newProgress; })
          .onPageEnd(() => this.openNotification())
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
      } else {
        Scroll() {
          Column({ space: 20 }) {
            Text('DSH Pocket').fontSize(32).fontWeight(FontWeight.Bold)
            Text('连接你的 DeepSeek Harness 工作空间').fontSize(16)
            TextInput({ text: this.address, placeholder: 'https://dsh.example.com' })
              .type(InputType.URL).onChange((value: string) => { this.address = value; })
            Button((this.mode === 'passkey' ? '✓ ' : '') + 'Passkey 登录')
              .width('100%').onClick(() => { this.mode = 'passkey'; })
            Button((this.mode === 'none' ? '✓ ' : '') + '无验证登录（受信任网络）')
              .width('100%').onClick(() => { this.mode = 'none'; })
            Text('登录策略由网关控制。选择无验证不会绕过服务端认证。Passkey 需要有效 HTTPS 证书及系统 FIDO2 支持。')
              .fontSize(13).fontColor('#64748b')
            Button(this.busy ? '正在连接…' : '连接工作空间').width('100%').enabled(!this.busy)
              .onClick(() => { this.connect().catch(() => { this.error = '连接失败'; }); })
          }.padding(28).width('100%').constraintSize({ maxWidth: 600 })
        }.layoutWeight(1).width('100%')
      }
      if (this.error) { Text(this.error).fontColor('#b91c1c').fontSize(13).padding(10) }
    }.width('100%').height('100%')
  }
}
