# HarmonyOS 7 原生适配与桌面卡片

产品级动效策略以及 API 23–26 降级矩阵见
[DSH Harmony 视觉与动效设计](design/2026-10-31-dsh-harmony-visual-motion.md)与
[HarmonyOS 7 动效策略调研](research/2026-10-31-harmonyos7-motion-strategy.md)。

## 已实现的范围

工程以 API 26.0.0 为 target，保留 API 23 最低兼容配置。新增能力均使用原生 ArkUI / Form Kit；Web 内容继续运行原版 Harness，不对聊天页面全屏叠模糊或替换其交互。

| 场景 | 实现 | 回退或边界 |
| --- | --- | --- |
| 原生标题栏 | Navigation 承载标题和操作；系统 ImmersiveMaterial | API 23–25 保留不透明栏 |
| 玻璃和光感 | 标题区按钮使用系统薄材质、交互光感及形变 | 系统材质被关闭、减少透明、省电及后台时使用清晰表面；效果受设备策略控制 |
| 减少动效 | 订阅系统减少动态效果，结合应用开关关闭交互形变和光感 | 监听在 Ability 销毁时注销；接口读取失败时保守减少效果 |
| 主题 | 原版 Harness 明暗主题镜像到原生栏和系统栏 | 手动主题优先于系统颜色变化 |
| 大字体 | 标题区域随字体缩放增高，标题单行省略，按钮有读屏标签 | 极大字号和最窄分屏仍需设备验收 |
| 键盘与窗口 | Web 输入区域随软键盘调整；保留系统安全区，无方向锁定 | 折叠、旋转与分屏由响应式 Web UI 和 Navigation 布局适配 |
| 渲染异常 | 原生展示恢复提示，用户可刷新重载 Web | 不自动重复提交任务或表单 |
| 前后台 | 回前台刷新电源策略及匿名快照；后台取消请求与同步计时器 | 不申请后台常驻权限，不保证应用退出后的卡片实时更新 |

沉浸材质由系统实现。`module.json5` 使用 `ohos.arkui.UIMaterial.state=default`，只对原生标题区显式设置材质。普通按钮通过 AttributeModifier 在版本保护之后调用 API 26 的 systemMaterial；减少透明时显式使用 Material.empty。标题栏采用标准布局，给 Web 留出完整空间，避免悬浮栏遮挡聊天输入和网页按钮。

这里没有调用部分 Beta 文档出现、但所核对公开接口声明中缺失的设备材质探针；使用 API 版本、系统能力及材质配置状态保护。最终是否渲染光效、渲染强度和低算力设备的退化效果由系统决定。需要接手者使用实际 SDK 26 补丁编译，并在支持设备上确认。

## 卡片功能

长按桌面 DSH Harmony 图标，进入服务卡片选择：

- **工作空间入口，2×2**：不显示地址和内容，一键打开原版 Harness；未连接时进入连接引导。
- **任务状态概览，2×4**：默认只展示入口。用户在应用设置 → 桌面卡片中开启匿名数量后，可展示运行中、待审批、近期完成与近期失败四项状态。提供“打开工作空间”和“同步状态”两个入口。

卡片是静态 ArkTS 服务卡片，交互使用 FormLink，生命周期使用 FormExtensionAbility。卡片 ID 注册、临时卡片转正式、移除和多实例更新均已处理。浅色、深色资源跟随桌面系统主题，而不是强制跟随应用内单独选择的主题。

“同步状态”会将应用带到前台并进入卡片设置，不在后台偷偷启动网络连接。应用还会在页面加载、回到前台及前台每 60 秒同步一次。请求使用现有同源登录 cookie；认证失败会清理卡片缓存。没有将 cookie、Passkey、上游启动令牌或推送 token 提供给 FormExtensionAbility。

## 数量的含义与新鲜度

状态来自 Harness 插件新收到的事件，**按会话的最近状态计数**，不是累计任务执行次数。开始/结束与审批请求/决定共同维护投影；同一会话多个审批全部处理后才离开等待状态。完成/失败展示最近 24 小时内仍保持该最近状态的会话。运行态超过六小时没有新事件时标为待确认，不伪装为实时运行。插件安装前的历史不回填。

每次交接的匿名快照都有本机同步时间，桌面始终称其为“快照”。超过 15 分钟的缓存会在**下次卡片更新**时隐藏数量并提示更新；系统周期回调按 30 分钟周期申请（updateDuration=1），实际调度由系统控制，所以不能保证恰好在第 15 分钟改变屏幕。桌面保留旧时间文案时也不代表服务器在线。

后台 Push 不直接修改这些数量：通知投递和任务概览是两条独立链路。因此本版本不宣称关闭应用后仍有实时桌面状态。

## 隐私与生命周期

默认关闭数量展示。只有用户明确开启时才缓存白名单中的数字及时间；没有对话、项目名称、会话 ID、服务器地址或账号信息。关闭数量后清除旧快照。退出或认证失效后清除快照及数量展示授权，所有已注册卡片更新为连接入口。

快照文件由 UI 进程单独写入，卡片实例文件由扩展进程单独写入。跨进程读取前移除 Preferences 的本地缓存，减少读取旧值的风险；UI 更新与退出清理串行执行，已退出桥接对象拒绝新的快照。

桌面只提供导航，没有任务执行、审批或取消的快捷按钮；这些操作进入应用后走原版 Harness 的现有权限和确认流程。

## 服务端升级

部署时应同时更新网关、通知插件和原生应用。数据库启动时自动增加 task_states 和 pending_actions 两张表，不删除现有登录和通知数据。旧插件仍可发通知，但没有单调事件序号时不会生成概览状态。

新版插件上报 turn/start、turn/end、approval/asked、approval/decided 的白名单状态。提交含会话序号，网关忽略迟到状态；插件重试保留同会话事件次序。只有完成、失败和待审批事件发 Push，其余只更新概览。审批全部解决或回合结束时撤销尚未投递的旧审批提醒，已经交给 Huawei 的消息无法撤回。

## 编译与真机验收

1. 使用包含 API 26.0.0 的实际 DevEco / SDK 打开 harmony，完成签名同步及构建；先修正具体编译诊断，再继续设备验收。此环境没有执行 Hvigor/ArkTS 构建。
2. 分别在 HarmonyOS 7 支持光感的设备、系统关闭材质的设备及最低兼容设备上启动；检查旧版本不会访问新材质接口。
3. 打开和关闭减少透明、系统减少动效、应用减少动效及省电模式；回到应用后检查材质回退。省电模式在启动、回前台及设置变更时重查，未声明订阅实时电源模式广播。
4. 检查浅深主题、字体缩放、软键盘、折叠屏展开/收起、横竖屏与分屏。确认网页没有被原生栏遮挡，系统栏按钮文字清晰可读。
5. 添加两种尺寸、多张同类卡片，测试预览、临时转正式、删除、应用升级及进程回收后恢复。
6. 未授权数量时桌面不显示统计。开启后触发实际运行、两个并行审批、完成和失败；同步并核对数量和时间。制造断网及过期场景，确认文案不声称实时状态。
7. 从卡片冷启动和热启动应用，核对对应入口。退出登录后检查所有卡片清理；确认通知权限与 Passkey 流程未被新入口绕过。
8. 关闭应用观察 CPU/网络与耗电，不应出现卡片常驻轮询。系统延迟卡片回调时旧快照必须仍带原时间，而不是被刷成当前时间。

## 参考资料

- [HarmonyOS 7 产品说明](https://consumer.huawei.com/cn/harmonyos-7/)
- [官方：开启沉浸光感](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/arkts-immersive-light-sense-enable)
- [系统材质参考](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-uimaterial)
- [OpenHarmony 官方系统材质声明与说明](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-arkui/arkts-apis-uimaterial.md)
- [OpenHarmony 官方 Navigation 接口声明](https://github.com/openharmony/interface_sdk-js/blob/master/api/@internal/component/ets/navigation.d.ts)
- [OpenHarmony 官方卡片配置](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/form/arkts-ui-widget-configuration.md)
- [OpenHarmony 官方静态卡片 FormLink](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-arkui/arkui-ts/ts-container-formlink.md)

公开 API 和平台文档会迭代，HarmonyOS 与 OpenHarmony 的设备策略也可能不同；真实 SDK 声明和设备行为是这次交接验收需要补齐的部分。
