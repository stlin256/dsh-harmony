# 连接、缓存与工作区分类研究

日期：2026-10-30。覆盖 [需求登记](../requirements/2026-10-30-native-polish.md) 的 CONNECT-01～07、WORKSPACE-01～09；CONNECT-06 与主题/设置研究衔接。本报告是写 spec 的依据，不是实现完成声明。

## 1. 审计范围与事实等级

- App 工作目录的读取基点为 `b2906a3cb21c8e65372f325567595d46664d0f50`，同时检查现有未提交补丁，尤其 NativeWorkspace 的 connecting、取消冷打开 HTTP hydration、首窗口 80→24 与 hasMore 传递。未把这些补丁视为已通过手机验收。
- 官方实现固定为 `deepseek-ai/deepseek-harness@f3803c96974ad4a94195fb97e5c637e9c2a3afe3`（0.2.2-alpha.2），不跟随变化的 HEAD。
- 主代理本轮提供的远端 CLI 事实：升级后 19 个会话、2 个真实工作区、Host 设置和 Markdown 导出可读。本研究未操作远端服务或设备，也没有测量真机首屏时间。
- **确认**表示当前源码可直接推导或纯合成实验可复现；**待证实**表示需要下一阶段手机/网关分段诊断。不能把潜在网络问题写成已经确定的断连原因。
- 本轮只新增本报告；未修改 App、网关、设备、服务或上游源码。合成基准通过 stdin 执行，未写入测试脚本。

## 2. 当前真实调用链

```text
页面挂载 reload
  GET state（认证）
  → GET native/sessions（网关 POST session/list）
  → 更新会话列表
  → 异步 GET native/workspaces（临时另建 Mux，取首 baseline 即关）
  → 异步 settingsDescribe、overview
  → 若最近/通知有 selectedId 则 select/follow

select
  先拿内存 model/draft/images 画旧内容
  → 新建手机至网关 WS（关闭前一个）
    → 网关新建至 Host Mux
      → $events
      → session/follow（24 messages，assistantStream）
      → session/observeState
      → session/observeProjections
      → 若后两者 invocation-unavailable，退 session/control + HTTP list
  → 另发 modelCatalog + projections HTTP

每帧 apply；最多约每40ms paint
  → 从所有已加载 NativeMessage 全量构建 transcript
  → 全量 presentation
  → MessageSource reload
  → 同时重新过滤/排序/重置 session list
```

证据：`harmony/entry/src/main/ets/components/NativeWorkspace.ets:148`、`:402`、`:434`、`:493`；`services/NativeHarnessClient.ets:170`；`gateway/src/native-harness.mjs:33`、`:67`、`:288`、`:291`。

当前临时 patch 已取消 select 同时执行 `hydrateHistory` 的调用，但该死方法仍在 `NativeWorkspace.ets:423`。基线版本确实同时 page 与 follow 读取首屏；后续不能把“本地改掉调用”写成已经证明用户设备没有重复读取。

## 3. 官方连接和状态合同

### 3.1 不能按版本猜端点

固定上游 `packages/api/session-controller/src/index.ts:561`、`:583`、`:606`、`:627` 同时声明 observeProjections、observeState、follow、control。现有测试 fixture 的 `modern` 参数通过人为令前两个端点返回 invocation-unavailable 来验证 fallback；它只能证明降级分支，不证明所有 0.2.2 Host 都移除了观察端点。

运行时若遇到 unsupported，必须记录稳定 endpoint/error code，并按当前 Host generation 一次协商；不能每次打开会话都靠失败探测一遍，也不能把所有错误归为“版本太旧”。

### 3.2 官方拆分

- 根级共享 Session control：每 generation 首个 baseline 为 `{type:'baseline',value:{projections:{[sessionId]:{asOfSeq,values}}}}`，之后是 `{type:'projection',sessionId,key,value,seq}`。并非只为当前聊天临时建一份。
- 工作区 follow：每 generation baseline（items/archive/pin）之后接 replace/upsert/remove/order/archived/pinned；默认保持订阅，不取到首帧就断开。
- 选中聊天 journal：follow snapshot 有 header/cursor/records/hasMore/**projections**/**assistantStream.revision**；durable event 连续 seq；assistant frame 有 dense revision，attemptId、index、end outcome 与 committed seq。
- 较早 page：以固定 throughSeq、beforeSeq、maxMessages/turnWindow 向前补。page 响应不是新的连接 generation，也不应清 transient assistant baseline。
- `SessionFollowRequest` 的公开输入是 address、activate?、assistantStream?、maxMessages?、turnWindow?；该版本**没有可擅自添加的 afterSeq/resumeCursor 参数**。缓存恢复应按官方完整 opening 与 journal 合并/修复实现。
- 官方 `SessionEventStream` 为用户打开会话传 activate:true；当前 native follow 未传 activate，保持被动读。是否需要激活必须在主 spec 明确区分“打开会话”“后台只读列表”，不能为解决慢加载让所有会话无条件激活。

证据：上游 `api/session-controller/src/types.ts:467`～`:583`；`src/client/transport.ts` 的 SessionEventStream/RemoteJournalStream；`src/client/sessions/assistant-stream.ts`；`api/workspace-controller/src/client/index.ts` 与 `model.ts:264`、`:311`。

### 3.3 当前协议损失

`gateway/src/native-protocol.mjs:112` 开始的 normalizeFollow 丢弃 snapshot.projections、assistant revision、startedAfterSeq/turn/step、end.index/outcome/committed seq；`NativeSessionModel.apply:202` 只拒绝 seq<=cursor，不验证 seq 恰好 cursor+1。丢一个 durable event 后会静默前进，后续 replay 被 cursor 丢掉。assistant delta gap 则抛错，经 `NativeHarnessClient.ets:196` 被缩成 frame_handler_error 并整体重连。

这是**确认的完整性和诊断缺陷**，但不能仅凭源码断言实际手机每次断连都是 gap；必须保留具体分类后取证。恢复规则应是 journal gap修复/新baseline、transient gap rebaseline，不是断线就删掉缓存或自动重发 prompt。

另外有两项需带分类实测、目前不能归因为已确认故障：网关每30秒ping并在下次仍无pong时terminate（`native-harness.mjs:263`～`:268`），须分别记录heartbeat丢失与普通close，确认手机载体自动pong及长主线程任务期间的行为；网关以32KiB WebSocket fragments发送一个逻辑JSON message（`:279`），须用跨UTF-8字符的大快照验证NetworkKit按完整message交付，不能因有分片就推断实现有误。当前大消息测试使用Node ws消费，不等同真机NetworkKit覆盖。

## 4. 逐项 CONNECT 根因与设计建议

| ID | 当前真实根因与证据 | 应写入 spec 的行为/结构 |
| --- | --- | --- |
| CONNECT-01 | 基线 select 直接 reconnecting=true，把首次请求当断线；现有未提交补丁已增加connecting并改此处。仍以若干布尔值分散维护，follow入口只connected=false，前后台/兼容触发并不统一设置opening；首个error frame直接reconnecting=true，await close才计划重试。证据 NativeWorkspace:91～99/419/434/455。 | 统一有限状态：idle/opening/ready/retrying/blocked/paused；另有cacheReady/historySync。首次opening显示简短loading/旧缓存，无断线横幅；实际失败后retrying才显示横幅；auth/unsupported不是无限retry。 |
| CONNECT-02 | 冷bootstrap串行state→sessions后才select；每次会话follow另握手2层WS；模型目录再HTTP2请求。旧基线还并发page+follow，已在pending patch撤掉。normalizedHistory对大正文重复序列化，paint重做全历史（见第6节）。 | 先渲染last-good列表与选中model，认证/目录/设置后台并行且single-flight；首屏唯一history opening；模型catalog按Host共享、selection读现成projection；记录分段时间，先优化bytes和全量扫描，再谈动画。 |
| CONNECT-03 | 当前有正确supportOriginPort:true；不可回退。错误均被折叠，socket reason只console，网关error把业务/协议/transport全部close1011；网关首snapshot15s强制断开，手机只对socket open有20s timer（open后不再监督snapshot）。每次reset会重跑可选observer失败探测，retries在每snapshot归零，快速“成功snapshot→立即坏流”可永久2秒循环。 | 双层连接各有generation与分类，required history失败才使聊天不可用；可选control失败局部降级；snapshot时限取可观测阶段并仅启动一次opening。attempt稳定时间窗口或失败计数防flap，exponential+jitter+网络可用性；永久401/403/unsupported终止自动重试。保留failure code而不记录token/正文。 |
| CONNECT-04 | models/drafts/images内存存在且设置Stack保留组件，这是已有正确基础。但模型/列表无LRU或size预算，journal无限累计；每次select followTail=true、running=false、waiting=false，未保存每会话阅读锚点/stream UI态。兼容关闭同时activityChanged.follow与refreshRevision.reload可触发两轮，reload再follow。HTTP请求没有可取消scope，晚结果只部分用selected/mounted护栏。 | client服务拥有Host身份scope与有界缓存；视图只持有view reference；区分activeChatId/recentSessionId。保留model/transient/draft/images/anchor按Session；设置不重连；兼容和前后台single-flight恢复；logout切identity先abort所有请求、invalidate generation、清缓存和敏感本地状态。 |
| CONNECT-05 | prompt在函数内部生成requestId后不保存；失败后只uncertain Set<sessionId>，无法按原id对账。按钮文字“已检查会话，允许再次发送”实际只删除Set，不执行检查（NativeWorkspace:742）。不会自动重发是已有正确行为，但用户再次点可能以新ID重复提交。 | 每次submit保存{id,requestId,contentDigest,attachmentRefs,phase}；accepted receipt/inbox/日志按requestId核对，未知保持未确认。主动“重新发送”需明确新请求，不能伪称已检查；网络重连只读同步，绝不new UUID自动重试。 |
| CONNECT-06 | NativeSettings.host初始空description，aboutToAppear不先hostChanged，只refreshHost，等HTTP结束才赋已有client镜像（:46/67～78）。刷新期间禁全部Host controls。NativeHostSettings.refresh有latest-read-wins但无inflight合并；bootstrap与设置重开可重复describe。 | mount同步采用last-good Host镜像/现有revision，马上有内容；loading只表示后台refresh而非empty；每Host single-flight refresh、可写busy按namespace/field；set用最新revision，冲突回读，失败不把未知写当成功。详见设置研究。 |
| CONNECT-07 | 主断线文案已短，列表与聊天各可画一条；error仍为全局裸Text，gateway带较长technical fallback。不同场景reconnecting可污染无活动聊天列表；未确认发送按钮文字过长且不实。 | 同一可见surface最多一条连接横幅“连接中断，正在尝试重连”；初始loading/缓存陈旧/业务操作失败分别用局部短反馈，不把operation error变成连接横幅；不会每条message插重复错误。 |

## 5. 逐项 WORKSPACE 根因与设计建议

| ID | 当前真实根因与证据 | 应写入 spec 的行为/结构 |
| --- | --- | --- |
| WORKSPACE-01 | `sessionList`只有一组LazyForEach，workspaceId为空时nativeWorkspaceSessions不过滤membership，显示“全部工作区”的flat列表；没有group header/Ungrouped/折叠树。workspace数据已可读不等于UI已分组。NativeWorkspace:602～654，NativeSessionModel:67。 | 默认按Host workspace entity/membership分组，标题+文件夹+数量+展开；Ungrouped独立。选择某workspace可过滤但不是分组的替代品。state持久化分组/排序/展开，不能按cwd猜实体。 |
| WORKSPACE-02 | gateway已允许workspaceCreate/Rename/Delete/Order和directoryList/Create，但NativeWorkspacePicker只手输path添加、行内rename、archive恢复；无Host目录浏览、移除注册/排序UI。无session insertBefore桥接；只有updated排序，helper的manual参数未从UI传入。create只在无preset时找blank，未核对cwd/preset兼容完整规则。 | 按官方pick Host directory→adopt；添加/rename冲突/删除注册确认/reorder分别可达；删除注册不删目录。membership/归档/pin权威，复用blank核对membership/cwd/archived/preset，去重连点。缺能力应真实隐藏或说明，不能只有backend endpoint就标done。 |
| WORKSPACE-03 | gateway workspace route任意异常吞掉返回HTTP200 `{available:false,items:[]...}`(:81～84)，丢401/403/timeout/unsupported/Mux error差别。App refreshWorkspaces忽略false与全部exception(:311)，首次失败留default false，picker显示“接口暂不可用”，无刷新按钮/appear重试。正常baseline成功后又失败只悄悄留旧值，无stale提示。 | 建独立WorkspaceStore：phase pending/ready，refresh idle/loading/error，lastGood，errorKind，generation；transient失败保留lastGood并重试，unsupported仅稳定端点拒绝，auth送登录。picker可重试并区分初始loading、真空、未提供。远端已有2工作区意味着必须追手机经过同一反代/身份的完整链路，不能只说Host没插件。 |
| WORKSPACE-04 | backToSessions只showSessions=true，不清selected；row背景永远`selected===item.id`，因此退出仍高亮（:198～209、:651）。近期会话/缓存身份与正在屏幕上显示的身份共用一个selected。 | route.visibleChatId与recentSessionId分开。手机列表页activeChatId为空，缓存与recent保留；wide时可仍同时选中聊天。返回/通知/点击/new session共享路由状态，所有selection样式从route派生。 |
| WORKSPACE-05 | menuId已正确按目标记录，但ellipsis永远Transparent；行背景只看selected，不看menuTarget/menuId（:642～651）。打开菜单不产生目标高亮。 | `menu.open && menu.sessionId===row.id`时trigger与行使用对应DSH pressed/open填充；dismiss/切目标/reset复位；按ellipsis不导航或改变聊天选择。通过真机验证Button事件不冒泡触发ListItem select，不能仅假设。 |
| WORKSPACE-06 | 网关未截title字符串，当前截断主要是列表Text、会话header、workspace picker的maxLines(1)+Ellipsis；管理menu不显示目标完整title。:633、:678～679，Picker.row。不存在证据证明Host只返回固定字数。 | 保留完整canonical title，不slice。手机允许标题换行/动态行高；若长内容需要紧凑折叠必须有直接可发现的完整标题阅读入口，不能只有无障碍文本。菜单header标明当前目标并能完整阅读；超长CJK/英文无空格/emoji/大字体都不挤掉操作。 |
| WORKSPACE-07 | origin subagent filter和Host blank字段已有；但nativeSessionVisible先用running/cache正文覆盖Host blank，且list保留selected会把刚退出的blank继续当current。无Host字段fallback只按中文默认title猜，不等于多语言正确。数据不是实时control更新，blank/running/title可能陈旧。 | Host blank是权威，当前main route的临时new/engaging只显一个；历史存在真实人类内容/Host metadata会变nonblank。系统注入不能构成可见性依据，子代理独立入口；空标题历史不等于blank。新建重复点击single-flight，端点拒绝复用刷新旧projection。 |
| WORKSPACE-08 | 侧栏和header已拆分且使用anchored popup，是已有正确方向。nativeSessionMenu无resource access gating；全局menuBusy禁所有行，活动归档确认没列Host activity；utility每开重做2个HEAD，失败一律“此服务未提供导出”。固定208vp菜单与长目标title/大字体需复核。 | 各入口保留官方顺序/语义；menu target独立，busy精确到动作，短error保留可重试；取完整Host活动列表后确认stop。能力缓存有unknown/error/available区别，不能请求超时当永久不存在。导出与反馈按已审计真实合同实现。 |
| WORKSPACE-09 | query仅本地title/id/当前已选workspace title/cwd的includes；“全部工作区”下workspace变量为空，按真实workspace名搜不到其members。没有远端content search、归档show/only。sort内对pin/membership反复indexOf，paint每40ms即使列表没变仍filter/sort/onDataReloaded。 | ID/title/workspace本地映射+官方session.search内容，250ms debounce/cancel/去重；local recent先，remote原序补snippet。排序预建rank Map/Set，列表只在metadata/query/view变化更新；每workspace默认5并为attention自动抬watermark。 |

## 6. 性能实验：仅合成桌面，不是手机成绩

### 6.1 归一化传输重复

使用当前 `normalizedHistory`，输入一条100KiB纯ASCII assistant正文（无私人数据、无图片/工具）。原始records JSON为102,570 bytes；归一化JSON为615,194 bytes，**6.00倍**。原因是同一正文出现在text、blocks、segments.text、segments.blocks、contentRaw、journal.raw多处；raw字段还需JSON转义和重复parse。

证据：`gateway/src/native-protocol.mjs:65`～`:75`、`:91`。这不是所有真实会话固定放大6倍，但确认当前简单消息就产生6份表示。把maxMessages从80减24不能约束单条数MB工具输出，也不能消除重复。

建议：传输保留一份规范typed事件/journal，展示投影通过seq/block引用；原始inspect按需读取/共享内存，rich blocks在客户端增量解析且按event缓存。若保留双表示过渡协议，至少不在同条payload重复raw正文六次，并以bytes+records双指标约束首窗口。不得通过永久截断真实内容改善数字。

### 6.2 全量投影成本

使用现有测试相同方法，以TypeScript transpile+Node VM加载原始`.ets`纯服务。每turn固定7条（start/user/reasoning/tool-call/result/assistant/end），每组执行`nativeTranscript`+`nativePresentTranscript`五次取中位，mode detailed、foldedReplies final。Runtime为本机Node v24.19.0；不含网络、JSON、ArkUI布局或设备运行。

| turns | input records | visible rows | 桌面纯投影中位ms |
| --- | --- | --- | --- |
| 25 | 175 | 100 | 0.33 |
| 50 | 350 | 200 | 0.67 |
| 100 | 700 | 400 | 1.71 |
| 200 | 1,400 | 800 | 3.09 |
| 400 | 2,800 | 1,600 | 13.28 |
| 800 | 5,600 | 3,200 | 44.12 |

这组实验只说明非线性放大与同步CPU风险，不能当成真机耗时或承诺提速倍数。当前40ms paint周期在这组大fixture上甚至短于桌面一次纯投影，不考虑ArkUI仍有赶不上节奏的风险。

确认的复杂度位置：

- `NativeTranscript.ets:202`每个ended turn对全部rows findIndex并slice/some，最坏O(turns×rows)，还分配后缀数组。
- `:255`每个assistant在foldedReplies final时对rows.some，同样可达O(rows²)。
- 每次paint调用完整nativeTranscript(:105)，复制所有row、tool tree、process标题并再调用presentation；最终`MessageSource.set`除了纯append外onDataReloaded；streaming同长度内容更新也是整表reload。
- `NativeSessionModel.apply`逐event concat(:210)与逐replacement全过滤，长期批量灌入有二次复制风险；`remember`在每range内scan全journal，过多replace同样乘积增长。
- nativeWorkspaceSessions的sort对pin/membership数组线性查找；paint即sessionsChanged(:497)，工具token更新也重排全部Session。

建议：先用Map一次构建turn→firstProcess/hasInterleavedUser/hasControl/lastReply、call→tool、membership/pin rank；durable event只更新受影响turn，prepending只对新前缀与跨边界turn重算；streaming只更新当前attempt/process；presentation对受影响turn+偏好revision缓存。数组源发布精确add/change/move，metadata未变不重算session列表。LazyForEach不是投影虚拟化：它只减少UI组件，不减少前面的全量纯函数。

## 7. 推荐状态与缓存架构

### 7.1 身份、连接和视图三层

1. **HostScope**：normalized origin+认证身份+generation，拥有transport、single-flight目录/设置/工作区与session metadata。logout/换Host必须整层invalidate，清所有敏感内存和挂起callbacks；同Host账号变化不能沿用另一身份缓存。
2. **SessionCache**：by durable Session address，拥有journal window、typed projections、assistant attempt revision/index、提交回执、draft/attachmentRefs、disclosures、阅读anchor。不要把缓存是否存在当成当前页面选择。内存有可观测bytes/entry count与LRU，active/unsent draft/uncertain submission不被普通LRU静默丢弃。
3. **ViewRoute**：list/chat/settings/preview/compatibility与activeChatId/menuTarget；visible flags统一派生。转settings不销毁Session；手机Back到list仅解除active，recent仍可记住；width变大并列模式不意外clear或重新打开。

### 7.2 连接状态机

```text
idle → opening → ready
         │        │
         ├─永久认证/能力错误→ blocked（明确动作恢复）
         └─可重试transport→ retrying ─退避→ opening
active变false/compatibility接管 → paused（有意暂停，不报断线）
paused → 一次恢复opening（保留cache与anchor）
任意identity改变 → disposed（旧请求不能再发布）
```

history/window状态单独pending/ready/stale/error，不用socketOpen代表内容ready，也不用history还没返回代表socket坏了。首次冷打开缓存不存在时loading；热打开立即显示cache但标注同步中（可用细小loading），真实故障才横幅。silent optional catalog/projection读取失败不必关闭完整history socket。

### 7.3 共享Catalog与Mux

推荐手机到网关共享一个受认证native carrier，分streamId承载Host control、workspace follow、当前Session follow、interaction；gateway对应复用上游Mux并按owner隔离，不跨用户共享waterfall。实现若暂时保留一个selected-chat WS，也至少将workspace/control改为服务scope长流，并缓存能力探测；不要每个工作区GET新握手后丢掉增量。

兼容路径先协商现代schema与支持的endpoint，旧Host适配只在缺能力时使用；每generation一次。不能因可选observer返回error而整个聊天无限flap。control baseline不能假定包含冷Session所有projection，selected follow snapshot的projections需正确seed；cached列表hint和sequenced基线不可按同一asOfSeq直接比较。

## 8. 工作区与命令合同

现有工作区native response需要从boolean available扩展为至少：`phase`（初始pending/ready）、`refreshStatus`、`hasGoodSnapshot`、`generation`、`items/archive/pin`、`failure.kind/code/retryable`。这是拟定native桥合同，**不是上游已经有同名字段**。桥接保留upstream工作区createdAt/updatedAt供竞态和最近workspace计算。

上游真实输入（payload envelope仍按Typert声明，不随native JSON任意改变）：

| 契约 | 输入/基线 | 合并、失败与取消 |
| --- | --- | --- |
| workspace/follow | args无业务request；baseline含items/archive/pin | 每generation先完整replace；其后upsert/remove/order/sets；carrier fail保留lastGood；权限撤销移除被撤资源 |
| workspace/create | request `{path}` | 幂等采用Host现有目录；返回workspace+created；取消选择前不写，adopting后不能假装撤销Host已提交 |
| workspace/rename | `{workspaceId,title}` | trim非空/唯一名，保持draft与冲突错误；旧updatedAt unary echo不得盖新stream |
| workspace/delete | `{workspaceId}` | 移除注册，确认，不删文件目录；成功后处理当前workspace选择和Ungrouped |
| workspace/insertBefore | `{workspaceId,beforeWorkspaceId?}` | 省anchor末尾；流与unary顺序按generation/请求序对账 |
| workspace/insertSessionBefore | `{workspaceId,sessionId,beforeSessionId?}` | Host membership内排序，不能本地伪造跨区迁移；当前bridge尚缺入口 |
| archive/unarchive/pin/unpin | `{sessionId,stopActivity?}`（stop仅archive） | quiet archive无需额外confirm；active拒绝带activity后才confirm stop；保存位置可恢复；pin/archive互斥 |
| directoryPicker/list、createDirectory | direct args `{path?}` / `{path,name}` | Host目录，不是手机目录；capability unavailable与unreadable/exists/create-failed分开；query换target取消旧scan |
| session/create | request `{workspaceId?,cwd?,sessionId?,agentPreset?}` | workspaceId与cwd互斥，命名blank复用；不要每点都new ID再堆空对话 |
| session/search | request query（以公开types为准） | 结果是content snippet，不混为session/list传query；cancel与去重见原工作区审计 |

官方 `api/workspace-controller/src/client/model.ts` 在baseline替换时抬order/archive/pin request counters，避免晚unary写回旧集合；在upsert比较updatedAt，不能只用最后网络响应赢。

## 9. 诊断与指标：先区分段落，不编造手机成绩

每次打开分配不含身份信息的operationId，记录阶段相对时间、计数和stable code；所有域名/URL/query/cookie/request正文/真实标题均不进入publication日志。

| 指标 | 精确定义 |
| --- | --- |
| cacheFirstPaintMs | 用户选择至旧缓存第一个可读消息已提交UI；无cache记notApplicable，不能记0 |
| coldFirstReadableMs | 无cache选择至首批可读消息UI提交，不以WS onOpen代替 |
| authoritativeReadyMs | selected follow baseline完整校验、projection/assistant接入且已发布 |
| handshake stages | 手机socket open、网关upstream open、history open send、raw snapshot first/last byte、normalize、send drain分别计时 |
| transportBytes | 原始snapshot、native snapshot、page、当前attempt，包含重复字段真实bytes |
| cpu stages | decode/parse、model apply、projection、source publish、首layout分别计时；报告p50/p95与长帧，不合并成“网络慢” |
| duplicateReads | 单次selection的state/list/page/follow/catalog/describe数量；是否因compatibility close/foreground双触发 |
| reconnect health | generation、attempt、previous-ready-duration、reason/code、backoff；永久错误禁止retry计数 |
| workspace health | upstream handshake/baseline code、nativeHTTP status、app parse/install、lastGoodAge、item数量；成功空与失败绝不混 |
| integrity | expected/actual durable seq、assistant revision/index、repair/rebaseline次数；只打数字，不打content |
| memory | cached Sessions、journal bytes、render projection bytes、附件bytes、LRU淘汰与被pin原因 |

下一阶段性能门槛建议（**目标而非实测**）：热cache同步渲染不等待任何HTTP；普通fixture一次projection目标p95小于8ms且streaming不随历史长度线性/二次增大；2工作区/19会话不因token repaint重建列表；冷打开基于真实链路基线做p50/p95对比，先要求无重复首history读取、无首屏自动连续补页、无成功snapshot后立即flap。暂不承诺特定公网秒数。

## 10. 必须完成的验收矩阵

### 10.1 CONNECT

- CONNECT-01：冷打开延迟snapshot、正常空会话、缓存热打开都不出现断线banner；断开后才出现；paused/compatibility不误报。
- CONNECT-02：同一selection只有一个follow opening，无首次HTTP page并发；初次position不触发onReachStart连续加载；模型/设置目录共享请求；25～800合成turn复杂度与手机长历史录制分别报告。
- CONNECT-03：模拟401/403、legacy observer unsupported、workspace-only failure、DNS/TLS、20s级冷历史、丢durable seq、assistant重复/缺revision、异常end、服务restart；每种有正确重试/阻塞/修复，不靠隐藏banner；supportOriginPort回归。
- CONNECT-04：A→B→A、聊天→settings→back、兼容→native、前后台、旋转宽窄、断线rebaseline，保留draft/附件/当前阅读anchor；旧请求晚到不发布到B；logout/换Host/换身份清理且无旧数据闪现。
- CONNECT-05：Host已接受但HTTP响应丢失，按原requestId证实只一条；unconfirmed不重复send；用户主动新提交可区分，禁止“已检查”假文案。
- CONNECT-06：已有Host镜像时设置打开首帧即有选项，异步refresh失败仍显示旧值+短retry；同revision写冲突正确恢复，不覆盖另一客户端更新。
- CONNECT-07：同surface只有一条统一断线横幅，操作失败局部提示；切list不留不相关聊天错误。

### 10.2 WORKSPACE

- WORKSPACE-01：2个Host实体、跨成员同cwd、Ungrouped、无成员workspace分别显示；分组不依赖路径basename或标题相同与否。
- WORKSPACE-02：Host浏览目录、cancel、read失败retry、新建folder、adopt幂等、rename同名拒绝、remove注册确认不删文件、排序与membership顺序、pin/archive/restore全部可达；preset兼容blank复用且连续点不堆。
- WORKSPACE-03：baseline成功2项、empty成功0项、初始pending、15s超时、auth过期、服务暂断、unsupported分别展示；保持lastGood；手动重试恢复后不需重装App；手机经过同一passkey反代身份验证。
- WORKSPACE-04：手机Back至list后无active selection高亮，wide并列仍有正确当前会话；recent缓存存在但不冒充active。
- WORKSPACE-05：逐行ellipsis开启时对应trigger/row高亮，dismiss/Back/切行清除；不触发row导航、不把target换为current chat。
- WORKSPACE-06：200字CJK、长英文无空格、emoji、RTL/双向文本、字体放大，完整title有可读layout/阅读入口；无字符串硬截断、无按钮被挤出、menu标清操作对象。
- WORKSPACE-07：Host blank true/false、无title历史、仅系统注入、子代理、当前blank、新prompt后nonblank、离开blank分别正确；列表live metadata更新无需全局refresh。
- WORKSPACE-08：管理/utility/View三类菜单分开；动作顺序/原图标/access/busy/错误/归档活动confirm/部分成功fork明确；可选export探测超时不会标“不提供”。
- WORKSPACE-09：搜ID/title/workspace/正文、取消旧query、内容与本地重复、归档filter、pinned稳定排序、attention超watermark、大字体滚动；token streaming期间list source不反复reload。

## 11. 推荐实施顺序（spec完成后）

1. 修正typed connection状态、诊断分类与错误传播，拿到可观测基线；同步修工作区“异常→200false空集”合同。
2. 引入HostScope/WorkspaceStore/route active身份，single-flight恢复与snapshot/projection完整性；保留现有正确Origin和不自动重发。
3. 消除6份文本表示、O(N²)索引与全历史token投影，做合成/真机性能验证，不先加更多loading动效。
4. 默认真实workspace分组、菜单目标高亮、Back选择、完整title与官方排序/search/目录操作。
5. 请求回执对账、冷/热缓存/前后台/认证/大历史矩阵；再对外宣称修复。远端升级可用只是前提，不代替手机链路验收。

## 附录：纯合成复现方法

在仓库 `gateway/` 为工作目录，通过 `node --input-type=module -` 标准输入执行下列代码。它只读取源码、在内存生成非私人夹具，不写文件、不访问服务或设备；输出随桌面负载可变，应重新采样而非硬编码报告数字。

```js
import fs from 'node:fs';
import vm from 'node:vm';
import ts from 'typescript';
import { performance } from 'node:perf_hooks';
import { normalizedHistory } from './src/native-protocol.mjs';

const text = 'x'.repeat(100 * 1024);
const record = [{ type: 'event', event: { seq: 1, time: 1,
  type: 'assistant/message', surfaceOp: 'append', data: { turn: 1, step: 1,
    message: { content: [{ type: 'text', text }] } } } }];
console.log({ upstreamBytes: Buffer.byteLength(JSON.stringify(record)),
  nativeBytes: Buffer.byteLength(JSON.stringify(normalizedHistory(record))) });

const dir = '../harmony/entry/src/main/ets/services/';
const modules = new Map();
function load(name) {
  if (modules.has(name)) return modules.get(name);
  const module = { exports: {} }; modules.set(name, module.exports);
  const output = ts.transpileModule(fs.readFileSync(dir + name + '.ets', 'utf8'), {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS }
  });
  vm.runInNewContext(output.outputText, { module, exports: module.exports,
    require: id => load(id.slice(2)) });
  return module.exports;
}
const { NativeMessage } = load('NativeSessionModel');
const { nativeTranscript, nativePresentTranscript } = load('NativeTranscript');
const { NativeChatPreferences } = load('NativeHostSettings');
function fixture(turns) {
  const rows = []; let seq = 0;
  const add = (turn, role, eventType, body = '', extra = {}) => rows.push(
    Object.assign(new NativeMessage(), { id: 'event-' + seq, seq: seq++, turn,
      step: 1, role, eventType, text: body, time: seq * 10,
      sourceKind: role === 'user' ? 'user' : '', ...extra }));
  for (let turn = 0; turn < turns; turn++) {
    add(turn, 'turn', 'turn/start');
    add(turn, 'user', 'user/message', 'query');
    add(turn, 'assistant', 'assistant/message', '', { reasoning: 'inspect' });
    add(turn, 'tool', 'tool/call', '{"path":"fixture.txt"}',
      { phase: 'start', callId: 'call-' + turn, toolName: 'read' });
    add(turn, 'tool', 'tool/result', 'body', { phase: 'result', callId: 'call-' + turn });
    add(turn, 'assistant', 'assistant/message', 'reply');
    add(turn, 'turn', 'turn/end', '', { outcome: 'completed' });
  }
  return rows;
}
const pref = new NativeChatPreferences();
pref.mode = 'detailed'; pref.foldedReplies = 'final';
for (const turns of [25, 50, 100, 200, 400, 800]) {
  const rows = fixture(turns); nativeTranscript(rows, false);
  const samples = [];
  for (let run = 0; run < 5; run++) {
    const start = performance.now();
    nativePresentTranscript(nativeTranscript(rows, false), pref, new Map());
    samples.push(performance.now() - start);
  }
  samples.sort((a, b) => a - b);
  console.log({ turns, records: rows.length, medianMs: samples[2],
    runtime: process.version, scope: 'desktop pure projection only' });
}
```
