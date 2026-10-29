# DeepSeek Harness：会话与工作区交互源码审计

这是实现 spec 的上游证据材料，不是已完成的鸿蒙功能清单。

## 审计基线与证据约定

- 官方仓库：<https://github.com/deepseek-ai/deepseek-harness>。
- 锁定 revision：`f3803c96974ad4a94195fb97e5c637e9c2a3afe3`。本机官方 clone 的 origin 与此一致；主代理已核对远端 HEAD 与此一致。
- 本文 `path:line` 均相对此 revision 的上游仓库，不依赖开发者机器的目录。GitHub 源码链接可用 `https://github.com/deepseek-ai/deepseek-harness/blob/<revision>/<path>#L<line>` 组合。
- 阅读对象是实际 React/TypeScript 实现、Remote 类型与测试快照；没有运行 GUI。注释中的 Figma 引用只作为实现作者说明，本文不声称已取得 Figma。

## 1. 三种“菜单”必须区分

### 1.1 会话列表行的三点菜单

官方内置内容与顺序由 `packages/client/ui-workspace/src/client/index.ts:317` 注册：

| 顺序 | 动作 | 出现条件与行为 |
| --- | --- | --- |
| 100 | 置顶／取消置顶 | 非归档会话，并且资源 access 允许对应 `workspace/pinSession` 或 `workspace/unpinSession`。图标依状态切换实心／描边 pin。 |
| 200 | 重命名 | `session/rename` 被允许；关闭菜单后打开独立重命名弹窗。 |
| 300 | 分支会话 | `session/fork` 被允许；关闭菜单后从最后一个已完成 turn 创建分支。 |
| 400 | 归档／恢复 | access 允许对应归档动作；归档行同一个位置显示恢复。 |
| 450 | 复制会话 ID | 关闭菜单后复制完整 ID，结果用短暂提示反馈。 |

证据：`session-actions/PinSession.tsx:24`、`RenameSession.tsx:17`、`ForkSession.tsx:7`、`ArchiveSession.tsx:24`、`SessionId.tsx:6`；`apps/web/tests/expected/menu-material/session-menu.expected.md:1` 的实际可访问性快照同样按这五项排列。每个动作可被 slot 扩展，但不代表 native 可以自行捏造“官方菜单项”。

空白占位会话不显示行菜单，也不支持拖动；会话菜单打开时抑制行 hover card。正常行单击进入；仅当前已选会话的标题先经过一次单击 arm 后，双击才重命名，避免进入会话的第二次点击意外改名。桌面 hover 的归档按钮 order 100、pin 按钮 order 200；手机没有 hover，应保留同一操作菜单，不能让核心动作依赖 hover。证据：`rows/Rows.tsx:645`、`:651`、`:659`、`:732`、`:749`、`:764`。

### 1.2 会话内容顶栏的三点按钮：更多视图

官方 `ConversationSession.tsx:27` 的 Ellipsis 实际是 **More Views**，内容来自 `conversation.session.header.views.actions`。它不是上面五项会话管理菜单，更不是模型、队列、工作区和调试数据的大集合。

- 仅 `!hideChrome && tabs.length > 1` 时显示视图栏。
- 固定视图 ID 的聊天排前，其次用户固定的其他视图；未固定的视图不占常驻位置。
- 有“更多视图”扩展时，可见上限是 `max(1, floor((rowWidth - 48) / 120))`。
- 三点菜单列出没出现在可见tabs中的剩余视图；owner entry包含`id/label/pinned/active`与`selectView/setPinned`回调。经扩展审计核对，官方默认`ui-entry-customization`菜单只消费打开操作和当前勾选，并提供可用时的浏览插件/创建插件入口，不提供固定按钮；不能把owner合同直接当成默认可见控件。
- 当前视图在 More 内时 More 按钮显示 active 着色。视图切换沿用同一会话，不创建新会话。

证据：`packages/client/ui-conversation/src/client/skeleton/ConversationSession.tsx:118`、`:125`、`:134`、`:217`、`:235`。

鸿蒙上可以保留一个紧凑会话操作入口以适应手机，但必须在 spec 标明这是移动端入口合并，内部管理动作仍按 1.1；若实现官方更多视图，须与会话管理明确区分，不能声称混合菜单与上游一致。

### 1.3 输入框的模型／推理菜单

模型独立位于 `conversation.input.model`，由 `ui-model-selection/src/client/ModelSelect.tsx` 实现，入口显示模型名称、推理级别与向下箭头。不能为了方便塞入会话三点菜单替代它。

- 已有可用当前模型：根 pane 为两行，“模型 当前值 >”和（该模型有 reasoning 元数据时）“推理 当前值 >”。
- 当前选择在目录中不可解析：直接进入模型列表。
- 模型列表按 provider 分组，提供方顺序通过 `provider-order.ts`；选择数大于 4 才显示搜索框。
- 搜索是大小写不敏感的有序子序列匹配，再按前缀、alignment 分数、目录原序排序，调用公共 `rankByName`，不是简单 includes。
- 推理级别来源是当前精确模型的 Host reasoning 元数据。若有 `defaultEffort`，effective effort 为明确保存值或默认值；没有 `defaultEffort` 时提供“提供方默认”选项。不要硬编码 low/medium/high。
- 打开菜单会刷新目录。选择过程中 pending 行的勾换为 spinner，入口箭头换 spinner，选择行禁用；返回结果成功才关闭。选中原有值直接关闭，不发送无意义写请求。
- 加载错误在菜单中显示 retry；选择被拒绝用短暂 toast，区分 writer-held。旧目录的成功数据保留，不因某个提供方失败清空其他 provider。
- 子 pane 的 Back/Escape 先回两行根 pane，根 pane 再关闭；移动端不会仅打开菜单就强制聚焦搜索、弹出键盘。
- `/model` 与输入框入口通过每会话共享 `ModelDirectory`，不能出现两份当前值。
- 断开 generation 会清除 pending、使旧响应失效，不让旧请求覆盖重连后的选择。

证据：`packages/client/ui-model-selection/src/client/ModelSelect.tsx:1`、`:116`、`:139`、`:152`、`:185`、`:252`、`:287`、`:378`、`:394`、`:402`、`:517`；`directory.ts` 中 `ModelDirectoryState/select/resetConnected`；`service.ts:1` 的 per-session resolver。

## 2. 会话可见性、标题和状态

`packages/client/ui-workspace/src/client/tree.ts:224` 是列表可见性的唯一规则来源：

1. `origin === 'subagent'` 不混入顶级会话列表，子代理通过父会话 catalog 进入。
2. `blank === true` 仅保留当前 mainView 正在选中的那一个临时 New Session；其余 blank 全隐藏。
3. 不使用“标题叫 New Session／默认名称”来推断空会话。真实判断来自 Host `blank`。
4. 归档过滤默认隐藏；`show` 原位置显示；`only` 只显示归档。
5. blank 的存储标题不用于显示和搜索，显示本地化“新会话”；未命名历史显示本地化“未命名”。

当前会话由 `retainedBy.mainView > 0` 识别，不等同于“列表第一项”。加载中的成员若尚无 SessionSummary 不造假占位，等 summary 到达再显示（`:322`）。

每行派生状态包含：pending interaction（approval、plan-review、question）、本会话 running、直接子代理 running 数、未读完成 `completionUnread`、pinned、archived、updatedAt、cwd。归档行淡化且不可进入，行内状态与 pin 标记不显示；详细状态仍可展示于行详情。证据：`tree.ts:35`、`:365`、`:388`，`Rows.tsx:490`、`:555`、`:593`、`:720`。

鸿蒙端最小正确行为：隐藏其他 blank 与子代理顶级条目；保留当前新会话；状态由投影更新；不能把“系统注入消息”当用户内容导致空会话变成可见。

## 3. 工作区不是按 cwd 临时分组

工作区是 Host 注册的 durable entity：`workspaceId/path/title/sessionIds/createdAt/updatedAt`。工作区成员关系来自 `sessionIds`，相同 cwd 不能替代 membership。默认名称须经 `workspaceDisplayTitle` 本地化。

官方浏览器支持三种分组：工作区并列、按已注册祖先路径嵌套的工作区树、平铺。没有归属任何工作区的会话追加到 Ungrouped（键为空串）。工作区实体即使没有会话也显示；只有归档专用过滤时，没有归档成员的工作区不显示。树父节点是“最近的已注册祖先工作区”，不是本机文件系统推测。

证据：`tree.ts:26`、`:292`、`:317`、`:428`、`:629`；`stores.ts:16`；`rows/WorkspaceBrowser.tsx:1487`。

视图状态本地持久化（上游键 `dsh.workspace.view.v5`），包括 groupBy、orderBy、groupExpansion、每个 account 的手动顺序、archivedFilter。默认工作区分组、updated 排序、隐藏归档。切换服务地址应分开本地视图状态；这是移动客户端的隔离要求，上游运行在一个 Host origin 内天然有隔离。

## 4. 排序、置顶、折叠与列表容量

- 近期排序：`updatedAt` 降序，时间相同以 ID 字典顺序稳定打破平局。`tree.ts:145`。
- 手动顺序按 account 保存。工作区各一个、Ungrouped 一个、flat 一个；不是一个全局数组。已有且仍属于 account 的位置保留，新增 pinned 优先，再补近期普通项，归档项保留会计位置。`tree.ts:170`。
- 当前 blank 始终置于其 account 最前，且不重复。然后非归档 pinned 在普通项之前，各分区内部保持调用者顺序。`tree.ts:208`、`:264`。
- pin 属 Host 全局集合，pin 后还把会话置于当前归属 account 与 flat account 的本地顺序前端；unpin 不删除会话，不清空手动顺序。`navigation.ts:391`、`pin-order.ts:45`。
- 拖动会话后切换到 manual；只能在允许重排且非 blank、非 archived 时拖动；pinned 仅与 pinned 互换。工作区 reorder 是 Host `workspace/insertBefore`，会话 membership reorder 有 `workspace/insertSessionBefore`；不要把移动跨工作区当本地数组操作。`Rows.tsx:645`、`WorkspaceBrowser.tsx:217`、`stores.ts:114`。
- 每工作区默认展示 blank 加前 5 个非 blank。running、有运行子代理、待确认、未读完成或当前会话自动抬高 watermark，自动范围最多 50；显式 Show more 与搜索 reveal 可超过 50。`WorkspaceBrowser.tsx:50`。
- 切换 grouping/order/archive filter 时替换视图，不播放会话“搬家”的排序动画；自动状态引起的增量重排允许动画。`WorkspaceBrowser.tsx:275`、`:339`。

移动端可以用分页或“显示更多”维持 compact，但必须保留 attention 会话可达；不能用只取最近 5 个而不显示运行中任务的截断。

## 5. 搜索规则

- 输入去外围空白；最大 500 个 UTF-16 code units。远端内容搜索 debounce 250ms，查询变更时 abort 前一个请求。`WorkspaceBrowser.tsx:50`、`:108`、`:1182`。
- 本地匹配会话标题、workspace label（无工作区时 cwd basename）、完整 session ID，大小写不敏感 includes。
- blank 和 subagent 顶级结果不匹配；归档过滤与普通列表一致。
- 本地匹配先按近期排序，随后追加远端内容结果原序；按 ID 去重。同一 ID 本地已出现时用远端 snippet 补到原位置，不再插第二行。
- 结果显示 title、工作区 context、可选 snippet 和统一状态。总条数受 result limit 约束；远端 hasMore 或合并结果超过 limit 都显示继续细化搜索提示。
- 归档结果可恢复但不可直接打开；单击给短提示。搜索选择结果后，展开所属工作区并 reveal 对应会话，不改变该会话排序。

证据：`tree.ts:534`；`WorkspaceBrowser.tsx:810`、`:975`、`:1126`；`Rows.tsx:519`。

## 6. 新会话、工作区选择与恢复

新会话是“连接/复用合适 blank”，不是每次点加号都堆一个空日志。

1. 目标 workspace 优先为显式选择、当前会话所属、最近 workspace；最近按成员最新更新时间，无成员则创建时间，平局按 Host 工作区顺序。
2. 从目标 membership 中查第一个 `blank && cwd === workspace.path && !archived` 的会话；若请求了 preset，只允许未记录 preset 或记录值相同的 blank。
3. 调用 `session/create`，传 `workspaceId`，可附希望复用的 `sessionId` 与 `agentPreset`。同 workspace、同 preset 的重复点击共享 in-flight promise。
4. Host 可以拒绝复用并返回新 ID；客户端刷新旧 blank 的 projection，不能永远把它错误隐藏。
5. 切换 workspace 可保留已有 draft，是否替换草稿由明确 draft options 控制。用户导航产生 cancellation，过期创建结果不得把新页面抢回旧 workspace。
6. 启动恢复先等 session/workspace baseline：恢复保存的正常会话；保存 blank 时先刷新 projection，再按记录 preset 复用；该 preset 已不存在/非法则退 Host 默认。初次完全空 Host 才尝试 `workspace/initializeDefault`。
7. 归档当前会话成功或流中发现当前被归档时，清除主视图选择；不能继续给已归档会话发送消息。

证据：`navigation.ts:215`、`:235`、`:257`、`:279`、`:337`、`:382`、`:465`、`:507`、`:577`。

## 7. 创建、重命名、删除工作区和目录选择

- 工作区 picker 列出现有工作区；重复名称通过最短可区分 path suffix 消歧，完整 path 保留可查看。选中项勾选。
- Add 操作是选择 Host 上现有/新建的目录，然后 `workspace/create {path}` 注册；不是选择手机本地目录。
- 有列表时 Add 固定在滚动区底部。没有 workspace 且 baseline 已完成，Add 是唯一入口时直接进入目录 flow，不先弹一个只有一行的菜单。baseline 未到则保持 loading，不能擅自认为没有 workspace。
- flow/adoption busy 时禁用所有其他选择，避免迟到结果覆盖新选择；失败用独立错误面板，可“重新选择”；取消无写入。
- 没有组合目录能力则不显示 Add。`workspace/create` 是幂等注册，返回 created 标记及 workspace。
- workspace rename 预填展示名，但是否真正变更比较存储 title；trim 后不能为空、不允许和其他 workspace title 完全重名、不允许未改变。会话 rename 则无客户端重名限制，也不禁用同名确认。
- workspace delete 是删除注册关系，命令本身不等于删除目录。UI 使用确认框、pending 不允许重复动作，成功等权威流确认后清理界面。不要自作主张删除服务器文件。

证据：`WorkspacePicker.tsx:87`、`:110`、`:115`、`:154`、`:172`、`:209`；`WorkspaceBrowser.tsx:1220`、`:1263`；`session-actions/RenameSession.tsx:46`。

官方浏览目录 `ui-directory-picker-browse/src/client/DirectoryBrowser.tsx:1` 的语义：Host breadcrumb、可编辑路径、隐藏文件开关、选择目录、新建子目录、Open 采用选中或当前目录。旧 listing 在异步导航期间保留，慢扫描 300ms 才显示 loading；目标和父级尽量作为同一帧落地（父级等待 200ms），路径草稿跟随 debounce 250ms。移动布局可把 680×500 的双 Miller 列转为单列下钻，但必须保留 breadcrumb、编辑路径、隐藏项、选中与 Open 的区别，不得点击目录就误提交创建 workspace。

## 8. 各项写操作的状态转移

| 动作 | 标准状态流 | 成功 | 失败／取消 |
| --- | --- | --- | --- |
| 会话 rename | 请求目标 → draft → submitting | 关闭弹窗，Host 投影更新 | 保留 draft 与 error，允许重试；submitting 不允许关闭/重复提交；IME commit 的 Enter 不提交 |
| pin/unpin | menu close → command | 权威集合更新；pin front local order | 短提示，保持原位置 |
| quiet archive | menu close → command，无额外确认 | 保留日志/位置，清主视图，提示 Undo/归档列表 | active 拒绝才进入下述确认；其他错误不伪成功 |
| active archive | Host 返回 `workspace/session-active` + activity → 确认 | 显式 `stopActivity:true` 后归档并提示 | Cancel 保留运行，confirm 出错保留对话框；不能在第一次请求静默 stop |
| restore | command | 从 archive set 移除，恢复原 account 位置 | 保持归档；不自动打开 |
| fork | command `{increaseTitle:true, allowMigration:false}` | 新会话从 Host list 出现于源会话旁；不要求自动选择 | migration-required 提示先打开会话；不在后台强做迁移 |
| copy ID | menu close → clipboard | 短成功提示 | 短失败提示 |
| workspace create | picker → directory flow → adopting | pick 新/已有 workspace，再连接 blank | 失败可重新选择，busy 锁防竞态 |

证据：`index.ts:174`、`:182`、`:193`、`:216`、`:224`、`:236`；`navigation.ts:321`；`ArchiveSession.tsx:105`；`RenameSession.tsx:73`。

## 9. 传输契约：不能用猜测的 HTTP path 代替官方 Remote

Host Remote namespace 是 `workspace`，源码 `packages/api/workspace-controller/src/index.ts:72`。请求 payload 是声明的 request，不是任意 UI JSON。

| Endpoint | 业务输入 |
| --- | --- |
| `workspace/follow` | stream，无业务 request；每 generation 开头 baseline |
| `workspace/create` | `{path}` |
| `workspace/initializeDefault` | 无业务 request |
| `workspace/rename` | `{workspaceId,title}` |
| `workspace/delete` | `{workspaceId}` |
| `workspace/insertBefore` | `{workspaceId,beforeWorkspaceId?}`，缺 anchor 表示末尾 |
| `workspace/insertSessionBefore` | `{workspaceId,sessionId,beforeSessionId?}` |
| `workspace/archiveSession` | `{sessionId,stopActivity?}` |
| `workspace/unarchiveSession` | `{sessionId}` |
| `workspace/pinSession` / `unpinSession` | `{sessionId}` |

`follow` baseline 是 `{type:'baseline',value:{items,archivedSessionIds,pinnedSessionIds}}`。后续有 replace（完整取代）、upsert、remove、order、archived、pinned；断开重连必须从新 baseline 开始，不能把旧增量套进新 generation。Host 会按 remote access 过滤资源与 membership。证据：`types.ts` 的 WorkspaceBaseline/WorkspaceFollowFrame，`index.ts:205`。

目录 namespace 是 `directoryPicker`：`pick(signal)`、`list(path?,signal)`、`createDirectory(path,name)`，能力有 native 与 browse 区分，不是所有 Host 都有。错误包括 unavailable、unreadable、exists、create-failed；必须保留稳定错误码。证据：`packages/api/workspace-controller/src/directory-picker.ts`。

## 10. 建议写进鸿蒙实现 spec 的验收用例

下面是从源码行为得到的验收要求，尚未声明 app 全部支持：

1. 连点新会话不堆空条目；其他 blank 隐藏，当前 blank 以新会话显示。显式同名历史可正常显示。
2. 父子代理不重复混入顶级；pending、running、子代理 running、未读完成在列表及时反映。
3. 会话操作菜单五项按官方顺序，依据状态与 access 出现；不会展示原始 JSON、大型目录或无关配置。
4. 返回逻辑是 child pane → 入口根 → 会话；系统返回与可见返回按钮一致，不丢草稿。
5. 归档静态会话无需破坏性确认，支持 Undo；活动会话拒绝后才确认 stop；取消不停止，恢复后保留原顺序。
6. fork 从最后完成 turn 创建、标题按 Host 递增、出现在源会话附近；迁移拒绝有明确短反馈。
7. 搜索支持 ID、title、workspace 与远端内容，旧查询晚到无覆盖，不重复结果；归档结果只能恢复后打开。
8. workspace 创建针对服务端目录；支持 Host 能力判定、取消、失败重选、重复目录幂等；永不删除目录文件。
9. 切换账号/Host 的 cached workspace 和会话列表隔离；重连 baseline 原子替换状态，选中会话的旧 pending 写请求失效。
10. 输入框模型菜单为独立两级交互，动态 Host effort、搜索阈值、busy/retry/短错误提示正确；手机打开不自动召唤键盘。
11. 手机上行视觉紧凑，触控热区可大于视觉 glyph；长 workspace title/path/model name 截断，详细值可查看，弹层不得越安全区或键盘。
12. 正常增量排序可动画；切换 grouping/filter/sort 不用移动动画误导用户；减少动态效果设置有效。

## 11. 当前移动实现需要特别复核的差异

在开始新实现前，主代理应对现有代码做 gap table。至少不能遗漏：当前临时 native 三点页混合模型/队列/工作区入口；本地 workspace picker 可能仍只支持手输目录而缺官方 Host 浏览 flow；只有 list snapshot 无 follow 增量会漏掉其他客户端的 rename/pin/archive；只按 cached content 推断 blank 不能等价 Host blank；普通 archive 加强制确认与官方安静归档逻辑不同；没有 access gating 时显示会被拒绝的按钮也不是官方交互。

这些是审计关注点，不是对未完整读取的 app 代码做已确认缺陷判定。实现取舍必须在主 spec 标注“保留上游语义”或“手机布局适配”，不能把删去能力当作同等完整移植。
