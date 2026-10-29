# DSH Harmony plugin

简体中文 · English

安装这一个插件即可为 Harness 增加 DSH Harmony 原生登录、会话接口、实时通道、任务概览、分级通知队列和网页会话定位。无需独立 relay 或常驻网关进程。Node.js 24.9+；需使用提供 `connection.requestRejection`、`connection.authorizeIndex`、`connection.authenticatedUrl` 的 Harness 版本。

从仓库根目录运行 `node scripts/package-plugin.mjs`，生成 `.artifacts/dsh-harmony-plugin-0.2.3.tgz`。通过 Harness 的插件管理安装该包，并启用 `@dsh-harmony/plugin`。也可以将包作为当前 web profile 的依赖安装，在 `cordis.patch.yml` 追加：

```yaml
- insert:
    - id: dsh-harmony
      name: '@dsh-harmony/plugin'
```

App 默认选择“原生登录”。填写 Harness Web 地址和启动 URL 中 `token=` 后的访问密钥；已有有效登录时不必再次填写密钥。原生登录直接调用 Harness 的正式令牌交换与签名 Cookie 验证，兼容 HTTP 和 HTTPS、局域网和公网。配置监听地址、受信任主机和公网 TLS 时遵循 Harness 自身的网络配置；插件不代替路由或端口映射。

Pocket ID Passkey 是可选的另一种登录方式，要求 HTTPS。其部署工具、适配器及说明位于仓库 `deploy/` 和 `docs/OIDC-DEPLOYMENT.md`。浏览器与 App 共用现有 Pocket ID 登录，不需要再注册独立的插件 Passkey。

数据默认保存在 `$DSH_HOME/harmony.sqlite`（未设置 DSH_HOME 时为 `~/.dsh/harmony.sqlite`）。插件保存启用后观测到的任务名、状态和待确认路由，不保存消息正文。通知等级由每台设备设置；推送构建还需配置 Huawei Push Kit 和 `HUAWEI_SERVICE_ACCOUNT`。应用商店构建不需要 Push Kit 服务帐号。

The single plugin provides native Harness login, session APIs, live updates, task overview, notification levels and web session handoff. No separate relay or gateway daemon is required. Build the installable package using `node scripts/package-plugin.mjs`, then install and enable `@dsh-harmony/plugin` through Harness's plugin manager or its web-profile Cordis patch.

Native login is the default. Enter the Harness Web origin and the access key from its startup URL's `token` query parameter. It reuses Harness's official token exchange and signed-cookie validation over HTTP or HTTPS. Configure network binding and trusted hosts using the standard Harness deployment settings. Optional Pocket ID login requires HTTPS and the OIDC adapter documented in the repository. The personal HAP uses the Huawei Push Kit service account; the AppGallery HAP excludes Push Kit.
