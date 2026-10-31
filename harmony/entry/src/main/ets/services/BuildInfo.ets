import { bundleManager } from '@kit.AbilityKit';

export class BuildInfo {
  static readonly appName: string = 'DSH Harmony';
  static readonly version: string = BuildInfo.installedVersion();
  static readonly bundleName: string = 'io.github.stlin256.dshharmony';
  static readonly author: string = 'stlin256';
  static readonly authorProfile: string = 'https://github.com/stlin256';
  static readonly repository: string = 'https://github.com/stlin256/DSH-Harmony';
  static readonly issues: string = 'https://github.com/stlin256/DSH-Harmony/issues/new';
  static readonly pluginInstallGuide: string =
    'https://github.com/stlin256/DSH-Harmony/blob/main/docs/PLUGIN-INSTALL.md';
  static readonly pluginReleaseTag: string = 'plugin-v0.3.6';
  static readonly pluginArtifactVersion: string = '0.3.6';
  static readonly pluginArtifact: string =
    'https://github.com/stlin256/DSH-Harmony/releases/download/plugin-v0.3.6/dsh-harmony-plugin-0.3.6.tgz';
  static readonly pluginInstallPrompt: string =
    '请按 https://github.com/stlin256/DSH-Harmony/blob/main/docs/PLUGIN-INSTALL.md 的说明，' +
    '为当前 DSH web profile 安装并启用 DSH Harmony 插件；使用与 App 匹配的 plugin-v0.3.6 Release 中的 ' +
    'dsh-harmony-plugin-0.3.6.tgz，安装后确认 @dsh-harmony/plugin 正常运行并报告版本。';
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
