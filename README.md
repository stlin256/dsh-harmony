# DSH Harmony

简体中文 · [English](README.en.md)

面向 HarmonyOS 的 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 伴侣应用。兼容界面保留原版网页；实验性原生界面提供会话、消息、工具与实时交互，并接入系统通知和桌面服务卡片。

## 两种登录方式

| 方式 | 服务端需要 | App 填写 |
| --- | --- | --- |
| **原生登录（默认）** | Harness + 本仓库一个 DSH 插件 | 服务地址、Harness 访问密钥 |
| **Pocket ID · Passkey** | 上述插件 + 可选 Pocket ID OIDC 认证入口 | 工作空间 HTTPS 地址、系统 Passkey |

原生登录复用 Harness 正式的启动密钥交换和签名 Cookie，不要求额外 relay 或网关进程，兼容 HTTP/HTTPS。Pocket ID 登录复用已有 Passkey，要求 HTTPS。两者均支持局域网和公网部署。登录方式与界面模式分别选择。

## 快速开始

1. 准备可访问的 Harness Web，服务器 Node.js 24.9+。
2. 在 `gateway/` 运行 `npm ci`，回到仓库根目录运行 `node scripts/package-plugin.mjs`。
3. 在 Harness 插件管理中安装生成的 `.artifacts/dsh-harmony-plugin-0.1.2.tgz`，启用 `@dsh-harmony/plugin`。[手动安装说明](plugins/dsh-harmony/README.md)。
4. 安装 App，默认选原生登录，填写地址和 Harness 启动 URL 中 `token=` 后的访问密钥。密钥不保存在 App 配置中；后续使用有效 Cookie。
5. 可选 Pocket ID 的[流程与工具](docs/OIDC-DEPLOYMENT.md)均在仓库中，配置后选择下面的 Passkey 登录。

网络监听、受信任主机、端口映射和 TLS 按环境配置，见[部署指南](docs/DEPLOYMENT.md)。

## 功能与状态

- 兼容模式保留 Harness 原版工作空间、插件和高级控件。
- 原生模式（实验）提供会话、文本/图片、工具、模型、队列、审批、提问和实时输出。覆盖范围见[界面模式](docs/UI-MODES.md)与[能力核对表](docs/NATIVE-COVERAGE.md)。
- 本机主题、动效和连接管理；登录失败或离线时仍可退出。
- 2×2 工作空间入口和 2×4 匿名状态卡片，使用带时间的本地快照，不保证后台实时更新。
- 插件收集任务/审批事件，SQLite 保存通知队列。实际系统推送另需当前 Harmony 应用对应的 Huawei Push Kit 与服务账号；未配置时推送关闭。

目标 SDK 26，最低 API 23。Release 已通过 DevEco CLI 编译和真机安装，原生完整覆盖与设备兼容性仍在推进。

## 开发与文档

[插件](plugins/dsh-harmony/README.md) · [部署](docs/DEPLOYMENT.md) · [Pocket ID](docs/OIDC-DEPLOYMENT.md) · [HarmonyOS 7](docs/HARMONY7.md) · [验证](docs/VALIDATION.md)

运行检查：`cd gateway && npm ci && npm test`。原生工程在 `harmony/`，可选认证工具在 `deploy/`。`gateway/` 是由插件复用的服务模块，不要求独立运行。签名、实际地址、服务账号和用户数据保留在本机；提交前运行 `node scripts/check-publication.mjs`。

[AGPL v3](LICENSE)，来源见 [NOTICE](NOTICE)。可选 OIDC 网关保留 [MIT 许可证](deploy/pocket-id-gateway/LICENSE)和[上游版本](deploy/pocket-id-gateway/UPSTREAM.md)。
