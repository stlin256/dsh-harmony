import { UIAbility, Want, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { WindowAppearance } from '../services/WindowAppearance';
import { NativeExperience } from '../services/NativeExperience';
import { accessibility } from '@kit.AccessibilityKit';

export default class EntryAbility extends UIAbility {
  private readonly motionChanged = (enabled: boolean): void => {
    AppStorage.setOrCreate<boolean>('nativeSystemReduceMotion', enabled);
    NativeExperience.changed();
  };
  onCreate(want: Want): void {
    AppStorage.setOrCreate<boolean>('systemDark', this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    AppStorage.setOrCreate<boolean>('pocketPageThemeKnown', false);
    webview.WebviewController.initializeWebEngine();
    // Debug builds alone expose the standard HDC-forwarded inspection socket.
    if (this.context.applicationInfo.debug) webview.WebviewController.setWebDebuggingAccess(true);
    this.updateTextScale(this.context.config);
    NativeExperience.refresh(this.context);
    try { accessibility.onAnimationReduceStateChange(this.motionChanged); } catch (_) {}
    this.route(want);
  }

  onNewWant(want: Want): void { this.route(want); }

  onForeground(): void {
    AppStorage.setOrCreate<boolean>('nativeAppActive', true);
    NativeExperience.refresh(this.context);
    AppStorage.setOrCreate<number>('pocketForegroundRevision', (AppStorage.get<number>('pocketForegroundRevision') || 0) + 1);
  }

  onBackground(): void {
    AppStorage.setOrCreate<boolean>('nativeAppActive', false);
    NativeExperience.changed();
  }

  onWindowStageCreate(stage: window.WindowStage): void {
    const mainWindow = stage.getMainWindowSync();
    WindowAppearance.mainWindow = mainWindow;
    // ArkWeb reports safe-area env() values to the original viewport-fit=cover page.
    // Paint the window underneath both bars instead of reserving white native bands.
    WindowAppearance.fullscreen(true).then(() => {
      WindowAppearance.refreshSafeArea();
      WindowAppearance.apply(this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      stage.loadContent('pages/Index');
    }).catch(() => { stage.loadContent('pages/Index'); });
  }

  private updateTextScale(config: Configuration): void {
    AppStorage.setOrCreate<number>('nativeTitleHeight', Math.min(88, Math.max(56, Math.ceil(56 * (config.fontSizeScale || 1)))));
  }

  onConfigurationUpdate(config: Configuration): void {
    AppStorage.setOrCreate<boolean>('systemDark', config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    this.updateTextScale(config);
    WindowAppearance.refreshSafeArea();
    // A manually selected Harness theme takes precedence over an OS change.
    // System-following pages notify us when their own theme changes.
    if (AppStorage.get<boolean>('pocketPageThemeKnown') !== true) {
      WindowAppearance.apply(config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    }
  }

  onDestroy(): void {
    try { accessibility.offAnimationReduceStateChange(this.motionChanged); } catch (_) {}
    WindowAppearance.mainWindow = null;
  }

  private route(want: Want): void {
    const route = want.parameters?.pocketRoute;
    if (typeof route === 'string' && ['workspace', 'overview', 'settings'].includes(route)) {
      AppStorage.setOrCreate<string>('requestedPocketRoute', route);
    }
    let sessionId: Object | undefined = want.parameters?.sessionId;
    const data = want.parameters?.data;
    if (typeof sessionId !== 'string' && typeof data === 'string' && data.length <= 4096) {
      try { sessionId = (JSON.parse(data) as Record<string, Object>).sessionId; } catch (_) {}
    } else if (typeof sessionId !== 'string' && data !== undefined && typeof data === 'object' && data !== null) {
      sessionId = (data as Record<string, Object>).sessionId;
    }
    if (typeof sessionId === 'string' && /^[A-Za-z0-9_-]{1,160}$/.test(sessionId)) {
      AppStorage.setOrCreate<string>('requestedSession', sessionId);
    }
  }
}
