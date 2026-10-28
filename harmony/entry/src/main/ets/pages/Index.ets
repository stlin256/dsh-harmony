import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import { picker } from '@kit.CoreFileKit';
import { PocketBridge } from '../services/PocketBridge';
import { WindowAppearance } from '../services/WindowAppearance';

@Entry
@Component
struct Index {
  private controller: webview.WebviewController = new webview.WebviewController();
  private context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
  private store: preferences.Preferences | null = null;
  private bridge: PocketBridge | null = null;
  private presentation: string = '';
  @StorageLink('nativeDark') private nativeDark: boolean = false;
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
    this.presentation = util.TextDecoder.create('utf-8').decodeToString(
      await this.context.resourceManager.getRawFileContent('presentation.js'));
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
      this.bridge = new PocketBridge(this.context, this.controller, next, async (): Promise<void> => {
        WindowAppearance.apply(this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
        this.ready = false;
        this.origin = '';
        this.controller = new webview.WebviewController();
        this.store?.putSync('origin', '');
        await this.store?.flush();
      });
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

  onBackPress(): boolean {
    if (this.ready && this.controller.accessBackward()) { this.controller.backward(); return true; }
    return false;
  }

  build() {
    Column() {
      if (this.ready) {
        Row({ space: 8 }) {
          Text('DSH Pocket').fontSize(14).fontWeight(FontWeight.Medium).layoutWeight(1)
            .fontColor(this.nativeDark ? '#F9FAFB' : '#0F1115')
          Button('刷新', { type: ButtonType.Normal }).height(44).padding({ left: 12, right: 12 })
            .fontSize(13).borderRadius(12).backgroundColor(Color.Transparent)
            .fontColor(this.nativeDark ? '#CFD3D6' : '#61666B')
            .onClick(() => { this.error = ''; this.controller.refresh(); })
          Button('设置', { type: ButtonType.Normal }).height(44).padding({ left: 12, right: 12 })
            .fontSize(13).borderRadius(12).backgroundColor(this.nativeDark ? '#353638' : '#F5F6F7')
            .fontColor(this.nativeDark ? '#F9FAFB' : '#0F1115')
            .onClick(() => this.controller.loadUrl(this.origin + '/pocket/'))
        }.padding({ left: 20, right: 12, top: 4, bottom: 4 }).width('100%')
        if (this.progress < 100) { Progress({ value: this.progress, total: 100 }).width('100%').color(this.nativeDark ? '#5686FE' : '#4176E6').height(2) }
        Web({ src: this.origin + '/pocket/?mode=' + this.mode, controller: this.controller })
          .width('100%').layoutWeight(1)
          .javaScriptAccess(true).domStorageAccess(true).databaseAccess(true)
          .fileAccess(false).mixedMode(MixedMode.None)
          .darkMode(WebDarkMode.Auto).forceDarkAccess(false)
          .backgroundColor(this.nativeDark ? '#151517' : '#FFFFFF')
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
          .onPageEnd(() => {
            if (this.allowed(this.controller.getUrl())) this.controller.runJavaScript(this.presentation).catch(() => {});
            this.openNotification();
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
      } else {
        Scroll() {
          Column({ space: 16 }) {
            Text('DSH Pocket').fontSize(28).fontWeight(FontWeight.Medium)
              .fontColor(this.nativeDark ? '#F9FAFB' : '#0F1115')
            Text('连接你的 DeepSeek Harness 工作空间').fontSize(14)
              .fontColor(this.nativeDark ? '#CFD3D6' : '#61666B')
            TextInput({ text: this.address, placeholder: 'https://dsh.example.com' })
              .height(48).borderRadius(12)
              .backgroundColor(this.nativeDark ? '#2C2C2E' : '#F5F6F7')
              .fontColor(this.nativeDark ? '#F9FAFB' : '#0F1115')
              .type(InputType.URL).onChange((value: string) => { this.address = value; })
            Button((this.mode === 'passkey' ? '✓  ' : '') + 'Passkey 登录', { type: ButtonType.Normal })
              .height(48).borderRadius(12).fontSize(14)
              .backgroundColor(this.nativeDark ? '#2C2C2E' : '#F5F6F7')
              .fontColor(this.nativeDark ? '#F9FAFB' : '#0F1115')
              .border({ width: 1, color: this.mode === 'passkey' ? '#ADB2B8' : Color.Transparent })
              .width('100%').onClick(() => { this.mode = 'passkey'; })
            Button((this.mode === 'none' ? '✓  ' : '') + '无验证登录（受信任网络）', { type: ButtonType.Normal })
              .height(48).borderRadius(12).fontSize(14)
              .backgroundColor(this.nativeDark ? '#2C2C2E' : '#F5F6F7')
              .fontColor(this.nativeDark ? '#F9FAFB' : '#0F1115')
              .border({ width: 1, color: this.mode === 'none' ? '#ADB2B8' : Color.Transparent })
              .width('100%').onClick(() => { this.mode = 'none'; })
            Text('登录策略由网关控制。选择无验证不会绕过服务端认证。Passkey 需要有效 HTTPS 证书及系统 FIDO2 支持。')
              .fontSize(12).fontColor(this.nativeDark ? '#CFD3D6' : '#61666B')
            Button(this.busy ? '正在连接…' : '连接工作空间', { type: ButtonType.Normal })
              .height(48).borderRadius(12).fontSize(14).width('100%').enabled(!this.busy)
              .backgroundColor(this.nativeDark ? '#F9FAFB' : '#0F1115')
              .fontColor(this.nativeDark ? '#151517' : '#FFFFFF')
              .onClick(() => { this.connect().catch(() => { this.error = '连接失败'; }); })
          }.padding(28).width('100%').constraintSize({ maxWidth: 600 })
        }.layoutWeight(1).width('100%')
      }
      if (this.error) { Text(this.error).fontColor('#b91c1c').fontSize(13).padding(10) }
    }.width('100%').height('100%').backgroundColor(this.nativeDark ? '#151517' : '#FFFFFF')
  }
}
