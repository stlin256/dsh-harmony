import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { DSHIcon } from './DSHIcon';
import { NativeMotion } from '../services/NativeMotion';

/** A temporary surface: the native workspace stays mounted underneath. */
@Component
export struct NativeCompatibilitySurface {
  origin: string = '';
  sessionId: string = '';
  destination: string = '';
  presentation: string = '';
  onClose: () => void = (): void => {};
  @StorageLink('nativeDark') private dark: boolean = false;
  @State private error: string = '';
  @State private progress: number = 0;
  @State private canGoBack: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
  private allowed(url: string): boolean { return url === this.origin || url.startsWith(this.origin + '/'); }
  private title(): string {
    if (this.destination === 'plugins') return '插件';
    if (this.destination === 'automation') return '自动化任务';
    if (this.destination === 'more') return '更多';
    return '完整工作空间';
  }
  private source(): string {
    const destination = ['plugins', 'automation', 'more'].includes(this.destination) ? this.destination : '';
    return this.origin + '/?dshHarmonySession=' + encodeURIComponent(this.sessionId) +
      (destination ? '&dshHarmonyRoute=' + destination : '');
  }
  private goBack(): void {
    try {
      if (!this.controller.accessBackward()) return;
      NativeMotion.animate(this.getUIContext(), 'navigation', (): void => { this.controller.backward(); });
    } catch (_) {
      this.canGoBack = false;
    }
  }
  private refreshHistory(): void {
    try {
      this.canGoBack = this.controller.accessBackward();
    } catch (_) {
      // The controller is not associated until the Web node reaches page end.
      this.canGoBack = false;
    }
  }
  build() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        Button({ type: ButtonType.Normal }) {
          DSHIcon({ glyph: 'chevron-left-outline', glyphSize: 17,
            color: this.dark ? '#F2F2F3' : '#25262A' })
        }.width(40).height(40).borderRadius(12)
          .backgroundColor(this.dark ? '#2C2C2E' : '#F5F6F7')
          .border({ width: 0.5, color: this.dark ? '#45464A' : '#DFE1E5' })
          .opacity(this.canGoBack ? 1 : 0.42)
          .enabled(this.canGoBack)
          .accessibilityText('网页后退').onClick((): void => { this.goBack(); })
        Text(this.title()).fontSize(16).fontWeight(FontWeight.Medium).layoutWeight(1)
          .fontColor(this.dark ? '#F9FAFB' : '#0F1115')
        Button({ type: ButtonType.Normal }) {
          DSHIcon({ glyph: 'close-outline', glyphSize: 17,
            color: this.dark ? '#F2F2F3' : '#25262A' })
        }.width(40).height(40).borderRadius(12)
          .backgroundColor(this.dark ? '#2C2C2E' : '#F5F6F7')
          .border({ width: 0.5, color: this.dark ? '#45464A' : '#DFE1E5' })
          .accessibilityText('关闭并返回原生').onClick(this.onClose)
      }.height(48).padding({ left: 12, right: 12 }).width('100%')
      if (this.progress < 100) { Progress({ value: this.progress, total: 100 }).height(2).width('100%') }
      Web({ src: this.source(), controller: this.controller })
        .width('100%').layoutWeight(1).javaScriptAccess(true).domStorageAccess(true).databaseAccess(true)
        .fileAccess(false).mixedMode(MixedMode.None).darkMode(WebDarkMode.Auto).forceDarkAccess(false)
        .keyboardAvoidMode(WebKeyboardAvoidMode.RESIZE_CONTENT)
        .backgroundColor(this.dark ? '#151517' : '#FFFFFF')
        .onLoadIntercept((event) => { const blocked = !this.allowed(event.data.getRequestUrl());
          if (blocked) this.error = '站外链接请使用系统浏览器打开'; return blocked; })
        .onWindowNew((event) => { if (this.allowed(event.targetUrl)) this.controller.loadUrl(event.targetUrl); })
        .onProgressChange((event) => { this.progress = event.newProgress; })
        .onPageEnd(() => {
          this.refreshHistory();
          if (this.allowed(this.controller.getUrl())) this.controller.runJavaScript(this.presentation).catch(() => {});
        })
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
