# DeepSeek Harness：设置、浮层、主题与视觉交互研究

研究基线：官方仓库 `https://github.com/deepseek-ai/deepseek-harness.git`，锁定提交 `f3803c96974ad4a94195fb97e5c637e9c2a3afe3`。复用已克隆的官方源码，核实 origin 后通过 `git show` 读取 sparse checkout 之外的文件，没有修改上游工作树。下列行号都属于该提交，方便以 `https://github.com/deepseek-ai/deepseek-harness/blob/<revision>/<path>#L<line>` 核对。

本文区分三类事实：**官方行为**来自源码；**移动映射**是鸿蒙实现应采用的适配；**当前差异**描述本仓库未提交工作树，不能当作已完成的设备验收。会话动作的具体业务入口及工作区逻辑见同目录的工作区研究；本文负责共享浮层和设置视觉契约。

## 1. 官方设置入口与导航

| 规则 | 源码证据 |
| --- | --- |
| 设置入口属于左侧栏底部；展开时为齿轮+文字，收起为纯齿轮，图标分别为16和18。 | `packages/client/ui-settings-general/src/client/chrome.tsx:22–27`；`SettingsRoot.module.css:16–58` |
| 普通入口高42；收起齿轮按钮36×36；背景透明，hover才填交互背景。 | `SettingsRoot.module.css:16–58` |
| 设置是独立模态层；关闭按钮、遮罩点击、Escape都关闭；底层会话不应因此被替换或丢失。 | `SettingsRoot.tsx:52–109`；`ui-layout/src/client/stores.ts:17–20` |
| Shell状态只有`open`和`activeId`。打开保留当前请求分类；选择只修改分类；关闭同时清空activeId；定向打开指定分类。 | `shell-store.ts:16–24` |
| 分类来自slot注册，按order排序；注册项消失时渲染回退到第一项。分类不是一个写死的数组。 | `ui-settings-general/src/client/index.ts:145–159`；`SettingsRoot.tsx:58–60` |
| 当前分类初始获得焦点；焦点移动时把分类滚到可见范围。只有前景模态拥有Escape与Tab，关闭后恢复调用按钮焦点。 | `SettingsRoot.tsx:79–89`；`ui-primitives/src/useModalLayer.ts:46–95` |
| 设置入口整体受`settings/describe`访问权限约束；服务未授予此能力时不能伪造一个可编辑的Host设置界面。 | `ui-settings-general/src/client/index.ts:190–231` |

### 分类与内容目录

官方静态注册目录不是“每台服务器必定都显示”的保证；可用性还受已安装插件、Remote能力和账户功能约束。

| 分类 | order / 内容与交互 |
| --- | --- |
| account | -10；账户身份、余额和账户链接、登录尝试进度/取消、退出。`ui-settings-account/src/client/index.ts:341`；`AccountSection.tsx:93–185`。这是DeepSeek模型账户，和本App的服务登录/Pocket ID不是一个身份。 |
| general | 0；功能插件向`settings.general.item`贡献行。`ui-settings-general/src/client/index.ts:248–255`。 |
| models | 10；提供方列表、一次一个编辑卡片；首次无可用提供方时可展开设置卡。新增含catalog/custom两种模式；访问过的面板保持挂载以保留草稿；写入/端点探测期间禁用模式切换；删除先确认。`ui-settings-models/src/client/ModelsSection.tsx:1–21`；`index.ts:136–146`。 |
| plugins | 15；子tab也来自slot，只有一个tab直接显示内容；多tab首次访问才挂载，以后切换隐藏并保留草稿、搜索和展开状态。`ui-settings-plugins/src/client/index.ts:74–84`；`PluginsSettingsSection.tsx:32–51,98–112`。 |
| agent-presets | 20；预设目录、默认预设、组合的只读查看、帮助、可用时进入Creator；编码工具关闭时隐藏需要编码工具的预设。`ui-agent-preset/src/client/index.ts:272–290`；`AgentPresetSection.tsx:15–29`。 |

`archived-sessions`在Shell中有图标映射，但此提交中没有对应正式分类注册（只有测试构造此id）。不能因图标分支就推断官方一定有此设置页；归档恢复按工作区研究实现。

General行的注册顺序：权限(-20)、语言(0)、外观(10)、字体(11)、工作详情(12)、编码工具(15)、快捷键(16)、链接打开位置(17，可用内置浏览器时)、忙时Enter行为(20)、用量详情(30)、日志上传(90，条件能力)、当前Host版本(100)。证据分别在`ui-permission-presets/src/client/index.ts:169–175`、`locale/src/client/index.ts:622–629`、`ui-theme/src/client/index.ts:622–645`、`ui-chat/src/client/apply.ts:153–205`、`ui-settings-general/src/client/index.ts:83–101`、`ui-shortcuts/src/client/index.ts:43`、`ui-conversation/src/client/apply.ts:197–206`、`ui-settings-session-log/src/client/index.ts:37`。

## 2. 官方手机设置布局

桌面设置面板为800×800，视口上下至少24空隙，188宽分类栏，分类栏和内容各自滚动；切分类不因内容长短改变整个面板的尺寸。分类行高40、间隔4、14号字、12圆角。面板28圆角、次级层颜色、突出投影。证据：`SettingsRoot.module.css:84–118,124–185,243–250`。

**浏览器宽度≤767时已有官方移动布局**：

- 设置占满视口，面板外圆角为0；顶行标题和关闭，第二行为横向分类条，下方才是可滚动内容。
- 分类条两端16边距，12上/14下间距，分类最小108宽，整体可以横向滚动；选中项进入可见区域。
- 内容左右16、底24；顶部标题左16；分类和内容的overflow互不干扰。
- 外观浅色/深色/跟随系统三个选项始终等宽一行，单个选项12上下/6左右内边距。

证据：`SettingsRoot.module.css:252–325`；`ui-theme/src/client/AppearanceRow.module.css:61–69`。这是官方CSS事实。鸿蒙使用相同信息结构、尺寸语义，加入系统安全区；不可用桌面800宽缩放到手机，也不可把所有官方分类内容塞在一页大卡片中宣称已复刻。

## 3. Host偏好与Remote契约

### 3.1 事实来源和读写

官方已认证客户端把这些偏好保存在**Host的用户设置文档**，不是浏览器localStorage。`ui-settings/src/client/index.ts:36–53`明确由一个共享镜像读取，并订阅`settings/document-updated`以及`connection/reset`重新加载。

Remote namespace为`settings`：

```ts
describe(): {
  writable: boolean,
  hasDocument: boolean,
  namespaces: Array<{
    ns: string, schema: JsonValue, value: JsonValue,
    base?: JsonValue, user?: JsonValue, applies: unknown,
    secrets: Array<{ path: string[], set: boolean }>, revision: number
  }>
}
mutate(ns: string, ops: SettingsPathOpView[], expectedRevision?: number)
  : SettingsNamespaceView
```

来源：`packages/api/settings-controller/src/index.ts:48–59,97–105,141–158`。读答案已脱敏；不要读取真实密钥值，也不要把配置整个dump到UI。

在已有Typert HTTP envelope的`payload.args`中，`describe`为`{}`，`mutate`使用**直接命名参数**，不套`request`。生产Client将调用参数按`parameter.wire`生成对象，再调用Connection RPC（`api/gateway/src/client/index.ts:458,499–542`）；测试remote-mock里的位置参数数组不是实际HTTP格式。

```json
{
  "ns": "ui-chat",
  "ops": [{ "op": "set", "path": ["transcriptView"], "value": "standard" }],
  "expectedRevision": 7
}
```

7只是示意值，实际必须取该namespace最近一次读/写答案的revision。恢复默认用`{op:"unset",path:[field]}`，不要替换整个namespace。官方也提供`update(ns,patch,expectedRevision)`和`replace(ns,section,expectedRevision)`，但标量偏好使用path mutation足够。

写入必须按namespace串行，复制入队参数，用最新已知revision；最新一次写失败后重新describe，冲突`settings/conflict`与拒绝`settings/rejected`有明确区分，不能显示“已保存”后忽略失败。写成功把返回namespace合并回镜像，失效较早的在途read；后续刷新失败保留最后成功的值并标记错误，不清空页面。证据：`ui-settings/src/client/config-form.ts:129–155,169–203`；`settings-mirror.ts:138–146,158–194`；`api/settings-controller/src/types.ts:11–21`。

本App的通知级别、后台监控、设备卡片、服务地址、Pocket ID登录、关于/仓库/Issue是**移动端扩展**；这些可以设备本地持久化，并与官方Host偏好在数据模型中分开，不能用AppStorage冒充Host设置同步。

### 3.2 `ui-chat`字段

| 字段 | 可写值 | 缺失/兼容规则 |
| --- | --- | --- |
| transcriptView | compact / standard / detailed / verbose | 官方普通Web默认detailed，Desktop默认standard；旧normal/expanded读作detailed，不再写旧值。 |
| collapseTiming | completion / next-input | 默认completion；独立于工作详情模式保存。 |
| foldedReplies | all / final | 默认all；verbose不折叠，因此隐藏该设置行但保留其偏好值。 |
| performanceUsage | compact / detailed | 默认detailed。 |
| linkOpening | sidebar / new-tab | 默认sidebar；本App能否提供相同内置浏览器要独立判断，不能假装功能存在。 |

证据：`ui-chat/src/chat-settings.ts:5–98`；Desktop默认例外在`ui-chat/src/client/apply.ts:169`；旧值兼容见`ui-chat/src/client/transcript-view.ts:69–78`及`chat-settings.ts:41–52`。

工作详情不是单纯字号/间距选项，它改变呈现策略：

| 模式 | 完成Turn折叠 | 过程分组 | 运行中的详情 | 已结束思考首行预览 |
| --- | --- | --- | --- | --- |
| compact | 是 | 当前/历史均折叠组 | 否 | 否 |
| standard | 是 | 当前/历史均折叠组 | 是 | 是 |
| detailed | 是 | 历史折叠；当前展开 | 是 | 是 |
| verbose | 否 | 不分组 | 否 | 是 |

证据：`ui-chat/src/client/presentation-policy.ts:25–85`。完成/下次输入时点、保留全部/仅最终回复应传入转录投影，而不是只更换设置页选中状态。

### 3.3 `ui-theme`和`locale`

`ui-theme.preference`为light/dark/system，默认system；选中框读**保存的偏好**，不能在系统深色时把system选中改成dark。`ThemeRuntime.setTheme`即时发布且写入Host；系统外观变化只在system模式下驱动活动主题。`ui-theme/src/client/AppearanceRow.tsx:30–58`；`ui-theme/src/client/index.ts:205–216,258–265`。

字体字段：`fontSize`文字默认14、范围整数10–22；`codeFontSize`默认11、10–16；`terminalFontSize`默认13、10–20。字体族分别`textFontFamily`/`codeFontFamily`/`terminalFontFamily`，空字符串选内置字体。`ui-theme/src/theme-settings.ts:57–76,91–106`。字体设置默认只展开文字大小；点disclosure再显示文字/代码/终端字体族及代码/终端大小；每次挂载默认收起。`FontSettingsGroup.tsx:34–54`。鸿蒙无法解析桌面字体族时应保留Host值，并使用平台字体fallback，不破坏其他客户端的设置。

`locale.preference`是显式BCP47语言id；**字段不存在**表示跟随客户端系统语言，没有名为`system`的可写语言值。基础支持zh/en，其余由语言包目录注册。选已在屏幕上显示但未显式保存的语言仍应写Host。`locale/src/locale-settings.ts:5–35`；`locale/src/client/index.ts:244–261`。鸿蒙界面只应提供实际已打包翻译，不能显示并未实现的语言。

## 4. 三点菜单及通用浮层

### 4.1 官方Menu行为

`ui-primitives/src/Menu.tsx`不是整页路由：它是**锚定在触发按钮的紧凑下拉菜单**，由业务方控制open。点外面、Escape、Shift+Tab关闭；普通选择是否关闭仍由owner决定，选择后把焦点归还原触发按钮；点击submenu父行只展开孩子，不执行父动作；只开一个submenu；禁用行不能执行。外接键盘ArrowUp/Down/Home/End走可用行，Enter/Tab确认，输入法组合期间不截获。来源：`Menu.tsx:121–171,330–435,450–521`。

portal位置：锚点间距4，屏幕边距12；支持上/下/右及start/end对齐，测量之后才绘制避免首次闪跳，跟随滚动/resize。菜单在模态上方，防止弹层被祖先overflow裁剪。`Menu.tsx:245–308,524–532`；`Menu.module.css:27–67`。

### 4.2 视觉尺寸

| 元素 | 官方值 | 证据 |
| --- | --- | --- |
| 主菜单卡 | 宽144–360；padding4；无额外分组卡片填色；16圆角；突出投影 | `Menu.module.css:6–35`；`MenuSurface.module.css:1–27` |
| 普通行 | min-height34，padding6×8，gap6，字号13/行高20，图标14，行圆角12 | `Menu.module.css:94–109,170–184` |
| dense | 行高30，垂直padding4，保持普通字与卡宽 | `Menu.module.css:126–133` |
| compact | 卡最小156，行24，字11/17，图标12，行8圆角 | `Menu.module.css:135–163`；这是显式模式，不能误把所有手机菜单压到24 |
| 选中 | 默认只显示尾部check；可选fill模式才保持hover填色 | `Menu.module.css:217–231`；`Menu.tsx:487–488` |
| 分组 | 0.5线，margin3×2；非交互灰字标题11/15；避免双线 | `Menu.module.css:253–275` |
| 禁用/危险 | 禁用opacity0.4；危险字/图标为错误色，危险hover背景单独token | `Menu.module.css:165–168,233–250` |
| 超长 | 无侧边submenu时内部滚动，底部footer固定；不是撑出视口 | `Menu.tsx:446–448,548–555`；`Menu.module.css:59–88` |

官方会话视图自己的“更多”是另一个用途：`ui-conversation/src/client/skeleton/ConversationSession.tsx:27–42`中的ellipsis是View tab溢出菜单，不应把“会话更多动作”和“更多视图”合并成一个随意的大页面。业务菜单可用项目需按工作区研究对应的controller/slot核对。

**移动映射建议（非官方源码事实）**：主动作仍用锚定三点按钮的浮卡，屏幕内最大宽min(360,视口-24)，以同一glyph/顺序/禁用/危险语义渲染；触控点击区可扩至40–44vp，字仍13–14，不靠大空白增强可点性。模型搜索/队列编辑等复杂子流程使用在同一前景层内的子面板，系统Back先退子面板，再关菜单，不退出聊天。若窄屏侧边submenu不能容纳，复用同一卡面进入子列表并提供返回；这属于移动适配，必须写入spec并验收。

## 5. 主题、图标、动效与无障碍

- 颜色使用语义token，避免每个组件随意选灰。亮色base/layer2白，主字黑、次字`#61666B`；深色base`#151517`、layer1`#232324`、layer2`#2C2C2E`、layer3`#353638`，主字接近`#F9FAFB`。菜单亮色材质`rgba(248,249,250,.58)`，深色`rgba(67,69,74,.45)`，背景blur40+saturate150%；遮罩仅dim（无模糊），亮色黑24%、深色黑50%。证据：`ui-theme/src/styles/design-platform.css:176–242,288–308,366–418`；`gradient-shadow-text.css:17–24`。
- 圆角阶梯4/8/12/16/20/28；普通过渡200ms，快100，慢300；曲线cubic-bezier(.4,0,.2,1)。`ui-theme/src/styles/base.css:14–23`。
- 普通Modal是遮罩+380宽上限卡，标题16/24/500，28关闭按钮，内容左右24；opacity淡入200；减少动态效果关闭动画。**Menu自身没有定义弹簧/放大进场动画**，不能声称任意复杂native弹簧就是官方原样。`ui-primitives/src/Modal.module.css:6–56,69–131`。
- AppFrame列宽切换用300ms同曲线；拖动期间不动画；减少动态效果不动画。`ui-layout/src/client/AppFrame.module.css:1–56`。
- keyed list成员/顺序改变使用进入/退出100ms、位置滑动200ms ease-out；初次加载不动画，用户首次交互后才启用，切视图/resetKey/未ready/减少动态时不动画。`ui-primitives/src/AnimatedRows.tsx:5–6,42–59,90–120`。不能每次流式文本追加都重播列表进场。
- 图标来自统一`ICON_ARTWORK`，glyph+weight而非Unicode字符；Regular1px/Medium1.3px；currentColor随语义颜色，尺寸由调用方指定，保持viewBox比例。`ui-primitives/src/icons/index.tsx:1–31`及`icons/artwork.ts`。齿轮、更多、返回、关闭、归档、分支、主题图标不应用“◉/⌘/›/×”字体字符替代。
- 触屏不显示键盘快捷键标签；外接键盘仍保留焦点和快捷键语义。`Menu.module.css:211–215`。遮罩层必须阻断背景操作，关闭还原触发控件可访问性焦点，加载/错误不能只靠颜色传达。

## 6. 布局与状态的移动边界

官方正常桌面三栏：中栏保护400；左栏默认280、264–420、收起rail56；宽度小于1024自动收起，窄屏手动展开仅改临时override，不覆盖保存宽度；重新跨断点清除override。右栏放不下300时先移除其track，保护聊天中栏。`ui-layout/src/client/columns.ts:10–58`；`stores.ts:69–75,102–141`。

手机单栏/抽屉替代三栏是合理的鸿蒙映射，但必须保存当前session、草稿、滚动锚点、分组展开和前景层状态。切设置、菜单、工作区、键盘弹出不得重新连接会话或清空草稿。保留状态不等于把所有后台页面继续暴露给触摸/读屏。系统状态栏按用户要求保留；内容避让顶部安全区，底部手势区背景与页面一致，内容不额外垫一条明显底色空隙。这些系统安全区规则属于App需求，不是浏览器CSS。

## 7. 当前鸿蒙工作树差异（只读核对）

| 项 | 当前代码 | 与目标的差异/需验证 |
| --- | --- | --- |
| 设置打开 | `Index.ets:244–255,419–420`用Stack显示设置，底层visibilityHidden仍挂载 | 原先cover不显示问题已有源码修复；不得在没有设备验证时再归因于旧cover。保持此状态隔离原则。 |
| 设置二级返回 | `Index.ets:281–287`先subpage→root，再root→close；`NativeSettings.ets:165–172,237–242`同源page | 已具有正确基本层级，需系统Back和页内Back一致验收；复杂dialog在前时不能一键跳过。 |
| 菜单形态 | `NativeWorkspace.ets:659–670`把conversation替换成整页NativeSessionTools | 与官方锚定浮卡差异明显；使聊天上下文消失。应该独立前景菜单，留聊天可见。 |
| 菜单行 | `NativeSessionTools.ets:98–108`所有行44高、末尾统一chevron；root两块灰卡 | 立即动作不应带“进入下一页”箭头；缺官方前置动作glyph；缺单一浮面材质/分割线/选中语义。44触控可保留，但不能因此把菜单变成设置列表。 |
| 根设置视觉 | `NativeSettings.ets:243–315`四个大圆角卡，21标题，Unicode分组icon，主题按system/light/dark | 和官方General平整分隔行、light/dark/system主题方块顺序及glyph不一致；移动扩展可分组，但不能替代Host General。 |
| Host偏好 | `NativeSettings.ets:81–99,255–269`只调用App bridge保存theme | 缺官方describe/mutate、工作详情、字体、语言等Host状态。设置选中状态与原生转录策略需同源。 |
| 二级布局 | root Scroll现在alignTop；About也alignTop | 属源码中的新修复，需小屏/大字体/短内容不垂直居中、长内容独立滚动验收。 |
| 返回能力派生 | `NativeWorkspace.ets:686–687`onAreaChange仅按wide/showSessions写nativeWorkspaceCanGoBack | 可能覆盖picker/new-session/tools的可返回状态；应从导航栈统一派生。 |
| 复用设置 | Index统一NativeSettings入口已存在 | 兼容Web齿轮必须仅通知App打开此原生设置，不新增服务器设置副本。 |

## 8. Spec必须落下的验收点

1. 手机设置按官方横向分类条布局；Host偏好从describe读取、带revision写入；冲突恢复、断线保留最后值；手机扩展有明确单独分类。
2. 三点菜单贴住锚点，屏内不溢出，不替换聊天；每项glyph、选中/禁用/分隔/危险语义准确；打开复杂子界面后返回只退一层。
3. page/menu/dialog/keyboard/system Back按前景层级消费；返回与关闭后session、草稿、滚动/折叠不丢失；不会触发隐式刷新/重发。
4. 亮/暗/system选择与实际主题分开；全部背景、材质、状态栏/导航区跟随同一palette，无白色闪烁。
5. 长标题、长服务地址、320/360vp宽、横竖屏、大字体和输入法弹起不溢出；无多余顶部空白。
6. 减少动态时所有新增页面、菜单、列表和折叠立即完成；普通动态不在流式文字每个token到达时重复播放。
7. 关于页本地logo/作者头像、用户名、版本、版权、仓库、Issue链接属于App内容；不混成DeepSeek官方账户身份或Host版本。

未深入覆盖的设置业务：模型提供方完整编辑schema、账户充值/权益、插件市场安装、Creator编辑器内部。这些仍应保留官方网页入口；如果要声称全部原生复刻，需再按各自controller补充spec，不能仅凭此通用视觉研究宣称已实现。
