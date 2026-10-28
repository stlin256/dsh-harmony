import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';

/** A temporary surface: the native workspace stays mounted underneath. */
@Component
export struct NativeCompatibilitySurface {
  origin: string = '';
  sessionId: string = '';
  onClose: () => void = (): void => {};
  @StorageLink('nativeDark') private dark: boolean = false;
  @State private error: string = '';
  @State private progress: number = 0;
  private controller: webview.WebviewController = new webview.WebviewController();
  private context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
  private allowed(url: string): boolean { return url === this.origin || url.startsWith(this.origin + '/'); }
  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text('完整工作空间').fontSize(16).fontWeight(FontWeight.Medium).layoutWeight(1)
          .fontColor(this.dark ? '#F9FAFB' : '#0F1115')
        Button('后退').height(44).onClick(() => { if (this.controller.accessBackward()) this.controller.backward(); })
        Button('返回原生').height(44).onClick(this.onClose)
      }.padding({ left: 16, right: 16 }).width('100%')
      if (this.progress < 100) { Progress({ value: this.progress, total: 100 }).height(2).width('100%') }
      Web({ src: this.origin + '/?dshHarmonySession=' + encodeURIComponent(this.sessionId), controller: this.controller })
        .width('100%').layoutWeight(1).javaScriptAccess(true).domStorageAccess(true).databaseAccess(true)
        .fileAccess(false).mixedMode(MixedMode.None).darkMode(WebDarkMode.Auto).forceDarkAccess(false)
        .keyboardAvoidMode(WebKeyboardAvoidMode.RESIZE_CONTENT)
        .backgroundColor(this.dark ? '#151517' : '#FFFFFF')
        .onLoadIntercept((event) => { const blocked = !this.allowed(event.data.getRequestUrl());
          if (blocked) this.error = '站外链接请使用系统浏览器打开'; return blocked; })
        .onWindowNew((event) => { if (this.allowed(event.targetUrl)) this.controller.loadUrl(event.targetUrl); })
        .onProgressChange((event) => { this.progress = event.newProgress; })
        .onErrorReceive((event) => { if (event.request.isMainFrame()) this.error = '加载失败，请检查网络连接'; })
        .onRenderExited(() => { this.error = '网页渲染中断，请重新打开此面板'; })
        .onShowFileSelector((event) => {
          const options = new picker.DocumentSelectOptions();
          options.maxSelectNumber = event.fileSelector.getMode() === FileSelectorMode.FileOpenMultipleMode ? 10 : 1;
          new picker.DocumentViewPicker(this.context).select(options)
            .then((uris: string[]) => event.result.handleFileList(uris)).catch(() => event.result.handleFileList([]));
          return true;
        })
      if (this.error) { Text(this.error).fontSize(12).fontColor(this.dark ? '#FF9393' : '#C53030').padding(12) }
    }.width('100%').height('100%').backgroundColor(this.dark ? '#151517' : '#FFFFFF')
  }
}
