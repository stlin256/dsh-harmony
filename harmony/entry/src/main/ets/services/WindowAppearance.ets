import { display, window } from '@kit.ArkUI';

/** Shares the actual website appearance with the native window and system bars. */
export class WindowAppearance {
  static mainWindow: window.Window | null = null;
  static refreshSafeArea(): void {
    if (WindowAppearance.mainWindow === null) return;
    try {
      const system = WindowAppearance.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const cutout = WindowAppearance.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      const density = display.getDefaultDisplaySync().densityPixels || 1;
      const top = Math.max(system.visible ? system.topRect.height : 0,
        cutout.visible ? cutout.topRect.height : 0) / density;
      const bottom = Math.max(system.visible ? system.bottomRect.height : 0,
        cutout.visible ? cutout.bottomRect.height : 0) / density;
      const left = Math.max(system.visible ? system.leftRect.width : 0,
        cutout.visible ? cutout.leftRect.width : 0) / density;
      const right = Math.max(system.visible ? system.rightRect.width : 0,
        cutout.visible ? cutout.rightRect.width : 0) / density;
      AppStorage.setOrCreate<number>('nativeSafeTop', Math.ceil(top));
      AppStorage.setOrCreate<number>('nativeSafeBottom', Math.ceil(bottom));
      AppStorage.setOrCreate<number>('nativeSafeLeft', Math.ceil(left));
      AppStorage.setOrCreate<number>('nativeSafeRight', Math.ceil(right));
    } catch (_) {
      AppStorage.setOrCreate<number>('nativeSafeTop', 0);
      AppStorage.setOrCreate<number>('nativeSafeBottom', 0);
      AppStorage.setOrCreate<number>('nativeSafeLeft', 0);
      AppStorage.setOrCreate<number>('nativeSafeRight', 0);
    }
  }

  static async fullscreen(enabled: boolean): Promise<void> {
    if (WindowAppearance.mainWindow === null) return;
    await WindowAppearance.mainWindow.setWindowSystemBarEnable(enabled ? [] : ['status', 'navigation']);
    await WindowAppearance.mainWindow.setWindowLayoutFullScreen(enabled);
  }

  static apply(dark: boolean): void {
    AppStorage.setOrCreate<boolean>('nativeDark', dark);
    WindowAppearance.applyBars(dark);
    WindowAppearance.refreshSafeArea();
  }

  static applyBars(dark: boolean): void {
    if (WindowAppearance.mainWindow === null) return;
    const surface = dark ? '#151517' : '#FFFFFF';
    WindowAppearance.mainWindow.setWindowSystemBarProperties({
      // Keep both system bars visible, but paint their inset areas with the
      // page surface so the gesture handle doesn't sit in a contrasting strip.
      statusBarColor: surface,
      navigationBarColor: surface,
      statusBarContentColor: dark ? '#FFFFFF' : '#000000',
      navigationBarContentColor: dark ? '#FFFFFF' : '#000000'
    }).catch(() => {});
  }
}
