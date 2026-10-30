# 2026-10-30：主题与设置逐项研究

本报告覆盖[本轮需求登记](../requirements/2026-10-30-native-polish.md)的THEME-01～05、SETTINGS-01～09、CONNECT-06。只读核对当前未提交源码、锁定的官方DSH与本机ArkUI SDK；没有修改App或网关实现，没有运行GUI，也没有读取凭据。本文提出的设计和指标是后续spec及验收目标，**研究完成不等于修复完成**。

DSH基线保持`f3803c96974ad4a94195fb97e5c637e9c2a3afe3`，不因新HEAD自动漂移。此前[上游视觉研究](upstream-settings-visual.md)的官方颜色、菜单、设置布局、Host合同继续有效。当前App仍为0.2.3；WithTheme包装、关于内嵌第三TAB、通知Bridge补丁都在未提交工作树，未提供本轮实机验收证据。

下文App路径省略前缀`harmony/entry/src/main/ets/`；SDK路径以`SDK_ETS`表示本机DevEco 26.0.0的`openharmony/ets`目录，避免将机器专有路径写成仓库依赖。所有行号是研究时的工作树位置，实施后需更新证据。

## 1. 已核实根因摘要

1. 之前仅显式切换了部分文本/背景和系统栏，ArkUI默认控件仍跟系统主题；当前新增`WithTheme`只有范围性修复。Select按钮色不等于菜单项色，资源主题与弹层还需覆盖和实测。
2. `Index.applyNativeTheme()`仅在`uiMode==='native' && !authSurface`时生效。在兼容模式里打开同一个原生设置，选择亮/暗只写偏好，不更新显示；这是“设置无反应”的确定代码路径。登录页也受此门控。
3. Settings每次挂载都将`host`初始化为空，再发请求；**没有先读取已经存在的client.hostSettings成功镜像**。所以热打开也等网络才出General选项。Host镜像本身已有最后成功值，但UI未利用。
4. 旧通知行向Bridge发送`notifyCompleted`等未知命令；Bridge实际只接受一个`notificationLevels`对象。新补丁已改为对象写入并回读，但远端与本地两阶段失败仍会分歧，尚不能验收为完成。
5. Push关闭先撤销服务器，后删Token，最后存false；中途失败不会回读状态。可能服务器已撤销、UI却继续显示开启。另外当前`allForSession:true`撤销同owner全部设备，与“此设备”开关的语义不符。
6. 关于之前切`settingsPage='about'`脱离三TAB；未提交补丁已使用`tab='about'`与`AboutSettings({embedded:true})`，需验收共同header、TAB、返回与滚动。
7. 兼容模式注入脚本仍匹配旧`.nav-divider`和`svg.lucide-settings`，而当前官方DSH是CSS module+sprite glyph。匹配失败直接return，不能据原生入口可打开就断言兼容入口正常。

## 2. SDK与官方事实

### 2.1 ArkUI主题不是给背景赋值

- `SDK_ETS/component/with_theme.d.ts:29–63`：WithTheme为**作用域内组件**定义默认theme和colorMode，默认SYSTEM。API12起可用。它是逻辑组件，不支持通用属性/事件（78–88），不能把backgroundColor等修饰写在WithTheme上。
- `SDK_ETS/api/@ohos.arkui.theme.d.ts:654–682`：CustomTheme有colors和darkColors。未提供darkColors时，直接自定义颜色可能在暗色仍沿用亮色，除非用dark资源目录。不能为系统主题只填一套DSH颜色。
- 同文件`707–728`：ThemeControl.setDefaultTheme在Ability调用影响整个Ability，在Page调用影响该页及后续页。它设置主题token，不是把所有硬编码颜色自动转换。
- `SDK_ETS/component/common.d.ts:24567–24586`：自定义组件可在onWillApplyTheme读取当前Theme并更新状态；需避免将Theme颜色缓存后永不更新。
- `SDK_ETS/component/select.d.ts:361–405,436–570,771–831`把按钮fontColor、选中option颜色、普通option颜色、menuBackgroundColor/Blur分开定义。只改`.fontColor()`不能证明下拉选项已跟随。
- Toggle的isOn支持双向绑定（`component/toggle.d.ts:267–285`）；onChange只是事件。设置持久化失败/早退时必须把受控值回到权威快照，不能只期待内部Switch自动回滚。
- `SDK_ETS/api/@ohos.data.preferences.d.ts:779–968`：put先改Preferences内存，flush/flushSync负责持久化。若flush失败，直接getSync可能读到已经改变但未落盘的内存值，不能把它当成“已持久化”的独立证明。

华为官方补充资料（仅引用相关结论）：

- [UIAbilityContext.setColorMode](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/js-apis-inner-application-uiabilitycontext)：Ability颜色覆盖应用/系统；须页面加载后调用，会创建新的资源管理器对象。若采用它，不能继续把effective config当作原始系统模式，且必须更新缓存ResourceManager。
- [WithTheme自定义DialogV2示例](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ohos-arkui-advanced-dialogv2)：示例将WithTheme放在弹窗builder内部。对本App新建的独立预览/弹窗，也应显式传主题，不能假设主树所有范围自动延伸。
- [openBindSheet资源色更新FAQ](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-arkui-1105)：ComponentContent内容需自行更新；这不表示当前普通bindSheet必定有同样缺陷，但说明不能笼统假定所有弹层自动跟新主题。
- [沉浸光感开启方式](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/arkts-immersive-light-sense-enable)：API26支持的Select/Toggle/弹窗可能默认启用系统材质，组件级可关闭；App减少透明应实际覆盖这些面，而不仅隐藏的Navigation标题。

### 2.2 与DSH保持同一含义

官方颜色/尺寸/动画见`upstream-settings-visual.md`。Host的ui-chat、ui-theme、locale偏好从`settings/describe`读取，以`settings/mutate {ns,ops,expectedRevision}`写；namespace内串行，失败刷新权威值。源文件：`ui-settings/src/client/config-form.ts:129–155`、`settings-mirror.ts:138–194`。原版General数据是功能插件贡献，不等同于本地通知/认证配置。

本轮不因精简移动UI删除既有spec的PREF04：官方字体、语言、主题等未移植项仍须保留“待实施”记录。已经实现的四档/折叠/回复/忙时发送选项须先做到稳定可用。

## 3. 统一主题设计

### 3.1 状态与所有权

建议明确以下状态，不再让`nativeDark`同时代表“网站刚报告的颜色”和“用户App选择”：

```text
AppAppearance:
  savedPreference = light | dark | system
  desiredPreference, writeState = idle | persisting | failed
  rawSystemDark
  resolvedAppDark = desired/saved固定值，或rawSystemDark
  revision
WebAppearance:
  hostPreference / observedWebDark（若页面已就绪）
  scope = trusted Host origin + login identity
```

**设计选择必须落入主spec**：App页、设置、原生聊天、原生预览始终采用AppAppearance；兼容网页保留Host ui-theme的原始含义。若产品要求App主题也覆盖兼容网页，则通过可信页面的官方theme服务做有明确所有权的临时视图覆盖，或显式写Host偏好并提示其跨客户端影响，不能仅修改`body`属性造成官方store下一帧回写。推荐前者：设备主题影响App shell；Host主题属于General的独立Host字段，两者不能用同名AppStorage冒充同步。现有用户最直接的“兼容模式设置改暗色无反应”必须先保证原生设置立刻受AppAppearance控制；网页主题差异要由spec明确，而非随最后一次Web回调随机改变shell。

状态转移：初始化先读已持久偏好→解析系统模式→首次绘制；选择模式→持久化→发布统一revision→root WithTheme/显式DSH palette/系统栏一起更新；持久化失败回到lastCommitted并短提示。系统变化只在system偏好下切resolved；关闭设置不清主题；切native/compat/auth不撤销App偏好。Web observation只更新WebAppearance，不覆写已显式选择的App shell模式。

实现边界：Root WithTheme包住所有App原生分支；每个独立builder/ComponentContent/新窗口接收同一theme snapshot；DSH自绘组件统一semantic palette；系统控件由WithTheme及CustomTheme双色token覆盖。若必须使用Ability.setColorMode处理系统弹层，建立单独rawSystemMode来源，设置NOT_SET后再跟随系统，避免配置回调反馈环；在spec前不要贸然把应用context颜色永久写死。

### 3.2 必须检查的主题表面

| 表面 | 普通、禁用、选择、错误等覆盖 |
| --- | --- |
| 设置/列表/聊天 | primary/secondary/tertiary、链接、图标、divider、卡面、选中/按压、禁用透明度 |
| TextInput/TextArea | 正文字、placeholder、cursor/selection、focus、底色与边框，含重命名/搜索/队列/问答/登录 |
| Select | 主按钮、chevron、未选/已选option文字及背景、menu材质；切主题时已打开菜单的行为 |
| Toggle | on/off轨道、thumb、disabled；切主题不改变业务isOn |
| popup/sheet/dialog/toast | 背景、内容、close/cancel/error、遮罩和读屏；独立builder明确主题 |
| 图片/文件/长文预览 | 阅读背景、关闭/复制/重试、代码/表格/link/error，系统预览页使用平台相应模式 |
| 系统栏与启动 | 状态栏及手势区背景/图标、冷启动首帧、返回App后恢复 |

当前具体漏色高风险位置：`NativeSessionTools.ets:119,128,144–154`的默认输入/按钮；`NativeInteraction.ets:144`问答TextArea；`NativeWorkspacePicker.ets:63,90`输入；`NativeImageView.ets:43,59`预览/错误按钮；`NativeTextContent.ets:31–50`长文操作；`NativeSettings.ets:92–95`仅设置Select按钮字体、未设置下拉菜单项。不能只扫出现`.fontColor`的代码判定通过，必须覆盖当前值为空/disabled/error等状态。

## 4. 设置镜像与首屏（CONNECT-06）

### 4.1 根因证据

`NativeSettings.ets:46`每次new一个空Host描述；`aboutToAppear:67–70`仅initialize+refreshHost，未同步调用hostChanged。虽然`NativeHarnessClient.ets:27–29`的hostSettings实例跟随已连接client保留，`NativeHostSettings.ets:28–40`也有loaded/最后成功description，UI只等网络完成才赋值。`NativeWorkspace.reload:160`与设置打开还可能同时发describe，`NativeHostSettings.refresh`只用read序号丢旧答案，无in-flight合并。

此外`hostBusy`同时代表refresh和write；一有后台刷新，所有Host选项都disabled且saveHost直接return（`NativeSettings:75,81,95`）。从用户视角点击暂时无反应，并非每次是Remote拒绝。

### 4.2 修复模型

镜像生命周期绑定`origin + authenticated identity/generation`，切身份清空，切设置不清空。状态：

```text
empty → loading → ready(snapshot)
ready → refreshing(snapshot仍可读) → ready(new snapshot)
refreshing失败 → stale(snapshot,error)
首次失败 → failed(no snapshot,retry)
logout/origin变化 → disposed（旧答案不可发布）
```

设置挂载**同步复制最后成功snapshot并渲染**；同时发ensureFresh。无snapshot时先有header/TAB与稳定行骨架，不用“服务不支持”代替loading。失败后有旧值保留旧值+短重试提示。每身份最多一个read在途+一个rerun位；中途收到刷新请求不多开HTTP，不丢失失效通知。成功写合并namespace不可原地改同一对象，发布新description以保证ArkUI观察；失效老read。Host推送`settings/document-updated`或连接reset驱动刷新。

写状态按namespace/字段独立：排队时取最新revision；后台refresh不全局锁所有控件。若read和用户写同时出现，写答案优先，旧read不覆盖。无写权限只禁用Host字段，不禁用TAB/关于/关闭/App本地设置。用户关闭设置取消的是view订阅，不取消已经发送的明确设置修改；旧generation永远不能回写另一身份UI。

性能验收目标（不是实测成绩）：

- 已有镜像时，从设置入口click到General第一帧可用值，P95≤100ms；对原生树只允许一次同步snapshot复制，不等HTTP。
- 20次热打开中，无“先空白再出四个选项”帧；后台刷新每次最多1在途，短时间重复打开/重连至多合并1次rerun。
- 冷打开header/TAB首帧≤100ms；首次值时间分别记录认证检查、describe RTT、JSON decode、镜像发布、ArkUI下一帧；LAN目标≤1s、远程目标≤2s（需在实际链路标明RTT和样本数，不能用mock声称达标）。
- 断网重开保留最后成功值，无法确认新的修改时显示短错误；不默默写默认值覆盖Host。

## 5. 本地设置事务、通知与Push

### 5.1 当前命令对照（必须逐项测试）

| UI项 | 实际写入链 | 当前判断 |
| --- | --- | --- |
| 外观 | `themeMode`→PocketBridge69–74→Preferences.flush→nativeThemeMode→Index179–183 | 原生路径可应用，兼容/auth门控漏应用；WithTheme新补丁未验 |
| 减少动态/透明 | Bridge97–100→NativeExperience.setPreference22–27 | 真实落盘；默认材质/部分无条件transition未覆盖 |
| 显示任务名称 | Bridge102–105→WidgetStore.setDetails70–78→清旧快照/发布卡片 | 真实链；存储/卡片发布失败需区分，禁止假成功 |
| 通知三等级 | 新UI175→notificationLevels107–115→可选POST device | 旧单项命令确定不匹配；新修补尚无两端事务验收 |
| 开启Push | 权限/getToken→POST device→pushEnabled(true) | 部分成功/取消/超时无对账，无per-device查询答案 |
| 关闭Push | DELETE allForSession→deleteToken→pushEnabled(false) | 撤销范围过大；中途失败UI与实际不同 |
| 无Push后台监控 | Bridge117–125→nativeBackgroundMonitor→NativeWorkspace.activityChanged | 真实开关；只有活跃任务的dataTransfer监控，不应承诺杀进程仍在线 |
| 立即同步 | action state检查→overview→widgetSnapshot | 全局busy阻塞其他App项；可单独busy并回读卡片同步时间 |
| 服务与登录/退出 | connection二级/Index.disconnectConnection | 不应等待其他同步才可进入二级/返回；失败保留改地址/退出本地路径 |
| 界面模式 | onModes回调仍声明，Index.modeSheet存在 | NativeSettings当前没有调用onModes的行，入口不可达；需恢复原生/兼容选择 |

### 5.2 通用本地事务

每个设置至少保存`lastCommitted`、`desired`、`pending(opId,generation)`、`error`；控件读desired或已确认快照，不能有自己另存一份状态。点击后立即提供忙碌/按压反馈，按设置键串行或合并最后意图，不能用全页`busy`让无关点击无反应。写入成功必须来自真正flush完成；失败回滚Preferences内存和UI至lastCommitted，再回读确认。不能在flush失败后用同一个缓存对象getSync读到候选值就当成功。

受控Switch可拆为@Link/受控view model子组件，onChange写desired；忽略已相同的confirmed值，内部程序性回读不要再次发网络。用户取消/关闭只关闭UI，不伪造旧值；正在发出的可幂等配置写可以后台结算，generation隔离其结果。错误提示短如“保存失败”，详情写脱敏诊断，绝不把token/地址/完整异常上屏。

### 5.3 三等级与分布式一致性

App和网关均用同一allowlist `{approval,failed,completed}`。当前插件入队按此对象过滤（`gateway/src/app.mjs:234–241`），App本地通知也检查同分类（PocketBridge136–144），这两部分合同已经有，但尚缺可靠变更/回读。

新UI补丁先本地flush后POST device，POST失败再写回旧本地levels（`NativeSettings:175–203`）。若远端实际已提交但答案丢失，回滚只影响本地，服务器可能仍是新值；因此“回滚本地”不是分布式事务完成。

修复设计：增加**按当前设备id查询的脱敏状态**（不返回token）以及变更receipt，如`{id,registered,notifications,revision}`；POST/DELETE仍用已授权device owner范围，并返回当前receipt。此为本项目API扩展，须与实现spec明确，非DSH官方合同。

```text
confirmed(snapshot)
  → staged(desired,opId)
  → obtaining-permission/token（仅首次开启）
  → registering/updating/revoking
  → server-confirmed(receipt)
  → local-persisting
  → confirmed(new snapshot)
失败明确未受理 → confirmed(old snapshot)+短错误
超时/网络答案不明 → reconciling(GET当前device receipt)
本地flush失败 → persistence-pending；不逆向篡改已提交server状态
```

Push未启用时levels的authority是本地durable snapshot，无需getToken/网络；启用时delivery authority是server receipt，持久pending意图后发送幂等配置，成功才清pending。重复配置必须复用deviceId，不能每次换token/新设备绑定；答案不明先查而不是宣称没改。用户关闭某等级应处理已入队同等级job：spec明确取消待发job/发送前再检查当前levels，避免关闭后仍收到旧队列造成误判；这不影响已经由系统显示的通知。

### 5.4 Push启用与停用

当前PushKitAdapter.getToken同时requestEnableNotification（personal7–9）。应区分用户拒绝、取消、服务未配置、token失败、server注册失败、local flush失败。只在server确认当前device注册后显示“开启”；操作过程中显式pending，不显示成功。

关闭只发送`DELETE {id}`，不是`allForSession`。server撤销成功即停止服务端路由并记录本地disabled，即使后续token清理失败仍显示disabled+cleanupPending，后台重试清token；token清理成功不能代替server撤销确认。network未知时对账receipt。退出登录可继续按既有session撤销规则清理，但不应把它复用成此设备的普通开关。

App不能仅从Preferences.pushEnabled得知系统通知权限和server绑定仍有效。回前台/打开通知设置时读本地配置、系统授权、server当前设备receipt，形成effective状态；server无凭据/设备被撤销/系统权限关闭时显示真实状态或可恢复操作。

### 5.5 无Push和通知打开

保留已存在无Push构建能力，不新增商店版本。无Push的“后台任务监控”只在已知活跃任务期间使用平台允许的dataTransfer模式，前台恢复/用户关闭/任务结束必须停止；系统拒绝后台任务时回滚并反馈。当前代码没有资格保证被用户结束进程后继续监控，这个能力边界不能藏在无反应的开关中。

通知路由当前有基础：`BackgroundMonitor.ets:11–17`的Want携sessionId；`EntryAbility.ets:68–82`解析新Want；Index保留requestedSession。这只能算实现基础。验收需冷启动/热启动/已在其他会话/设置打开/需重新认证：先保存目标路由，经认证后只开目标一次，权限弹窗取消不清目标，目标归档/不存在有短反馈且可返回。路由应同时绑定配置连接身份，不能拿A服务器通知的sessionId跳到B服务器同名会话。

## 6. 三TAB、二级和入口设计

设置树应显式建模：`Settings(tab=general|app|about, detail?, foregroundOverlay?)`。三个TAB都是同一层级，始终保留header和tabstrip；About是第三TAB内容，不设置独立about page。连接/模式等二级可以显示详细header，但Back回原tab；系统Back先最上层Select/dialog/preview，再detail，再关闭settings。关闭恢复调用入口焦点；底层conversation/web保持挂载，不能点击穿透。

当前`Index.ets:281–287,419–420`Stack与二级Back基本正确；未提交About嵌入补丁方向正确，但须测长页面滚动及小屏，不能复用About里的第二层header。tab切换保留各tab滚动位置，已访问tab不重复fetch；关于不做网络依赖。窗口变化只更新布局不改nav状态。

兼容入口：`presentation.js:16–21`旧CloudCLI选择器与DSH官方DOM不一致。锁定版本可依赖的**实际源码事实**如下：

- `ui-sidebar/src/client/SidebarRoot.tsx:404–411`在底部先渲染`sidebar.footer.action`，再`sidebar.settings`；`contract/slots.ts:51–56,141–145`声明前者是root作用域list，每项接收`wide:boolean`，供展开行/收起56宽rail适配。这是比CSS module类名可靠的正式扩展合同。推荐通过可信App本地client模块登记一个footer action，其点击仅调用openSettings Bridge；需对当前模块加载器的登记/卸载做夹具验证，不能假设任意页面暴露全局ctx。
- 官方fallback设置按钮在`SettingsRoot.tsx:227–236`带`aria-haspopup="dialog"`及本地化aria-label，子内容`chrome.tsx:25`为`IconSettingsOutlineMedium`；`ui-primitives/src/icons/index.tsx:17–23`实际生成`svg[data-icon="dsw-icon-settings-outline-medium"]`和`use[href="#dsw-icon-settings-outline-medium"]`。它没有`lucide-settings`类。
- 但该fallback**不是所有部署必有**：`ui-settings-account/src/client/index.ts:333–334`可替换`settings.launcher`；`AccountMenu.tsx:64–83`底部入口会成为头像/ellipsis菜单，齿轮只在打开的菜单项里。因此不能把扫描gear svg作为唯一注入锚点，也不能搜索到菜单里的gear后把App入口插进该菜单任意父层。
- SidebarRoot最外层是普通div和CSS module类（266–272），并无稳定的`aside`或`data-sidebar`标记。本地注入若不能使用slot合同，应先在本地受控模块建立一个唯一锚点；不得依赖猜测的parentElement层数或哈希类名。

不篡改服务器设置页，不替代官方Host按钮。一次登记一个App齿轮，重复hydration/开关侧栏不重复，卸载时移除自己登记；点击只发openSettings。只信当前配置origin的top/frame，旧Bridge`trusted`校验继续保留。

## 7. 逐ID设计、取消与验收

| ID | 根因/当前证据 | 修复设计与错误/取消 | 必须验收 |
| --- | --- | --- | --- |
| THEME-01 | Index原来缺系统控件主题范围；当前425仅新增WithTheme；NativeSettings Select只设button颜色 | 同一AppAppearance驱动scope+DSH palette+独立弹层；取消主题选择不写；持久失败恢复 | light/dark/system×列表/聊天/所有设置/菜单/输入/预览；打开Select时切系统主题；不能有不可读字 |
| THEME-02 | 硬编码背景配默认控件，局部漏色；兼容/auth模式被179–183门控 | root scope与双色CustomTheme，default/placeholder/selected/disabled覆盖；不凭背景变化验收 | 浅→深→浅各10次；输入有/无字、控件on/off/disabled/error；统计漏色0 |
| THEME-03 | EntryAbility43 fullscreen(false)，无用户全屏开关 | 保留状态栏，逻辑不再从设置改window flags；布局读取safe area | 状态栏始终可见；顶部标题不被遮挡；全设置查无全屏项 |
| THEME-04 | WindowAppearance按base色画栏，About/connection使用另一底色；固定padding可能叠加safe area | 页面surface统一或向system bars报告当前surface，系统避让只计算一次；键盘resize | 竖/横/键盘开关，底部无异色带、无额外固定空白、最后一项可触达 |
| THEME-05 | NativeExperience正确读系统动画；部分transition无条件；减少透明主要作用隐藏标题，metadata default可能启用控件材质 | 统一Experience snapshot控制所有页面/menu/preview/list；API26材质逐表面empty fallback；旧API不取新对象 | App或系统任一reduceMotion即无转场；reduceTransparency后Select/Toggle/弹层不剩默认透明材质；token刷新不重播 |
| CONNECT-06 | NativeSettings首次空host、未先hostChanged；镜像refresh无合并 | 同步last-good→后台ensure；revision写队列；错误保留好值，身份换清缓存 | 热开P95≤100ms且0空白帧；offline可读旧值；请求合并/无默认写回 |
| SETTINGS-01 | Stack原生入口已有；Web注入仍旧Lucide选择器 | 可信origin单一openSettings路由+稳定DSH锚点；入口不受Host读忙碌阻塞 | 两模式各20次打开/关闭，0无反应、0重复齿轮、0穿透；保留草稿/滚动 |
| SETTINGS-02 | 旧about page分支；新embedded补丁未验 | 共用header/tabstrip，about只做内容；独立滚动，首次无需网络 | 通用→关于→应用来回20次，header位置不跳、第三tab保持选中 |
| SETTINGS-03 | Index二级Back已存在；局部popover等前景层还需统一 | Nav state统一派生，系统Back从前景消费；已受理修改不因返回隐式撤销 | Select/连接/模式/预览逐层返回；旋转后仍同层，0错误退出 |
| SETTINGS-04 | 全局busy早退，旧未知Bridge命令、缺回读/事务；模式入口丢失 | 命令registry类型化，独立pending，受控desired/committed；flush/Remote结果后回读；失败短反馈 | 每个可见项一正一反、一错误、一取消；重启回读一致；不存在空onClick/静默return |
| SETTINGS-05 | 三分类合同两端有；新补丁仍先本地后远端且不明结果回滚 | per-device receipt+幂等配置+对账；发送前复查levels，取消待发同级job | 8种level组合、前台本地/后台Push；关闭一级仅对应一级停止；关闭Push仅此设备 |
| SETTINGS-06 | personal/store适配已存在，后台start/stop真实但无失败回显 | 按supported显示Push/monitor；无Push不承诺杀进程保活；通知路由绑定连接身份 | Push冷/热/认证后打开；无Push开启拒绝回滚、关闭停任务、活跃结束停任务；不新开发商店发布 |
| SETTINGS-07 | Host revision队列已有但UI不利用缓存，刷新全局锁；字段尚未全移植 | immutable镜像、串行同ns、refresh合并、冲突恢复与权限；保留原spec未完字段目录 | 冲突/只读/文档变更/重连下权威值；四模式×时机×回复实际影响同一聊天，不只选中UI |
| SETTINGS-08 | About本地logo/avatar、BuildInfo字段齐；embedded新补丁未验 | 第三tab展示完整内容，外链系统打开/失败短反馈，不因头像网络慢等待 | 离线头像/logo均可见；版本与app.json一致；作者/仓库/Issue目标正确；版权许可有来源 |
| SETTINGS-09 | 现有平整tab方向正确，Unicode箭头残留、默认弹层/文字密度不统一 | 官方glyph/token/compact行复用，16vp内容边距；只保留必要标签与状态 | 320/360vp/大字体不溢出；重要文字不截断；无JSON/大段实现说明 |

## 8. 可执行验证清单与指标

### 自动化（后续实现时再增加/运行）

1. Theme resolver表驱动：App三个偏好×OS两个模式×native/compat/auth/setting/preview，保证App native surfaces结果一致；Web observation不能覆盖显式App preference；旧API不调用26对象。
2. Bridge registry从UI全部command到执行器全覆盖，未知命令测试；每项布尔true/false均持久化，flush reject不产生已保存状态；notificationLevels禁止错误key/非boolean。
3. Host mirror：缓存挂载立即可见、并行refresh合并、write答案先于旧read、冲突恢复、namespace串行互不堵塞、dispose后不能发布、换身份不泄漏。
4. 通知状态机：权限拒绝、token失败、POST成功/失败/答案不明、本地flush失败、DELETE成功但token清理失败；单设备撤销不影响其他设备；8组合，队列前二次过滤。
5. 导航：3TAB同一shell，detail返回原tab，overlay优先，退出不清draft/cache；兼容注入对官方DSH夹具重复运行仅一个App齿轮，并校验可信origin。

### 真机CLI（不可用mock代替）

- 用HDC布局/脱敏截图核对主题矩阵与点击状态；保留截图在本机TEMP，真实服务地址和对话不提交。
- 记录10次以上暖/冷General首内容帧及请求数；记录主题选择→所有可见控件最后一次换色时间。目标热切主题P95≤200ms，无中间黑字暗底帧；启动无明暗闪烁。这里200ms是预算，不是已经测得的成绩。
- 单次普通本地开关先给按压/忙碌反馈≤100ms；持久化成功通常≤300ms，超过500ms保留该行loading但其他TAB/关闭仍可用。网络设置确认预算为已测RTT+解码/布局；2s仍未确认显示简短同步状态，不长时间静默。
- 全部Switch正反操作后关闭/重开设置，再结束进程重启；UI、Preferences、远端receipt三者比对。失败注入和用户拒绝后不能保留假开启状态。
- 保留系统状态栏，键盘开关/旋转/大字体后系统Back走正确层，缓存会话无需重载；App后台停止装饰动画。

## 9. 实施前顺序与未决项

先完成本轮总spec逐ID映射，再实施：①主题所有权与Theme scope/token→②设置热镜像/独立busy→③Bridge单写者与通知device receipt→④3TAB/二级/兼容注入→⑤全矩阵自动化及真机。当前未验补丁可保留作候选，但不能跳过上述设计评审。

需要主spec明确的唯一产品歧义：App外观与Host ui-theme是否为独立设置。推荐清楚保留归属，并至少使原生设置无论从何处打开都立即响应App外观；不要让兼容Web回调随机决定原生页主题。若选择统一两者，须说明写Host会影响同Host其他客户端，并正确处理离线冲突，不能只做DOM改色。

SDK声明能证明API范围与参数，不能证明该设备上已打开popup/系统dialog会自动重绘；此项必须列为设备测试。当前54个Kit mock测试和release编译无法替代这些视觉/事务/性能验收。
