import { window } from '@kit.ArkUI';

/** Shares the actual website appearance with the native window and system bars. */
export class WindowAppearance {
  static mainWindow: window.Window | null = null;

  static async fullscreen(enabled: boolean): Promise<void> {
    if (WindowAppearance.mainWindow === null) return;
    await WindowAppearance.mainWindow.setWindowSystemBarEnable(enabled ? [] : ['status', 'navigation']);
    await WindowAppearance.mainWindow.setWindowLayoutFullScreen(enabled);
  }

  static apply(dark: boolean): void {
    AppStorage.setOrCreate<boolean>('nativeDark', dark);
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
