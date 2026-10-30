# Pocket ID Passkey 部署 / Deployment

默认原生登录只需安装 [`@dsh-harmony/plugin`](../plugins/dsh-harmony/README.md)，使用 Harness 启动 URL 的访问密钥。以下内容仅用于可选的 Pocket ID Passkey 登录。原生模式可用 HTTP/HTTPS；Passkey 模式必须使用 HTTPS。两者均可部署在局域网或公网。

## 已有 Pocket ID 和 Harness OIDC 网关

准备 Node.js 24.9+、Python 3、pnpm 和 systemd。先运行 `node scripts/package-plugin.mjs`，把生成的 `.tgz` 解包到发布目录的 `plugins/dsh-harmony/`；该目录必须包含脚本验证过的生产依赖，不能只复制仓库中的轻量 `plugins/dsh-harmony/`。同时将 `deploy/` 放在 `/srv/dsh-harmony/releases/<release>/`，然后执行：

```bash
sudo python3 deploy/install-pocket-id.py \
  --release /srv/dsh-harmony/releases/RELEASE \
  --profile /path/to/dsh/profiles/web \
  --harness-user YOUR_HARNESS_USER \
  --oidc-root /opt/harness-passkey-gateway \
  --oidc-env /etc/harness-gateway/gateway.env
```

安装器备份原配置，安装一个 DSH 插件和 OIDC 适配器，生成服务间随机密钥，准备两个 systemd 覆盖文件；不主动重启服务。核对输出的备份路径，确认没有运行中的任务，然后执行：

```bash
sudo systemctl daemon-reload
sudo systemctl restart deepseek-harness harness-gateway
```

没有新增独立 Harmony 后台服务或 relay。插件在 Harness 进程内承载 `/pocket/*`；现有 OIDC 网关验证账号后才将这些请求交给插件。App 填工作空间 HTTPS 地址，选择下面的“Pocket ID · Passkey”。局域网使用同样可访问且证书受信任的 HTTPS 地址。

安装器在切换 `current` 前会实际导入发布目录中的插件入口。若发布包缺少依赖，安装立即停止，原发布和原 profile 保持可用。

## 从零准备 Passkey

1. 按 [Pocket ID 官方部署文档](https://pocket-id.org/docs/setup/installation) 部署身份服务，提供 HTTPS 身份域名。仓库 `deploy/pocket-id.env.example`、`deploy/pocket-id.service` 提供独立二进制服务模板；实际版本及二进制校验按官方发行说明选择。
2. 在身份服务中登记你的 Passkey。创建 confidential OIDC client，回调地址为 `https://agent.example.com/_gateway/callback`，启用 PKCE S256，scope 为 `openid profile email`。保存 Client ID、Client Secret 和允许登录账号的稳定 subject。
3. 运行 `sudo python3 deploy/bootstrap-passkey.py --harness-user YOUR_HARNESS_USER`。它安装仓库随附的可选 OIDC 网关、准备受限配置和启动凭据目录，不启动未配置的服务。已有网关时跳过此步。
4. 编辑 `/etc/harness-gateway/gateway.env`：设置 `PUBLIC_URL`、`OIDC_ISSUER`、客户端凭据、`ALLOWED_SUBJECTS` 和本机 `HARNESS_UPSTREAM`。保留配置权限 0600，不放入 Git。先按上一节安装插件和适配器，再重启 Harness；插件会将当前启动凭据写到工具准备的私有文件，网关不会把它传给 App。
5. 按 `deploy/Caddyfile.example` 配置 HTTPS 入口。将工作空间转发至网关端口 4180，将身份服务域名转发至 Pocket ID。证书和路由按实际网络配置；局域网可使用受信任内部 CA。
6. 启用网关：`sudo systemctl enable --now harness-gateway`。检查 `/pocket/api/state` 返回 `mode: proxy`、认证源是配置的 Pocket ID 地址；未登录的 `/pocket/` 应跳转到 OIDC 登录。然后在 App 完成一次真实 Passkey 验证。

可选 OIDC 网关保留原 MIT 许可证和[源仓库版本](../deploy/pocket-id-gateway/UPSTREAM.md)。升级网关源码时，安装器会核对预期补丁位置，未知结构会拒绝修改。部署前的文件备份位于 `/var/backups/dsh-harmony/`；回滚时恢复原网关源码、profile 的包/锁/patch 文件、systemd 覆盖文件以及原 `current` 链接，再重启对应服务。保留 Harness 和会话数据库。

## 组件和使用方式

| 部署方式 | 服务器需要 | App 登录 |
| --- | --- | --- |
| 原生登录 | Harness Web + 本仓库单一 DSH 插件 | 服务地址 + Harness 访问密钥 |
| Pocket ID | 上述插件 + HTTPS + Pocket ID + 可选 OIDC 网关/适配器 | 工作空间 HTTPS 地址 + 系统 Passkey |

浏览器打开正常 Harness 地址即可使用原版网页；原生用户可使用原启动 URL 登录。Pocket ID 用户按现有 OIDC 流程登录。登录后 `/pocket/` 提供配套设置和任务概览。旧 DSH-Pocket 项目的设备 bearer relay 协议与本项目不同，不需要为 DSH Harmony 再部署它。

系统推送另需当前 Harmony 应用对应的 Huawei Push Kit 服务账号 `HUAWEI_SERVICE_ACCOUNT`。未配置时插件仍能提供登录、原生会话、任务状态和队列，但不会投递系统推送。事件只从插件启用后观测，不回填全部历史任务。

## English

Native login is the default and requires only the single `@dsh-harmony/plugin` installed in Harness. Enter the Web origin and access key from Harness's startup URL. HTTP and HTTPS are supported on LAN or public deployments; configure standard Harness binding and trusted hosts as appropriate.

Pocket ID login is optional and requires HTTPS. Build and extract the self-contained plugin artifact into `plugins/dsh-harmony/` under the release directory. The lightweight source directory by itself is not a deployable plugin because its nested gateway imports production dependencies. The bundled MIT OIDC gateway, `bootstrap-passkey.py`, `install-pocket-id.py`, environment/service templates and Caddy example provide the remaining deployment tools. Register a confidential Pocket ID OIDC client with PKCE S256 and the workspace's `/_gateway/callback`, keep credentials in the private server environment, and apply the installation command above. The installer verifies the staged plugin imports before switching releases, prepares backups and configuration without restarting services. Restart only after checking that Harness has no running tasks.

The adapter forwards `/pocket/*` only after verifying the existing OIDC session and strips browser-supplied attestation headers. The plugin requires both a loopback peer and the private adapter key. Native login independently uses Harness's public token exchange and signed-cookie validation. No additional companion daemon or relay is required. The App permits the configured identity origin for navigation; its native JavaScript bridge remains restricted to the workspace origin.

Browsers continue to use the normal Harness workspace. Huawei Push Kit credentials belonging to this Harmony app are additionally required for actual system notifications. Without them, login, sessions and event overview remain available, but push delivery is disabled.
