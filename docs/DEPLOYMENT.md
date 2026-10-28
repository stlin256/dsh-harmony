# 编译与部署

## 原生登录：默认方式

准备运行中的 Harness Web 和 Node.js 24.9+。按[插件说明](../plugins/dsh-harmony/README.md)生成安装包，在 Harness 中安装启用 `@dsh-harmony/plugin`。一个插件包含登录、原生会话、实时通道、任务概览、通知队列和网页会话导航，不需要独立 relay 或网关进程。

App 默认选“原生登录”，填写服务地址及控制台启动 URL 中 `token=` 后的访问密钥。密钥通过 Harness 正式接口换取签名 Cookie，不作为无验证模式使用，也不保存进 App 设置。

局域网和公网均可使用 HTTP/HTTPS。具体接口监听、`--trusted-host`、端口映射及 TLS 遵循 Harness 的标准配置；安装插件不会自动修改网络。插件数据默认在 `$DSH_HOME/harmony.sqlite`。

## Pocket ID Passkey：可选方式

[部署流程与工具](OIDC-DEPLOYMENT.md)支持已有认证网关接入，也提供从零准备网关的模板。Passkey 要求 HTTPS 和手机受信任的证书，局域网与公网均可部署。

App 填工作空间入口，身份服务地址由已配置的网关返回。强制 Pocket ID 的入口要求选择 Passkey；仅安装插件的 Harness 入口使用原生访问密钥。其他项目的设备 bearer relay 协议地址不能作为本 App 地址。

## 通知

插件直接监听真实 `session/event` 并写入 SQLite，无需另装 `pocket-notify` 或配置公网事件密钥。保存任务名、状态与路由标识，不提交对话正文。历史继承事件被过滤，取消不作为完成提醒。

自用 `default` HAP 使用 Huawei Push Kit。需要已登记的 Harmony 应用、Push Kit 能力和项目级服务账号 JSON。将 Harness 服务的 `HUAWEI_SERVICE_ACCOUNT` 设为受限文件路径，不要提交私钥。`HUAWEI_TEST_MESSAGE` 默认为 true，类别默认为 MARKETING。`store` HAP 不打包 Push Kit；可选开启任务运行时后台监测，应用只在存在运行中任务时申请系统长时任务，并在任务结束后停止。

## 编译和安装 App

安装含 SDK 26 的 DevEco Studio。在 `harmony/` 将 `build-profile.example.json5` 复制为被 Git 忽略的 `build-profile.json5`，配置 bundle、开发证书、设备和 Profile。Passkey 需要 `ohos.permission.ACCESS_FIDO2_ONLINEAUTH`。

`build-profile.example.json5` 定义了两个产品：`default`（自用 Push Kit）和 `store`（不含 Push Kit）。保留本机签名资料，将两个产品的 `bundleName` 设置为开发者中心登记的应用 ID；个人 Push Kit 版与应用商店版应使用各自需要的签名配置。

```bash
devecocli signature generate --product default
devecocli signature generate --product store
devecocli build --product default --build-mode release
devecocli build --product store --build-mode release
devecocli run --module entry@default --product default --build-mode release --skip-build
```

使用同一产品的相同签名覆盖更新，保留数据。两个产品分别输出到 `harmony/entry/build/default/outputs/default/` 和 `harmony/entry/build/store/outputs/store/`。

## 浏览器和维护

浏览器继续打开正常 Harness 地址：原生部署使用启动 URL，Pocket ID 部署按现有 OIDC 登录。登录后 `/pocket/` 提供配套设置和任务概览。App 关闭后任务仍在服务器执行，插件持续采集后续事件。

升级前检查运行中的任务，保留配置、Harness 数据和 SQLite。Passkey 安装器备份到 `/var/backups/dsh-harmony/`，采用版本化 release 和 `current` 链接。`deploy/preflight.mjs` 输出任务数量；`deploy/verify-live.mjs` 使用私有启动文件验证原生登录、会话、实时通道和退出，不输出密钥或对话。

旧的[独立网关](STANDALONE-GATEWAY.md)作为高级方案保留，不是默认插件部署的必要组件。
