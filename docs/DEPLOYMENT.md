# 编译与部署交接

## 服务关系

此项目为单用户远程控制端。Passkey 网关控制进入同一个 Harness 工作空间的权限，不映射多个 Harness 用户。无验证模式允许能访问该服务的人控制工作空间，需由部署者在隔离网络内显式启用。

原版 Harness 没有在本研究版本中提供可直接复用的 Passkey 登录模块。网关实现 WebAuthn，认证后代理原版 UI 和 HTTP/WebSocket/SSE；服务端代持 Harness 自己的启动令牌交换得到的 cookie。客户端永远不需要知道 Harness 令牌。

研究版本见根目录 NOTICE。参考 [Harness Web 服务文档](https://github.com/deepseek-ai/deepseek-harness/tree/main/packages/host/webserver)、[SimpleWebAuthn 服务端接口](https://simplewebauthn.dev/docs/packages/server) 和 [HarmonyOS ArkWeb](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-webview)。

## 启动服务端

1. 安装 Node.js 24.9 或更新的 24.x 版本。在运行 Harness 的机器上启动 `dsh web`，让其只监听 loopback。使用该版本 CLI 的帮助设置监听地址和端口。
2. `cd gateway`，运行 `npm ci`；复制 `.env.example` 为 `.env`，权限设为仅服务用户可读。配置 `PUBLIC_ORIGIN` 为手机实际访问的 HTTPS 源地址，`UPSTREAM` 为本机 Harness Web 源地址。
3. 将 `dsh web` 输出的启动 URL 放入 `UPSTREAM_LAUNCH_URL`。网关启动时在服务器本机交换认证 cookie；该 URL 不进入 APP。Harness 重启会使尚未交换的启动令牌失效，应更新配置并重启网关。也可以只设置 `UPSTREAM_COOKIE` 为先前合法交换得到的 cookie。
4. 分别用 `openssl rand -hex 32` 生成 `BOOTSTRAP_SECRET` 和 `EVENT_SECRET`。前者仅用于首次注册 Passkey，后者仅供 Harness 插件提交事件；不要使用样例字符串。
5. `npm start`。网关固定监听 loopback，使用 HTTPS 反向代理暴露。实际配置只保留在本机。

下面仅为保留示例域名的 Caddy 配置，需替换为自己的有效域名。反向代理必须保留原始 Host/Origin，并支持 WebSocket 和流式响应。不要开放 Harness 本机端口让远端绕过认证网关。

```caddyfile
dsh.example.com {
    reverse_proxy 127.0.0.1:8787
}
```

网关不信任 `X-Forwarded-*`，严格检查 Host；修改请求必须携带同源 Origin。它会为代理到本机 Harness 的请求重写 Host/Origin/Cookie，并剥离客户端授权头。Pocket 路径为项目保留空间，不转给 Harness。TLS 由外层反向代理终止，应用不会忽略证书错误。

## Passkey 与无验证

默认 `AUTH_MODE=passkey`。手机打开网关后，输入首次配对密钥创建 Passkey；后续使用系统验证登录。注册和登录都要求 user verification，挑战有 120 秒有效期、一次性消费并绑定 HttpOnly cookie。会话 cookie 有效期 30 天。

当前版本只允许创建一个 owner credential。可通过系统 Passkey 同步或跨设备认证使用它；不提供新增独立凭据的页面。如果凭据丢失，停止网关，备份数据文件，然后在 `gateway/` 运行：

```bash
node --env-file=.env src/reset-owner.mjs --revoke-owner-and-all-devices
```

这会撤销全部会话、设备注册及待发送通知。更换首次配对密钥后重启，并重新配对。数据库包含 Passkey 公钥、会话哈希及设备推送 token，应按凭据文件保护，不得提交或分享。

无验证部署必须同时设置：

```dotenv
AUTH_MODE=none
ALLOW_NO_AUTH=true
```

APP 中的登录方式只是连接向导提示，不能改变或绕过服务端策略。无验证模式仍通过 cookie 区分每台设备的通知设置。退出会撤销通知和本机数据，但该模式的网页本来就无需验证。

## Huawei Push

在 AGC 创建 HarmonyOS 应用并启用 Push Kit，bundle 名称、签名证书及工程项目必须匹配。默认 bundle 为 `io.github.stlin256.dshpocket`，可以修改，但须同步 AGC 配置。服务端使用同项目的 **项目级服务账号 JSON**，不是客户端 API key 或 OAuth client secret。

服务账号 JSON 需要 `project_id`、`key_id`、`sub_account` 和 RSA PEM `private_key`。将文件保存在仓库外，仅供服务进程读取；`.env` 的 `HUAWEI_SERVICE_ACCOUNT` 指向该文件。服务端使用 PS256 JWT 和 Huawei v3 messages API，模型参照克隆项目中已存在的 HarmonyOS 接入，仍需在自己的 Huawei 项目中实际验证。

默认 `HUAWEI_CATEGORY=MARKETING`、`HUAWEI_TEST_MESSAGE=true`。`WORK` 等类别需要 Huawei 相应分类权益。正式投递前按自己的项目权益和配额调整类别，并关闭测试模式。Huawei 接口接受消息不等于设备已展示消息。

应用中点击“通知”→“开启通知”，同意系统通知权限。APP 取得 token 后以当前认证会话注册。关闭通知先撤销服务端设备注册，再删除系统 token；退出撤销当前会话的全部设备注册。重新安装、系统 token 更新或注册失败后，重新开启通知以更新 token。当前没有 token 自动刷新监听。

队列最多每次投递 20 条，指数退避、最多 8 次尝试、一小时过期；投递前重查设备是否被撤销。事件键去重保留七天。锁屏只有通用文案和会话标识，不发送对话、工具参数、文件路径或项目名。

## Harness 插件

将 `plugins/pocket-notify/` 放到 Harness 可解析的位置，在自己的 Cordis 配置中追加插件（路径是相对该配置的路径，不要直接照抄实际部署路径）：

```yaml
- name: ./plugins/pocket-notify/index.mjs
  config:
    endpoint: https://dsh.example.com/pocket/api/events
```

Harness 的服务环境中设置 `POCKET_EVENT_SECRET`，与网关 `EVENT_SECRET` 相同；也可以用 `POCKET_EVENT_ENDPOINT` 代替 YAML 中的 endpoint。请按所使用 Harness 版本的插件加载方式安装；本项目没有自动修改用户的 Harness 配置。

插件监听真实的全局 `session/event`：`turn/end` 的 completed/error、`approval/asked`。取消事件不作为完成通知，历史继承事件被过滤。只提交事件键、会话 ID 和事件代码，网络失败在插件内存中有界重试；网关接受后写 SQLite，支持重启续发。**插件向网关交接前的内存队列不耐进程重启**；没有宣称全链路严格一次投递。当前不发送普通提问提醒。

## DevEco Studio 编译

工程沿用参考项目的 SDK 26 / 最低 API 23 配置及 Hvigor 6 模型。需安装包含该 SDK 的 DevEco Studio；如果测试机 SDK 不同，请在 IDE 内选择实际已安装且支持所用 API 的版本，并记录调整，不要将签名配置提交。

1. 打开 `harmony/`，复制 `build-profile.example.json5` 为 `build-profile.json5`。
2. 在 IDE 里配置 app signing，使 bundle/证书/设备/profile 匹配 AGC。签名必须包含 `ohos.permission.ACCESS_FIDO2_ONLINEAUTH`，并具备 Push Kit 能力。
3. 同步 ohpm 依赖，Build HAP；可选使用 `scripts/build-harmony.ps1 -DevEcoHome <本机DevEco目录>`，脚本会创建忽略的本机 profile 并调用 ohpm/Hvigor。
4. 产物预期为 `harmony/entry/build/default/outputs/default/entry-default-signed.hap`。用 DevEco 或 HDC 安装并启动 EntryAbility。
5. 首次启动填写 **网关 HTTPS 源地址**，不是本机 Harness 端口。Passkey RP ID 是该域名，域名更换后已有 Passkey 无法继续用于新域名。

应用使用 ArkWeb 系统 Passkey，不使用 JS 模拟成功或绕过服务端校验。当前环境没有 SDK，以上为工程交接路径，需由接手者实际执行编译；编译错误和运行结果请按 VALIDATION.md 记录。
