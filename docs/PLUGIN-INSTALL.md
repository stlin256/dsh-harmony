# Install the DSH Harmony Plugin

[简体中文](#简体中文) · [English](#english)

## 简体中文

DSH Harmony App 需要 `@dsh-harmony/plugin` 向 DSH 增加原生登录、会话、实时更新、通知和移动端会话定位。插件由本仓库维护，并与 App 一起发布。

### 一句话安装

把下面整句发送给 DSH：

> 请按 https://github.com/stlin256/DSH-Harmony/blob/main/docs/PLUGIN-INSTALL.md 的说明，为当前 DSH web profile 安装并启用 DSH Harmony 插件；使用与 App 匹配的 `plugin-v0.3.6` Release 中的 `dsh-harmony-plugin-0.3.6.tgz`，安装后确认 `@dsh-harmony/plugin` 正常运行并报告版本。

这句话也显示在 App 首次引导中，可直接复制。

### 在 DSH 中手动安装

1. 打开 DSH 的 **插件**。
2. 选择 **Add plugin**。
3. 粘贴与当前 App 匹配的版本化安装地址：

   ```text
   https://github.com/stlin256/DSH-Harmony/releases/download/plugin-v0.3.6/dsh-harmony-plugin-0.3.6.tgz
   ```

4. 确认来源，安装并启用 **DSH Harmony**。
5. 重启或重连 DSH。重新打开 App，在 **设置 → DSH 设置** 中核对插件版本。

DSH 的插件管理器只安装声明了 `dsh.bundle.patch` 的 bundle。本项目发布包已经包含 patch、Host 入口、浏览器入口、本地化元数据和全部生产依赖。

不要把 `plugins/dsh-harmony/` 源码子目录直接作为 Git 安装目标。该目录在仓库内通过相对路径复用 gateway；发布压缩包是完整的可安装单元。

### Agent 或命令行

启用 `plugin_manager` 工具的 DSH 预设可以让 Agent 安装上述 tarball。命令行环境也可以使用 DSH 的正式插件命令：

```sh
dsh plugin --profile web add <与 App 匹配的 tgz URL>
```

安装成功并不等于模块已激活。确认 bundle 已启用，并检查 Harness 重启后的日志。

### 更新

App 和插件使用独立版本号。升级时使用与 App 对应的固定插件版本，避免 `latest` 在 DSH 版本兼容范围外漂移。版本不匹配时，先查看 Release 说明中的兼容表。

## English

DSH Harmony needs `@dsh-harmony/plugin` to add native login, sessions, live updates, notifications and mobile session handoff to DSH. The plugin is maintained in this repository and released alongside the app.

### One-sentence install

Send this sentence to DSH:

> Follow https://github.com/stlin256/DSH-Harmony/blob/main/docs/PLUGIN-INSTALL.md to install and enable DSH Harmony for the current DSH web profile. Use `dsh-harmony-plugin-0.3.6.tgz` from the matching `plugin-v0.3.6` release, then verify that `@dsh-harmony/plugin` is running and report its version.

The same prompt is available through the app's first-run guide.

### Install in DSH

1. Open **Plugins** in DSH.
2. Select **Add plugin**.
3. Paste the versioned artifact URL:

   ```text
   https://github.com/stlin256/DSH-Harmony/releases/download/plugin-v0.3.6/dsh-harmony-plugin-0.3.6.tgz
   ```

4. Verify the source, install and enable **DSH Harmony**.
5. Restart or reconnect DSH. Reopen the app and check the plugin version under **Settings → DSH Settings**.

The plugin manager accepts bundles that declare `dsh.bundle.patch`. The release contains its patch, host entry, browser entry, localized metadata and production dependency closure.

Do not install the repository's `plugins/dsh-harmony/` source directory through a Git spec. Inside the monorepo it resolves the gateway through relative paths; the release tarball is the complete install unit.

### Agent or CLI

A DSH preset with the `plugin_manager` tool can install the tarball. A terminal deployment can use the official plugin command:

```sh
dsh plugin --profile web add <matching-tgz-url>
```

Successful installation does not prove activation. Confirm the bundle is enabled and inspect Harness after restart.
