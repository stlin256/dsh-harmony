# DeepSeek Harness 扩展交互 inventory

本文件为鸿蒙交互 spec 提供实际入口、状态、操作和传输证据。它描述上游，不表示当前 App 已实现这些功能。源码基线统一为官方仓库 <https://github.com/deepseek-ai/deepseek-harness> 的 `f3803c96974ad4a94195fb97e5c637e9c2a3afe3`。以下路径均相对此 revision；阅读方式为本机官方 clone 的 `git show`，未启动 GUI，未修改上游。

## 0. 对首轮会话菜单审计的重要补全

上游有三处不同用途的省略号，不能混为一个页面：

1. 左侧 Session 行的菜单：置顶／取消置顶 → 重命名 → 分支 → 归档／恢复 → 复制 Session ID。见 `ui-workspace/src/client/index.ts:317`。
2. 会话标题右侧 utilities 的更多操作：**复制会话为 Markdown → 下载日志 → 反馈（反馈服务可用时）**。这是 `packages/session-query/session-log-export/src/client/HeaderAction.tsx:45` 的实际内置菜单，注册在该包 `index.ts:69`。复制 pending 时只禁用 copy，下载 pending 时只禁用 download；选择后先关闭菜单。此前仅阅读 `ui-*` 模块容易遗漏它。
3. View 标签栏末尾的更多视图：收起的 View（当前项勾选），随后浏览更多插件（可用时）、创建你的插件。View owner 虽提供 pin 回调，官方默认 `ui-entry-customization/src/client/EntryMenuContent.tsx:35` **不消费该回调，不显示 Pin/排序**。首轮工作区报告里“更多视图可固定”应按本条修正。

模型、权限、plan 属输入框；jobs、subagents、schedule 各有独立小入口；不能把它们堆成大号“更多配置”页再称为官方逻辑。

### 0.1 Header utilities：导出与反馈的精确契约

`packages/session-query/session-log-export/src/routes.ts` 声明两条 exact Fetch 路由。浏览器使用去掉开头斜杠的文档相对地址以兼容应用base path；native通过本实例基地址解析同一路由，不拼接到任意外站：

| 操作 | 请求 | 格式与行为 |
| --- | --- | --- |
| 复制会话为Markdown | `GET /api/session.markdown?sessionId=<URLSearchParams编码的ID>` | `text/markdown; charset=utf-8`，整份committed逻辑历史，不限当前客户端加载窗口；native clipboard写`text/plain` |
| 下载日志预检 | `HEAD /api/session.export?sessionId=<编码ID>&includeDescendants=true` | 成功后启动同URL的GET；HEAD返回与GET同状态/headers而无body |
| 下载归档 | `GET /api/session.export?sessionId=<编码ID>&includeDescendants=true` | `application/zip`，`Content-Disposition: attachment; filename="dsh-session-<safeID>.zip"`，Host流式生成 |

Markdown标题来自同快照最新`session/title`，可附真实物化Session file路径；人类用户为blockquote、最终assistant为正文、中间assistant/tool活动为details。仅append消息，省略reasoning/system/developer/非user source注入/request/runtime；fork前缀一次，压缩不删原历史；附件仅可读label，不带bytes或认证链接。只选中Session与继承前缀，不串入child日志，尾部恰好一个换行。不能在App通过角色文本临时拼出近似版冒充官方export。

ZIP依赖sessionQuery、sessionPersistence、attachments；导出前flush活跃根会话。根日志用该generation规范名（v0 `session.jsonl`，其他 `session.vN.jsonl`）；child在`subagents/<safeID>/`下同名；图片在`media/`，通用附件在`files/<digest-prefix>/<digest>/<name>`且有界流式压缩。它包含原始日志，不能套聊天过滤去删除系统记录。默认DEFLATE level6。native下载需保存完整二进制，不能先UTF-8解码。

**认证与权限**：Connection前置Host/Origin trust及browser/API认证（`packages/client/connection/src/rpc-host.ts:128`）；exact Fetch路由绕过普通Gateway资源判定，因此该文件`:215`至`:222`明确**只允许owner principal**，其他peer403。浏览器已认证owner与新API peer区别不可忽略。native plugin代理不能以“已安装插件”绕开这个门槛；只可携带本实例授权cookie/身份并继承Host拒绝。上游header没有独立capability查询或access hook，插件被装配才有入口与路由；App若要gating需明确协商，不以虚构`session/export` Remote推断。

**失败**：缺/空sessionId400，missing Session404；Markdown缺sessionQuery或读取失败500（sanitized message）。ZIP缺依赖500，flush/read失败500，includeDescendants只接受true/false。route未注册为404，未认证401，non-owner/trust拒绝403。native应将HTTP失败分类为短提示/重试，不把HTML登录页复制成Markdown或保存成zip；成功格式也应核对。

**操作状态**：Markdown在整个plugin实例只一项pending，后点请求加入第一项，不能把复制目标中途换成另一个Session；关闭scope/插件中止读取且阻止晚写clipboard。ZIP每Session一项pending；progress dialog有preparing/success/error，关闭仅dismiss不取消，后续完成不重新弹。浏览器“success”表示启动下载，不证明归档GET完整落盘，native保存可用自己的传输状态明确完成。

**反馈来源**：`ui-message-feedback/src/client/index.ts:85`提供`ctx.feedbackUi.openSession(sessionId)`，目标为`{kind:'session'}`。Header插件在`src/client/index.ts:48`动态inject该服务，存在才显示反馈；点选只关闭menu并打开已有Session feedback draft，不提交、不下载。Message rating用messageFeedback，Session feedback独立走sessionFeedback。当前native如果尚无完整feedback form，应记录为待实现并隐藏该项，不指向仓库issues或伪装为已提交反馈。

**源码定位**：`session-log-export/src/client/{HeaderAction,controller,copy-controller,Dialog}.ts[x]`、`src/index.ts`、`src/markdown.ts`、`src/archive.ts`、`src/routes.ts`；`ui-message-feedback/src/client/index.ts`。

## 1. 所有右侧内容共用的容器规则

**入口**：会话 header corner 的展开按钮；文件链接、工具行号引用、文件树、计划/产物/提醒打开动作，统一经 `sidebarRight.openResource` 或 `openTab` 导航。没有会话时不画展开按钮。

**状态**：每 Session 一份布局与 tab identity、选中项、分栏比例、浮窗矩形、push/fullscreen 呈现。内容参数、字节、网络连接不放进持久布局。相同资源 `(kind,contentId)` 默认聚焦现有 tab；普通 page 只在目标 pane 内去重；`multiple` 的 terminal/browser 可独立创建。每个 occurrence 有独立 abort 生命周期。

**动作与转移**：展开、收起、切 tab、切 Session 不等同关闭；显式关闭/替换才触发资源清理 handler。窄于 768px 打开右栏自动全屏，退出这种全屏即收起。普通与全屏使用同一内容树，不重建正文。关闭最后一个非 guide 的停靠 tab 会收起整栏；唯一 guide 不提供 tab close。资源再次打开可携带 line/index 等导航参数，旧导航晚到不得抢回新内容。

**契约/源码**：`packages/client/ui-sidebar-right/README.zh.md` 的 Presentations、State、Tab domain、Controller；`src/client/service.ts`、`contract/slots.ts`；布局纯函数属于 `ui-dockkit`。分栏、拖拽浮窗是桌面布局能力，手机可将它们映射为内容页导航，但须保留内容身份、关闭清理、返回路径和跨 Session 隔离。

## 2. Trajectory：事件账本与检查器

**入口**：`conversation.view`，id `trajectory`，order 10，非工具调用折叠组。工具 Inspect 可请求该 View 并定位 call。

**状态**：完整驻留快照、React 当前窗口、turn/assistant 折叠、search query、timeline selection、选中记录、duration/time 显示、history loading。初次派生尾部 50 个 target node，显露更早驻留内容后才请求前页。虚拟化只挂可见行；追加保持稳定键，内容 delta 不重建滚动结构。

**动作**：搜索当前可见窗口；展开/收起全部或单个 turn/assistant；选记录打开局部 inspector；选时间区间筛选其间有活动的记录；时间域缩放/平移；加载更早。流式跟随尾部，用户上滚后暂停跟随。Inspector 分别展示 overview、input/code、output、timing、原始内容，run_code 可代码/JSON切换、换行、源码复制；正文保留记录顺序、附件、图片，不以当前工具目录重写历史。

**正确性约束**：进行中记录只有已知开始点，不伪造持续时间；请求完成不代表 tool/turn 结束；TTFT 需要已记录 step start 与首 token，吞吐需真实用量。轨迹是只读投影，允许审计上下文和注入记录；聊天隐藏系统注入的要求不能通过删掉原始历史实现，否则 Trajectory 失真。

**契约**：共享 Session events/page 与 `session.loadOlder()`；精确实时结果用 `toolResults.watch({sessionId,seq},signal)`。返回 `{available:false}` 与 `{available:true,value:null}` 有区别。原始最终工具值仅活跃 Host 实例内存保留；恢复、fork、冷历史不伪造该值，失效时仍可看 durable rendered output。只为当前选中 result 打开流，退出 result pane 即释放。

**源码**：`packages/client/ui-trajectory/src/client/index.ts:90`、`TrajectoryView.tsx:35`、`:134`、`:508`、`watch-tool-result.ts`、`types.ts`；`trajectory-*-definition.ts`；包 README 的 ledger/inspector 规则。

**手机适配**：横向 overview 可触控缩放和区间选择，inspect 成为全宽二级页，关闭回原 ledger 位置；不能用“原始 JSON 全屏文字”代替结构化 inspector，也不能让手机手势触发虚构模型动作。

## 3. Files：Host 工作目录树

**入口**：右栏 guide 的 files 卡片（order 10）及 `workspace.files` command，打开/聚焦当前目标 pane 的 files page；不认领 file resource。

**状态**：每 tab 的 root、每 absolute path 的 loading/ready/failed level、expanded、autoRefresh、scrollTop。root 是 Session 的 cwd；没有 cwd 时显示简短空态。

**动作**：目录展开/折叠、手动刷新、打开文件预览。directory 在首次展开 list，再次展开重新读并恢复仍存在后代；折叠保留已显示缓存并关闭不可见目录 watchers。刷新保留树，不清空为整页 spinner。排序目录优先，再按不分大小写自然名；dotfiles 正常显示；other 灰显不可点。截断、空、not-found/outside-workspace/not-directory 各有语义。

**契约**：`workspaceFiles.list(sessionId,absolutePath,signal)` 与 `workspaceFiles.changes(sessionId,path,signal)` 直接子项监听。文件通过 `fileAddressFor` 生成 `dsh-resource://file/session/...`；不把手机路径拿去当 Host path。

**源码**：`packages/client/ui-sidebar-files/src/client/index.ts:61`、`:81`、`definition.tsx`、`FilesBody.tsx`、`face.ts`、`directory-node.ts`、`store.ts`；Remote `packages/api/workspace-files/src/index.ts:303`、`:340`。

**上游边界**：没有文件搜索、重命名、删除、拖动管理或多 root；手机新增这些能力须独立 spec，不得伪装已有官方动作。

## 4. Document Preview：文件查看与格式切换

**入口**：file resource，fallback kind `text`。同 basename 不代表同一文件；身份包括完整 Session address 与 path。Host 返回的 absolute path 用于头部，长 path 保留尾部、完整值可查看。

**状态**：每 tab 的 text pages/bytes、版本、read/observation failure、pending changes、renderer、wrap、scroll、导航 revision。loading modes 为 text-pages、bytes-complete、renderer 自主加载。选择仅一个 renderer 时不画无意义菜单；只有声明 wrap 的 renderer 显示换行开关。

**动作**：选 renderer、换行、load more、手动刷新、自动刷新、跳行、查看图片/PDF缩放、可选 Host 原生应用打开。page 版本变化则从头重读，避免混合版本；晚失败保留已读内容并提供局部 retry。刷新保留滚动偏好并作废旧 request。

**格式矩阵**：

| 类型 | 展示与交互 |
| --- | --- |
| 纯文本/Markdown/代码 | 累计分页前缀；末尾或按钮读下一页；代码高亮/行号/换行；Markdown本地图片经已认证文件读取，保留顺序 |
| 图片/SVG | 静态图片上下文；fit width、实际尺寸、缩放、超出视口时平移；SVG不注入父DOM；动画图缩放不重建 |
| PDF | 全字节、页阅读、文本选择、fit/percentage zoom，保持文档原色 |
| Word/PowerPoint | Host officeToPdf 转换，再复用PDF；未装服务、转换失败、缺字体分开呈现 |
| 表格 | 浏览器内工作表/表格查看；由Excel renderer拥有格式与写入逻辑，不可把它误称只读文本 |
| HTML | coding-tools偏好决定静态清理或脚本sandbox策略；不授予父应用源与Host读文件能力 |
| 未支持二进制 | 明确unpreviewable，不发送无意义文本read；可用时给Host原生打开 |

**契约**：`workspaceFiles.stat`、`read(sessionId,path,{offset},signal)`、`readBytes(sessionId,path,{},signal)`、file ResourceGroup changes；Office 有独立转换/缓存 generation。bytes 从不进入持久布局或Session JSONL。外部URL和本地关联资源不能混用认证cookies。

**源码**：`packages/client/ui-sidebar-documentpreview/src/client/index.ts:93`、`:97`、`:127`；`rpc.ts`、`TextPreview.tsx`、`document/contract.ts`、`office/`、`excel/`、`html/`、`pdf/`、`code/`、`image/`；Host `workspace-files/src/index.ts:233`、`:257`、`:290`。

**手机适配**：顶部控件随空间折叠，正文全宽，图片/PDF触控缩放；无hover设备缩放控件常显；返回恢复原文件树/对话位置。浏览格式与修改表格要明确区分，不能因为原生无renderer就显示空白页。

## 5. Browser：HTTP(S) 页签

**入口**：guide 的浏览器、`browser.new`，以及 Chat 链接偏好“应用内侧边栏”。Web profile 默认禁用，Desktop默认启用；能力存在才展示，不是所有DSH实例必有。

**状态**：每 tab 控制的url/history/index、empty/loading/known/unknown navigation、failure、restoreTarget、sandbox临时状态。保存标题/url不等于自动恢复页面；启动仅展示恢复入口，用户 restore/reload 才导航。

**动作**：前进、后退、刷新、输入地址、外部浏览器打开；Web逐tab sandbox切换。缺scheme补HTTPS；接受HTTP(S)/loopback，拒绝file/javascript/data/blob、内嵌凭据、DSH应用自身origin与畸形地址。每次guide/委托链接打开新独立Browser tab。

**载体边界**：Web iframe跨域导航后可能只知道unknown；这时禁用前后退和外部打开，刷新回最后受控URL，不能显示未经观察的真实URL。Desktop使用受限webview与原生history。浏览内容不进入模型context。

**契约/源码**：`ui-sidebar-browser/src/client/index.ts:43`、`:74`；`browser/BrowserController.ts:12`、`:94`、`:183`，`BrowserPersistence.ts:8`、`BrowserFrame.ts`、`browser/url.ts`、`pages.ts`、`electron/`。

**手机适配**：Harmony独立Web载体可改善URL可观察性，但这属于载体实现；认证隔离、Host地址拒绝、手动恢复、关闭清理应保持。不得让外站获得DSH网页bridge。

## 6. Terminal：用户交互式终端

**入口**：guide新终端主按钮，旁边arrow选择已安装shell；`terminal.new`。主按钮打开最近且仍可用shell，菜单打开才查询shell，查列表不分配进程。终端类型multiple。

**状态**：environment、Host terminal id、creating/connecting/connected/disconnected/failed/closed、running/exited/failed进程状态、writable、snapshot/output序号、ack及input window、exit code。tab identity与Host identity独立保存；折叠/切页保留进程。

**动作**：原样输入Tab/控制字、resize、双击标题rename、接管输入、reconnect、退出后新建、显式close结束进程。断线保留screen；退出/恢复失效不自动重启，不偷偷新建shell。close tab立即移除，cleanup后台持久重试；未保存layout的Host进程不自动制造恢复tab。

**契约**：`terminal.environment/shells/list/create/retain/attach/rename/close`。attach双向流首snapshot，再ordered output/state/ack；write/resize每attachment sequence从1连续编号，ack不是重放授权。Host错误区分 unavailable、control-unavailable(read-only/not-running)、limit-reached。用户terminal权限独立于Agent权限，终端输出不进入Agent对话。

**源码**：`ui-sidebar-terminal/src/client/index.ts:54`、`:75`、`:86`；`TerminalGuide.tsx`、`terminal.tsx:24`、`:46`、`:60`、`:106`、`:176`；`api/terminal-controller/src/index.ts:118` 至 `:241`、`types.ts`、`src/client/model.ts`。

**手机适配**：需PTY终端仿真而非普通TextArea；系统键盘+可达的Ctrl/Tab/Esc辅助键；只在可见可写时按安全区/键盘尺寸resize。未实现完整仿真不能标记与官方terminal等价。

## 7. Plan：模式徽章、审批、历史计划

**入口**：`/plan`/加号命令菜单进入；`conversation.input.plan` chip退出；pending plan review自动打开预览；完成turn尾部计划产物卡片可再次打开。

**状态**：Host `plan` projection的active/pending，effective target为pending时反转active；leaving/error只用于操作展示，不自作主张确认退出。Review按callId或requestKey身份在当前浏览会话只自动打开一次，关闭后不因remount再弹。计划历史和回答审批独立生命周期。

**动作**：点击chip执行`commands.execute(sessionId,'/plan off',[])`；失败保留chip与短局部错误。查看全文不等于批准执行。历史计划按每次调用分别保留，重复打开聚焦已有tab；无callId的临时review正文不持久化，刷新失效需回pending review。

**契约/源码**：`ui-plan/src/client/index.ts:63`、`:65`、`:79`、`:97`、`:116`；`PlanModeControl.tsx:19`、`PlanCard.tsx:43`、`:72`；`plan-resource.ts`通过`session.events/page`找到精确调用参数；`dsh-resource://plan/**`与`plan-review/**`；审批answer入口由ui-user-questions拥有。

## 8. Goal：持久目标与当前激活

**入口**：composer dock，顺序Todo之后、Queue之前；`/goal`创建来自Host命令，本UI条带不创建goal。持久命令还投影成右对齐Command input气泡，不伪造user/message或turn。

**状态**：durable goal id/revision/objective/phase与进程local armed/disarmed activation分开。loading、无goal、complete、成功clear隐藏；active+armed显示pause；active+disarmed/paused/blocked显示resume。

**动作**：InlineEditor编辑（保留多行）、pause/resume/clear；busy single-flight同步防同帧连击，失败保留草稿与局部error；每次调用读取当前id+revision作为CAS ref，旧activation read不得盖新event。清除成功先抑制条带等projection追上。

**契约**：`goals.get(sessionId)`、`edit(sessionId,ref,{objective})`、`pause/resume/clear(sessionId,ref)`，订阅`goal/activation-changed`、connection reset与running变化。活跃状态读取等待历史open成功并临时retain，结束释放。

**源码**：`ui-goal/src/client/index.ts:102`、`:122`、`:132`；`GoalBar.tsx:42`、`:61`、`:129`、`activation-source.ts`、`goal-command-input.ts`；Host `packages/goal/goal/src/index.ts:278`、`:330`、`:353`、`:365`、`:434`。

## 9. Jobs：后台运行与输出观察

**入口**：`conversation.session.header.actions`的job-list，order20（preset/subagent之后）。该会话没有job时不渲染空控件。

**状态**：唯一roster `JobView`含running/stopping及终态、startedAt/finishedAt、progress/detail、retained output bytes。进行中优先；已结束组有运行项时默认折叠，无运行项默认展开；清空已结束只是客户端隐藏，不调用Host删除。

**动作**：展开运行中或有保留输出的结束job；展开打开observe，收起/关闭菜单即停流。无输出结束job静态呈现。running提供两击停止：idle→armed，3秒内再击→pending，失败短暂failed（4秒）后复位；成功HTTP返回仍等待roster状态变化，不给重复kill。

**输出**：固定高内部滚动、命令/输出可换行；复制命令不复制输出；缺口与断流局部提示。elapsed只为live每秒更新。

**契约/源码**：`ctx.jobs.watchRows/observe/kill`对应Host namespace单数`job`的`list/follow/kill`。`ui-jobs/src/client/index.ts:35`；`JobListAction.tsx:64`、`:170`、`:337`、`:430`；`api/job-controller/src/index.ts:59`、`:75`、`:90`、`:109`。

## 10. Schedule：自动化管理、会话时钟、turn尾卡片

**入口族**：全局sidebar的“自动化任务”(`main` id schedules，order10)；session header utilities的时钟(order-5)；`schedule_create`完成后turn尾卡片(order20)；Session行的空闲时钟标记；任务右栏tab。

**全局状态/动作**：默认已开启，可筛已结束/全部；搜索stored title、instruction、sessionId。新建打开新会话，由模型创建任务，列表没有直接创建表单。选任务默认规则tab；同任务刷新保留所选tab。详情有规则/运行记录、关联会话、更多菜单delete；关联会话只有元数据ready、存在且未归档可点，浏览不会激活/取消归档。

**规则编辑**：活动任务编辑title/instruction/timing草稿，结束只读；dirty才显取消/保存栏；失效刷新不覆盖dirty；取消回权威值，保存失败留草稿。完整预期record+change做compare-and-update，冲突刷新后再重试；未知写状态与读取失败分别呈现，不自动重发。

**时间控件**：daily、weekdays、weekly、固定小时/分钟/秒间隔、once、cron；固定间隔至少60整秒。date月历、time三列24h时分秒、可搜索timezone；保留存储IANA时区与未编辑毫秒，不能按语言猜所在地。手机不自动聚焦timezone搜索。

**运行记录**：进入records才拉最新20条；更早按cursor追加，保留前页/失败重试，invalid cursor给刷新；展示旧记录真实prompt，不以当前instruction补写历史；新latest message刷新最新页但不切tab。delivery完成不等于模型任务完成。

**删除**：确认后硬删除任务及delivery history，保留原session与已入队消息；最终结果由应用级toast跨页面播报。清理全部结束任务亦需确认并显示数目，unknown-state不伪成功。

**会话入口**：首次未读完不显示时钟；成功空结果隐藏；刷新保留last known；读取失败保留可retry入口。仅1条直接打开详情，其他数量弹紧凑列表，逾期优先再按next target；每行打开/删除。页面宽度约束到viewport，不能溢出。schedule标记只在idle且未归档时出现，不能覆盖pending/running/unread completion。

**卡片**：先从该call持久化result收窄完整record，turn结束后显示stored title/frequency/open；之后成功目录read才可改随当前状态或标已删除，不能因读取中暂时空数据闪成删除。

**契约/源码**：`ui-schedule/src/client/index.ts:104`、`:110`、`:141`、`:184`、`:196`、`:217`、`:236`；`TaskManagerPage.tsx`、`TaskDetail.tsx:38`、`:159`、`DeliveryHistory.tsx:70`、`ScheduleCatalogAction.tsx`、`catalog-source.ts`；Host `schedule.catalog/list/update/delete/deleteInactive/history`，订阅`schedule/changed`与reset。资源access允许catalog才注册管理面，session/list另独立检查。`packages/schedule/schedule/src/index.ts:298` 至 `:408`。

## 11. Subagents：目录、谱系、继续会话

**入口**：header actions子代理数量(order10)，ancestor breadcrumb切换，目录行尾aside箭头，`@`引用；普通session列表隐藏子会话。

**状态**：共享`subagentCatalog/subagent/subagentTiming/tokenUsage` projections；仅根有成员或error才显示trigger；缺席/成功空隐藏。目录展开后才刷新嵌套层，不用打开菜单就重复fetch根。外部mode是不可打开leaf；unknown仍可读history，确认模式前read-only；migration-required可打开，不扩下级。

**动作**：点击目录固定、outside/Back关闭；桌面hover150ms开/离开120ms关。tree展开/折叠、局部retry、打开主会话或aside；地址始终`{parentSessionId,childSessionId,mode}`，不能用label查ID。one-shot永只读；continuable且确切parent在时普通composer可向FIFO inbox发后续prompt，Stop单独路由。parent offline且child idle为只读；child仍running则禁Send但保留Stop。

**契约**：session projection刷新；继续`subagents.prompt`，中断`subagents.interruptByParent`；aside `dsh-resource://subagentchat/session/<child>?parent=...&mode=...`保留自己的reference，tab关才release。`@label`仅引用，不授权continue。

**源码**：`ui-subagent/src/client/index.ts:37`、`:60`、`:82`、`:94`；`SubagentHeaderLineage.tsx:203`、`:440`、`:572`、`:617`；`SubagentReadOnlyComposer.tsx`、`sidebar-chat/index.tsx`；Host `packages/subagent/subagent/src/index.ts:449`、`:518`。

## 12. Workflow Run：持久运行层级

**入口**：Chat独立`workflow-run`节点，不等同普通工具结果预览。

**状态**：run→phase→实际start的members；running/completed/failed/cancelled/interrupted。member settle不删条目或改顺序。completed默认折，异常/运行默认展；异常首次出现自动展开一次，正常完成自动折一次，但焦点在内容内则延迟到blur，避免内容突然消失。同phase有新member重新running会重新展开。

**动作**：run/phase disclosure；只有member和child均running、child.parent匹配当前session且身份projection可用时才可打开child；external不生成本地会话动作。无取消/retry控制，无脚本/输出/拓扑编辑页。

**契约**：durable `tool-workflow/run-start`、`agent-start`、`agent-end`、`run-end`按runId归并；start前的update先pending，补页后确定性归并。普通step/turn完成不意味着后台workflow结束；只有崩溃interrupted/fork边界可使缺end的运行显示interrupted。

**源码**：`ui-workflow-run/src/client/index.ts:27`；`workflow-definition.ts:12`、`:158`，`WorkflowRunPanel.tsx:72`、`:183`、`:351`。

## 13. Slash commands：声明驱动的输入流水线

**入口**：键入`/`与composer加号同菜单。空query有添加（file/goal/plan/feedback）和指令（compact/permission/model/export等）分组，按稳定definitionId本地化，不以名称猜命令语义。查询以name/title模糊子序列匹配，去分组heading。

**分派状态**：Host descriptor带input为leadingInput；客户端popupSelect/action装饰只认裸调用；其余execute。空格matchSpace读ready cache，Enter matchEnter等目录。catalog失败明确拒绝，不能静默降级成普通prompt。leadingInput草稿恢复只claim，不执行。命令与skill同名时命令优先。

**动作**：popup options load/search/group/当前勾选/选择/确认/retry；desktop聚焦search，手机手动聚焦；返回先退出popup/claim再回composer。目录reset或显式dismiss中止options且保留草稿，晚结果不重新打开。带附件只允许descriptor明确`input.attachments`，拒绝保留全部草稿附件并短toast。

**契约**：`commands.list(sessionId)`、`commands.execute(sessionId,line,attachments)`，目录按capability/session缓存；`commands/change`、preset selected与connection reset失效。临时retain等待session history打开再fetch。popup `searchMode`默认substring(label/detail)，/model显式fuzzy-label；两者不是统一一个误差匹配。

**源码**：`ui-commands/src/client/index.ts:64`；`service.ts:101`、`:125`、`:220`、`:304`、`:423`；`contract.ts`、`directory.ts`、`resolution.ts`、`popup.ts`、`PopupSelectView.tsx`、`presentation.ts`。

## 14. References：文件、目录、会话的原子引用

**入口**：`@` source，未引号token并行发现files与sessions；`@\"...`只file。结果顺序files→当前直接subagents→其他sessions；某域失败不抹掉另一个成功域。

**状态/动作**：file pick插原子引用，保留规范`@path`或quoted剪贴板形式；directory主行/Enter选目录本身，Tab/chevron保持可编辑path并下钻，breadcrumb可回上级。session pick保存Host规范`@[label](dsh-session:...)`身份，不能按可见title重建。文件引用可打开当前内容预览，失败局部retry/close；folder/session标签不冒充文件按钮。

**契约**：`fileReferences.list(sessionId,query,signal)`与`sessionReferenceResolver.candidates(sessionId,query,signal)`；wait session open并临时retain/cancel。发送保留mention，由Host pre-step验证和捕获context；候选查询不激活目标或修改模型上下文。

**源码**：`ui-reference/src/client/index.ts:73`、`:90`、`:131`、`:164`、`:235`、`:264`；`user-text-rules.ts`、`FileReference.tsx`；共享`ui-input-trigger`管理caret/token/claim与候选生命周期。

## 15. Permissions：当前会话与未来默认值

**入口**：composer `conversation.input.permission`、裸`/permission`popup、settings.general默认行。三者不能混成一个全局开关。

**状态/动作**：当前controls需要session permissions projection与完整process catalog；只读/工作区写/完全权限/可选Auto由Host动态提供。visible Full Access和Auto各有明确确认；显式带参命令直接执行。custom是展示态，不是目标。catalog撤销/代际变更关闭陈旧confirm与slash choices、保留草稿，已提交请求仍等返回。

**契约**：共享`permissionPresets.catalog()`；current通过`commands.execute('/permission <id>')`且projection确认；未来默认从configForms permission descriptor动态enum推导，经revision `settings.mutate`单路径写，绝不改当前session。Auto只可当前会话，不当未来default。

**源码**：`ui-permission-presets/src/client/index.ts:144`、`:169`、`:177`、`:186`；`catalog.ts`、`PermissionSelect.tsx`、`PermissionRow.tsx`、`settings-store.ts`；订阅`permission-presets/catalog-changed`与真实connection generation。

## 16. Skills：调用、预览和回放稳定的工具卡

**入口**：`/`候选skill source(order2)、手输`/name`、输入/已发引用点击查看SKILL.md；工具`skill`专属行。

**状态/动作**：候选按普通session single-flight缓存，等待history open；preset切换只清该session，插件变化/reset清全部；失败不毒化cache。选择插入字面`/name `并发同样prompt，Host确定性注入正文，不能在手机先把skill文件粘成大prompt。用户可调用但model不可调用的条目仍显示，并有user-only描述。

**工具展示**：preparing仅glyph+title不可展开且不查询当前目录；start/result使用冻结record参数与输出；settled展开Instructions卡，保留原始输出、失败首行/中断语义，可Inspect。重装或修改skill后历史卡不改变。地址模式subagent不发会激活它的skill list。

**契约/源码**：`skills.list({sessionId},signal)`；`ui-skill/src/client/index.ts:89`、`:115`、`:167`、`:205`、`:224`、`:249`；`SkillRow.tsx`、`SkillReference.tsx`、`user-text-rules.ts`。记录工具输出与已安装目录必须分开。

## 17. 其余不能从“模块覆盖表”漏掉的产品交互

| 族 | 入口、状态与动作 | 契约和实现入口 |
| --- | --- | --- |
| Session日志/Markdown | header utilities更多；完整会话Markdown复制（单pending避免剪贴板竞态）；ZIP下载独立进度/error dialog；dismiss dialog不等于取消download；/export成功也触发下载 | `packages/session-query/session-log-export/src/client/{HeaderAction,controller,copy-controller,Dialog}.ts[x]`，`routes.ts`；使用定义常量的已认证HEAD/GET，ZIP包含descendants，不能只复制屏幕已加载片段 |
| Agent Preset | new session hero选择、session header只读label(order-10)、settings roster/default/read-only YAML/Creator；Host只在first turn前切换，已有运行会话不改composition；Creator只准备可审阅draft | `ui-agent-preset/src/client/index.ts:1/226/283`，`agentPresets.list/read`，registry settings default；coding-tools偏好会筛内置PTC/minimal，不能丢custom |
| Deliverables/Changes | completed turn tail文件产物和changed files；多交付2列、超过4默认折；点击preview；changed review选择文件/单栏左右diff/wrap/full file；记录快照不可当当前文件；关闭coding-tools只隐藏changes，不隐藏显式present | `ui-deliverables/src/client/index.ts:61`、`:84`、`:88`，`deliverables-definition.ts`、changes summary/diff stores、`ReviewTab.tsx`；`present`冻结call/result，已认证摘要和逐文件diff路由，reset清缓存 |
| Feedback | 最终assistant动作行like/dislike(order10)、/feedback、header反馈共享每Session dialog；提交才评分，同评分再点retract；failed保留draft/toast，不进入模型context | `ui-message-feedback/src/client/index.ts:98/115/137`，MessageFeedbackController/FeedbackDialogController；messageFeedback list/put/retract版本对账，sessionFeedback；完整messageId才显示 |
| Attachments | input附件卡、用户/助手/tool/trajectory共用image gallery/lightbox；已认证Session image URL缓存共用，输出顺序不重排；发送失败保留附件；图库替换不能泄漏blob/认证 | `ui-attachment/src/client/index.ts:21/24/29/35/38`，`ui-conversation`图片factory；`file-upload`是独立上传协议，不能用文件名伪装已上传附件 |
| Approval/Question/PlanReview | composer selector takeover而非普通聊天文字按钮；pending interaction影响列表状态；attach/claim与answer分离，过期request不能重复answer；审批与question显示各自专门控件 | `ui-approval/src/client/index.ts:80/94/97`；`ui-user-questions/src/client/index.ts:222/295/382/394`；`userQuestions.attachWait/answer`；细节由聊天交互审计继续展开 |
| Open In App | workspace header/files actions、document actions/unpreviewable、deliverables/review原生打开；Host没有桌面隐藏native controls但保留preview；选择的app来自Host，不是手机猜服务器程序 | `ui-open-in-app/src/client/index.ts:110/114/126/139/142`，对应controller与Host GET应用列表/POST打开或reveal；busy单文件、结果toast/可retry错误 |
| Plugins/Market | sidebar Plugins全局页；已安装/发现、详情、enable/disable、managed row config、spec preview安装、进度/log/cancel、卸载确认、更新；Host无managed profile不可用；read failure与空列表不同 | `ui-plugin-manager/src/client/index.ts:132/167`及slot-contract/face；`ui-plugin-market/src/client/index.ts:55`；`pluginManager`/`pluginMarket` Remote，profile revision与操作生命周期由Host拥有 |
| More入口自定义 | sidebar More、View More、rightbar guide More；默认footer只有browse(可用时)/Creator；Creator追加本地化请求到已有draft并保留attachments/references，不自动send | `ui-entry-customization/src/client/index.ts:54/58/62`，`EntryMenuContent.tsx:35`；`uiWorkspace.startSession` with cordis、whenDraftExists append |
| Shortcuts/Theme/Secret mask | 快捷键注册按焦点区域/modal决定可用性，手机不要套桌面Ctrl说明；theme是共享状态，document保原色；secret masking不得改变原始复制/执行身份 | `ui-shortcuts`、`shortcuts`、`ui-theme`、`ui-secret-mask`；这些是横切行为，不能仅“有设置开关”算完成 |

## 18. 实现 spec 必须写清的边界

1. **所有入口都要有归属**：session管理、header utilities、View导航、composer、turn tail、global panel、右侧content不是一个路由层级。手机可以把右侧pane改成全宽页，返回应回原surface和scroll位置。
2. **Host能力决定功能**：无对应插件/Remote/access时隐藏或给准确unavailable，不展示永远失败的按钮。自定义UI插件不是固定json字段；未知扩展需要兼容网页或明确unsupported，不能假装native支持任意第三方React slot。
3. **事件与payload要完整**：只转成role/text会失去workflow/plan/delivery/goal/reference/tool schemas。App原生渲染需保留typed event/projection契约，Chat系统消息过滤是presentation政策，不能破坏共享history。
4. **资源身份不可简化**：Session+address+call/event seq+generation必要时都要保留；相同标题、路径basename、当前Session不能用来替代identity。
5. **异步与取消是交互的一部分**：保留last good/read failure，不伪造empty；旧generation/旧query/旧tab response全部失效；写操作未知状态不自动重试。loading不遮掉所有可读缓存。
6. **手机改布局，保留状态机**：touch替代hover，触控热区可扩大，图标与行语义保持；窄屏pane全宽、长标题截断、细节二级页、键盘不自动弹。短横幅/局部retry优先，不添加教学长文。
7. **完成标准按族验证**：除模块名外，每族至少覆盖入口可达、empty/loading/ready/error、busy/取消、成功权威确认、断线重连、返回保留上下文、安全区/键盘、access未授予。缺任何族要在gap表显式标partial，不因源码存在即写done。

本报告尚不是所有扩展功能逐控件像素规范；它提供跨完整上游功能族的可追踪语义 inventory，具体实现前仍需引用对应renderer/controller/tests核对细节。
