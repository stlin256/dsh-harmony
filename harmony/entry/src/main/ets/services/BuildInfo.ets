import { bundleManager } from '@kit.AbilityKit';

export class BuildInfo {
  static readonly appName: string = 'DSH Harmony';
  static readonly version: string = BuildInfo.installedVersion();
  static readonly bundleName: string = 'io.github.stlin256.dshharmony';
  static readonly author: string = 'stlin256';
  static readonly authorProfile: string = 'https://github.com/stlin256';
  static readonly repository: string = 'https://github.com/stlin256/dsh-harmony';
  static readonly issues: string = 'https://github.com/stlin256/dsh-harmony/issues/new';
  static readonly copyright: string = '© 2026 stlin256 and contributors';

  private static installedVersion(): string {
    try {
      return bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).versionName || '未知';
    } catch (_) {
      return '未知';
    }
  }
}
