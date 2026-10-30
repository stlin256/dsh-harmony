import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { deviceInfo, power } from '@kit.BasicServicesKit';
import { accessibility } from '@kit.AccessibilityKit';
import { uiMaterial } from '@kit.ArkUI';

export class NativeExperience {
  static refresh(context: common.Context): void {
    const store = preferences.getPreferencesSync(context, { name: 'pocket-native-experience' });
    AppStorage.setOrCreate<string>('nativeThemeMode', store.getSync('themeMode', 'system') as string);
    AppStorage.setOrCreate<boolean>('nativeReduceTransparency', store.getSync('reduceTransparency', false) === true);
    AppStorage.setOrCreate<boolean>('nativeUserReduceMotion', store.getSync('reduceMotion', false) === true);
    try { AppStorage.setOrCreate<boolean>('nativeSystemReduceMotion', accessibility.isAnimationReduceEnabledSync()); }
    catch (_) { AppStorage.setOrCreate<boolean>('nativeSystemReduceMotion', true); }
    try {
      const mode = power.getPowerMode();
      AppStorage.setOrCreate<boolean>('nativePowerSaving', mode !== power.DevicePowerMode.MODE_NORMAL && mode !== power.DevicePowerMode.MODE_PERFORMANCE);
    } catch (_) { AppStorage.setOrCreate<boolean>('nativePowerSaving', true); }
    NativeExperience.changed();
  }

  static setPreference(context: common.Context, key: string, value: boolean): void {
    if (key !== 'reduceTransparency' && key !== 'reduceMotion') throw new Error('Unknown presentation preference');
    const store = preferences.getPreferencesSync(context, { name: 'pocket-native-experience' });
    const previous = store.getSync(key, false);
    try { store.putSync(key, value); store.flushSync(); }
    catch (error) { store.putSync(key, previous); throw error as Error; }
    NativeExperience.refresh(context);
  }

  static changed(): void {
    AppStorage.setOrCreate<number>('nativeExperienceRevision', (AppStorage.get<number>('nativeExperienceRevision') || 0) + 1);
  }

  static materialsEnabled(): boolean {
    // Do not resolve API-26 objects until the runtime version gate has passed.
    if (deviceInfo.sdkApiVersion < 26 || !canIUse('SystemCapability.ArkUI.ArkUI.Full')) return false;
    if (AppStorage.get<boolean>('nativeReduceTransparency') === true || AppStorage.get<boolean>('nativePowerSaving') === true ||
      AppStorage.get<boolean>('nativeAppActive') === false) return false;
    try { return uiMaterial.getMaterialInfo().state !== uiMaterial.MaterialState.DISABLE; }
    catch (_) { return false; }
  }

  static reducedMotion(): boolean {
    return AppStorage.get<boolean>('nativeUserReduceMotion') === true || AppStorage.get<boolean>('nativeSystemReduceMotion') === true;
  }

  static titleOptions(dark: boolean, _revision: number): NavigationTitleOptions {
    const options: NavigationTitleOptions = { backgroundColor: dark ? '#151517' : '#FFFFFF', barStyle: BarStyle.STANDARD };
    if (deviceInfo.sdkApiVersion >= 26) {
      // Explicit empty also disables system defaults when accessibility or power
      // policy requests an opaque surface. It differs from undefined.
      options.systemMaterial = NativeExperience.materialsEnabled() ? new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.THIN, interactive: false, applyShadow: false, lightEffect: null
      }) : uiMaterial.Material.empty;
    }
    return options;
  }

  static state(context: common.Context): string {
    const store = preferences.getPreferencesSync(context, { name: 'pocket-native-experience' });
    return JSON.stringify({ themeMode: store.getSync('themeMode', 'system'), reduceTransparency: store.getSync('reduceTransparency', false) === true,
      reduceMotion: store.getSync('reduceMotion', false) === true,
      systemReduceMotion: AppStorage.get<boolean>('nativeSystemReduceMotion') === true,
      materialEnabled: NativeExperience.materialsEnabled() });
  }
}

/** Used only inside Navigation's title builder, an API-26 permitted surface. */
export class ChromeMaterialModifier implements AttributeModifier<ButtonAttribute> {
  constructor(_revision: number) {}
  applyNormalAttribute(instance: ButtonAttribute): void {
    if (deviceInfo.sdkApiVersion < 26) return;
    if (!NativeExperience.materialsEnabled()) { instance.systemMaterial(uiMaterial.Material.empty); return; }
    instance.systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      interactive: !NativeExperience.reducedMotion(),
      applyShadow: false,
      lightEffect: NativeExperience.reducedMotion() ? null : { color: Color.White }
    }));
  }
}
