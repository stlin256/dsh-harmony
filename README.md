# DSH Harmony · DSH Pocket

HarmonyOS 原生 ArkWeb 应用，加载 DeepSeek Harness 原版远程 Web 界面。客户端目录保留 `dsh-pocket` 名称，GitHub 仓库为 **dsh-harmony**。

- 原版 Harness 会话、工具、文件和实时输出；原生连接向导、返回、刷新、文件选择、明暗主题。
- Passkey 注册与登录，系统 FIDO2 验证；显式启用的无验证模式。
- Huawei Push Kit：完成、失败、审批提醒，SQLite 投递队列、重试、去重及退出撤销。
- 单用户、单 Harness 实例模型；所有配对设备共享该工作空间。

```text
HarmonyOS ArkWeb → HTTPS 反向代理 → Pocket 网关 → 本机 Harness Web
                                    ↑
Harness 通知插件 → 认证事件入口 → SQLite 队列 → Huawei Push → 系统通知
```

| 目录 | 内容 |
| --- | --- |
| `harmony/` | DevEco Studio / ArkTS Stage 工程 |
| `gateway/` | Node.js 24 网关、Passkey 页面、Huawei Push 服务 |
| `plugins/pocket-notify/` | Harness Cordis 事件插件 |
| `docs/DEPLOYMENT.md` | 服务端部署和原生编译交接 |
| `docs/VALIDATION.md` | 已验证内容、验收步骤和已知边界 |

在 DevEco Studio 中打开 `harmony/`，复制 `build-profile.example.json5` 为 `build-profile.json5`，使用自己的签名配置。连接前先按 [部署文档](docs/DEPLOYMENT.md) 启动网关和插件。

本环境已运行服务端测试，**没有 HarmonyOS SDK、设备和 Huawei 项目凭据，未生成或验证 HAP**。Passkey 的系统兼容性、签名权限和真实 Push 到达需要按 [验收文档](docs/VALIDATION.md) 验证。

```bash
cd gateway
npm ci
npm test
```

所有实际地址、启动令牌、签名文件和服务账号只放本机忽略文件。提交前运行 `node scripts/check-publication.mjs`；可用环境变量 `DSH_PRIVATE_HOSTS` 额外检查私有域名，检查输出不会打印匹配值。

项目遵循 [AGPL-3.0](LICENSE)。参考来源及研究版本见 [NOTICE](NOTICE)。
