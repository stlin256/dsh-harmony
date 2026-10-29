# DeepSeek Harness 聊天交互源码研究

研究日期：2026-10-29。范围为官方聊天、输入与运行过程，不把 Harmony 当前实现当成上游行为。本文为原生交互 spec 的证据输入，不是完成报告。

## 源码基线

- 官方仓库：<https://github.com/deepseek-ai/deepseek-harness>。
- 锁定提交：`f3803c96974ad4a94195fb97e5c637e9c2a3afe3`。研究时 `git ls-remote origin HEAD` 与本地 HEAD 一致。
- 已核实既有 clone 的 origin，复用 clone，以 `git show HEAD:<path>` 读取 sparse checkout 之外的源码，没有改变共享 checkout。
- 下文路径均相对于官方仓库。永久链接使用上述提交；上游代码和测试优先于本文概括。

## 设计骨架：不是按消息角色拼一个聊天列表

官方先把持久事件和流式片段投影成有身份的 Conversation Node，建立 Turn/Step/Call 位置，再生成过程组和可见行，最后交给具体视图。语义状态、可见性、分组、展开状态、滚动和动画相互独立。不能让一个 `tool/result` 新增一个重复气泡，也不能把同一 Assistant 的推理和回复无条件合并到一个盒子。

| 层 | 官方所有者 | 原生重写应保留的职责 |
|---|---|---|
| 日志与实时窗口 | `packages/api/session-controller/src/client/transport.ts`、`packages/api/gateway/src/client/journal-stream.ts` | seq 覆盖范围、snapshot 替换、prepend、append、独立 assistant revision、缺口修复 |
| 事件投影 | `packages/client/ui-chat/src/client/conversation-nodes/*` | 人工/上下文来源分类、Assistant 生命周期、call/result/PTC 配对、中断边界 |
| 业务可见性 | `.../contract/chat-visibility.ts:10` | 系统提示、普通 Context、permission 命令不进入聊天行；Context 的工具增删通知例外 |
| 分组与策略 | `.../conversation-nodes/process-groups.ts`、`turn-process.ts`、`presentation-policy.ts:26` | 同轮过程组、整轮折叠资格、四档呈现与偏好 |
| 原子视图 | `ui-chat/src/client/chat/*`、`ui-tool/src/client/tool/*` | 回答、思考、工具专用卡、提问、错误、运行状态、完成操作 |
| 输入事务 | `ui-conversation/src/client/input/machine.ts:33` | 草稿冻结、接纳后清空、失败保留、不重复发送 |
| 视口 | `ui-chat/src/client/chat/use-chat-scroll.ts:47`、`use-scroll-follow.ts:20` | 跟尾意图、分页锚点、折叠时定位和手势中断 |

聊天规则的官方详细说明是 [conversation-nodes/README.zh.md](https://github.com/deepseek-ai/deepseek-harness/blob/f3803c96974ad4a94195fb97e5c637e9c2a3afe3/packages/client/ui-chat/src/client/conversation-nodes/README.zh.md)。下面只转述实现所需约束。

## 1. 人工消息、Steering 与系统注入

1. 真实来源读取 `user/message.data.source.kind`，不是只读取 `data.message.source`。`user` 为人工输入；被持久 `next-step` claim 领取的人工输入为 Steering。
2. 非人工输入并非全部删除。普通上下文在 store 中保留、在 Chat 隐藏；真正唤醒轮次的 next-turn 非人工 claim 变成独立、默认收起的触发通知。空闲 next-step 的通知须符合 Step 1、已加载轮次起点、claim 在起点之后、无 next-turn claim、同批无人工输入这些严格条件。
3. 系统注入既不进入过程组，也不截断过程组。不能靠“正文里含有 cwd”删除真人消息。旧无来源记录可以另设保守兼容规则，但那不是现代官方分类。
4. 人工/Steering 使用相同右侧气泡和附件布局。source 装饰由独立插槽处理。pending 和本地 echo 不冒充持久来源。
5. 人工消息的 copy 使用文本投影；事件时间不伪造。分支必须使用真实可分支边界，不能随便以当前页面最后一个序号替代所选消息。

证据：[message.ts:81](https://github.com/deepseek-ai/deepseek-harness/blob/f3803c96974ad4a94195fb97e5c637e9c2a3afe3/packages/client/ui-chat/src/client/conversation-nodes/message.ts#L81)、`inbox.ts:85-139`、`chat/MessageItem.tsx:171`、`README.zh.md:78-85`。

## 2. Assistant、流式更新与停止

- 每个 Step 的流式、完成、打断 Assistant 共用稳定身份。文本、推理、图片按照原 block index/顺序保留。连续图片组成图库，图库身份由第一张所在 block index 决定。
- 工具调用协议块只保存工具身份，不当作回答文字，也不重复计数；工具 Node 单独拥有流入的参数。具名 delta 即可生成 preparing 工具行，block-end 只是参数结束，只有 tool/call 才代表已派发。
- 完成块替换/校正实时片段，不能把完成正文再追加一次。停止时冻结已显示的 partial，并显示停止标识；没有持久 messageId 的 partial 不提供持久消息操作。
- 推理各自可展开。收起时，已完成推理预览首行；运行中预览推进到最近完整段落的首行，去除 `**` 装饰。正文保留完整 Markdown。当前仍未完整输出的第一行不应在预览中不停抖动。
- 未知 block 不应静默丢失，官方会用保守结构化 fallback 显示。

证据：`conversation-nodes/assistant.ts:95-145,263-354`、[AssistantMarkdown.tsx:76](https://github.com/deepseek-ai/deepseek-harness/blob/f3803c96974ad4a94195fb97e5c637e9c2a3afe3/packages/client/ui-chat/src/client/chat/AssistantMarkdown.tsx#L76)、`ReasoningRow.tsx:13-97`、`TurnTailNodeView.tsx:60-100`。

## 3. 分组、整轮折叠和偏好

### 过程组

- 同一 Turn 相邻的思考/工具进入同一组；Step 变化或工具类别变化不拆组。
- Assistant 回复截断组并成为独立 response；同一 Assistant 中有思考和回复时，先投影 reasoning，再结束组，回复独立显示。
- 可见人工输入、Steering、触发通知、model-retry、turn-error/max-tokens、turn-tail/control 等真实边界拆组。另一轮或无轮归属节点也拆组。工具失败仅更新其成员，本身不拆组。
- `run_code` 与其 PTC 子调用为一棵根工具树，子调用不另产生根消息。父先子后参与摘要。
- 空白/只有协议块的 Assistant 不生成空组。`closed` 是业务上该段过程结束，与用户是否展开无关。

### 整轮控件

- 整轮控件位于开场连续输入之后。已开始过程后出现可见输入，必须保留所在位置，整轮不允许隐藏过程。
- 正常完成、已有过程、没有中途可见输入的 Turn 默认收起过程。失败、停止、运行中不支持整轮收起。
- 默认所有阶段回复和最终回答始终可见，思考属于过程。`foldedReplies=final` 时才允许连阶段回复一起折叠。
- 完成没有最终回答也可折叠过程。只有结束记录而未加载起点时可折叠已加载范围，但不伪造耗时。
- 外层关闭时重置内层组、推理、工具的展开状态；切换展示模式保留用户手动展开选择。分页新增内容维持既有组/消息身份；发现更早真实边界时重分组，而非把所有旧内容强行并入一组。
- 手动折叠先转移焦点；自动折叠若会隐藏键盘焦点，则保留过程展开。

### 四档展示（必须是同一份分组数据）

| 策略 | Compact | Standard | Detailed | Verbose |
|---|---|---|---|---|
| 组头 | 分类摘要 | 摘要及实时详情 | 运行时隐藏、历史保留 | 隐藏 |
| 组正文初始态 | 收起 | 收起 | 运行时平铺、历史按手动开合 | 全部平铺 |
| 已完成思考预览 | 无 | 首行 | 首行 | 首行 |
| 单个思考/工具正文 | 手动 | 手动 | 手动 | 手动 |
| 正常完成整轮 | 默认收起 | 默认收起 | 默认收起 | 一直显示，仅保留时长/状态抬头 |

Host 偏好为 `ui-chat.transcriptView`。已存四值直接读取；旧 normal/expanded 按 detailed 展示、不能擅自改写持久值；Desktop 默认 standard，非 Desktop Web 默认 detailed。原生属于新平台，默认选择须在 spec 中明说，不能声称官方要求 standard。

独立偏好：`ui-chat.collapseTiming=completion|next-input`（默认 completion），`ui-chat.foldedReplies=all|final`（默认 all）。next-input 在最新真人交互段完成后保留运行时呈现，直到普通新消息进入待发送态或新交互段建立；单纯排队或 steering 不触发收起。通知唤醒轮次不会误收起同交互段。保存位置是 Host profile，而非 Session 日志。

证据：`README.zh.md:70-151,201-236`、[presentation-policy.ts:26](https://github.com/deepseek-ai/deepseek-harness/blob/f3803c96974ad4a94195fb97e5c637e9c2a3afe3/packages/client/ui-chat/src/client/presentation-policy.ts#L26)。

## 4. 摘要、活动和图标

- 单组按 callId 去重；准备、运行、成功、失败、中断均计一次调用。不同父子 callId 分别计数。缺失原调用的结果不靠输出猜类别。
- 完成摘要按次数降序，同数按首次遍历顺序，最多三类，超过加“等”。不是工具成功数，不等于文件数量。
- 活动从仍运行的调用按**开始时间**取最近者，不按最近输出时间。时间相同后遍历者胜出；较新调用完成后回到更早仍运行者。没有工具时用最近运行 Assistant 的非空推理段落；组结束立即清空 live 详情。
- 类别匹配按原工具名区分大小写，不剥离命名空间：read；read_image；grep/glob/`*_inspect`；write；edit/apply_patch；bash/pwsh/exec_command/write_stdin/`terminal_*`；run_code；web_search；web_fetch；subagent/`subagent_*`；todo_write/create_goal/update_goal/get_goal；ask_user_question/request_user_input；剩余 tools。`*_inspect` 早于 terminal/subagent 前缀。
- 活动详情字段依次取：title、description、objective、task、task_name、name、question、questions、prompt、message、command、cmd、queries、query、pattern、url、uri、file_path、path、target、action、status。questions 取对象数组首个 question；普通数组必须全字符串。合并空白，限制160个**字素簇**，不是160个 UTF-16 单元。preparing 未封闭且暂无字段时保持空白，不提早工具名兜底。
- 实时组标题至少保持150ms，只保存最新待显示标题；结束摘要立即更新。图标来自官方 artwork 的业务分类图标，失败/停止也保留业务图标，状态由语义点/裁决单独表达。

证据：`README.zh.md:153-350`、`process-activity.ts`、`chat/ChatGroupSeat.tsx:28,98-127`、`ui-primitives/src/icons/artwork.ts`。

## 5. 工具原子卡片：原生实现映射

官方是 `ToolCallTree` 统一根/子节点，以精确 wire name 选择 renderer。不是“所有工具名 + JSON”。每个 callId 的 preparing/start/result 共用身份与独立 disclosure；PTC 也走同一选择路径，但专用 model 可主动拒绝缺少 metadata 的子调用。自动审核拒绝先于专用卡，使用 generic 裁决，不能显示为命令成功。

模型目录基准：`packages/client/ui-tool/src/client/tool/models/`；视图目录：`.../tool/toolviews/`。证据：[ToolCallTree.tsx](https://github.com/deepseek-ai/deepseek-harness/blob/f3803c96974ad4a94195fb97e5c637e9c2a3afe3/packages/client/ui-tool/src/client/tool/ToolCallTree.tsx)、[ui-tool/README.zh.md](https://github.com/deepseek-ai/deepseek-harness/blob/f3803c96974ad4a94195fb97e5c637e9c2a3afe3/packages/client/ui-tool/README.zh.md)。

模型入口行号：`read-card-model.ts:100`、`search-card-model.ts:82`、`diff-card-model.ts:100`、`terminal-card-model.ts:312`、`web-card-model.ts:58`、`image-card-model.ts:194`、`todo-diff-model.ts:17`、`details-card-model.ts:33`；提问视图的 `ask-question-row.tsx:98,124,214` 分别是问题校验、稳定ID配对和状态裁决入口。server到native DTO必须保留这些模型读取的原始 `meta`、`content`、原call参数和error，不能只留拼接output。

| 家族/源码 | 有效输入与专用结果条件 | 必须保留的裁决/fallback |
|---|---|---|
| read / `read-card-model.ts` + `read-row.tsx` | call.name=read，file_path 非空，offset/limit 若存在为正整数；成功根结果 meta.path/offset/lines/totalLines/lang 合法；lines.number 递增且不超 totalLines，text 为字符串；单段 result text 匹配 file envelope | 子调用、错误、缺失/错误 metadata 或 envelope 返回 null，用 generic；显示记录路径，cwd相对化后 home 缩写；聊天 preview **8行**，完整行号保持；offset 可作打开文件定位 |
| grep/glob / `search-card-model.ts` + `search-row.tsx` | pattern 正确，path 可省略但若有须非空；grep include 空字符串等同省略，其他只接受有效单 glob（花括号内逗号可接受）；成功根 meta.truncated:boolean,total:非负整数；grep shape=matches/files[{path,matches[{lineNumber,line}]}]；glob shape=paths/paths:string[] | 子调用/失败/非法 include/格式不明用 generic；truncated 保留原 result recovery locator；聊天 **8行**，不能把截断当完整结果 |
| write/edit/str_replace_editor / `diff-card-model.ts` + `file-mutation-row.tsx` | write(file_path,content)；edit(file_path,old_string,new_string,replace_all?)；str_replace_editor(create:path,file_text? 或 str_replace:path,old_str?,new_str?)；运行中展示拟议 diff；write/edit 成功读取 meta.diffs[{path,oldText:string|null,newText:string}] | 根调用专用；失败 generic；str_replace_editor 完成结果 generic；write 成功 meta.diff缺失或空可用参数全文件 diff，edit 不可；标题展示记录替换统计，不能把拟议变化称应用完成；聊天 **9行**，新增/删除语义色 |
| bash/pwsh/terminal_send / `terminal-card-model.ts` + `bash-sample.tsx` | bash/pwsh command 非空，description 非空表示标准 shell，无 description 表示 persistent；timeoutMs 若有正有限数，workdir:string，run_in_background:boolean；terminal_send(sessionId非空,text:string,submit?:boolean)；running显示command；结果须单text且非isError | 标准前台结果尾部 exit/signal marker 解析；有 spill notice 则 generic，不根据被截断文本推断退出成功；persistent完成 generic；后台terminal_send generic；后台shell成功只是job启动回执，卡片只保留command/cwd，不显示退出成功；非零/缺码/信号用中性胶囊+红点；运行cwd只接受绝对workdir，结果优先记录meta.cwd，旧根结果才回退sessionCwd；子调用可用专用terminal |
| web_search/web_fetch / `web-card-model.ts` + `web-row.tsx` | search queries非空全非空string[]；fetch url非空；成功根meta.truncated:boolean；search sources[{url,title?,snippet?,publishedAt?}],answer?:string；fetch meta.url:string,statusCode:integer | 子调用/错误/不完整meta generic；搜索显示来源和回答；fetch折叠URL仅http(s)可开浏览器；不把任意协议URI当网页打开 |
| read_image / `image-card-model.ts` + `read-image-row.tsx` | result成功，call file_path非空；根必须meta.path，子调用可回退参数；content只允许text/image，包含image envelope和完整图像引用；attachmentId非空，mediaType四种，bytes/width/height正整数，originalDimensions如有同样合法 | 引用来自result.content，meta只给路径；任一非法图像/未知block整张卡退generic，不能丢部分内容；经认证loader取bytes，禁止解析opaque attachmentId；保留额外text、原路径、像素/字节事实 |
| todo_write / `todo-diff-model.ts`,`todo-history.ts`,`details-card-model.ts:todosDetail` + `todo-row.tsx` | 成功结果，call.args.todos[{content非空,status:pending|in_progress|completed}]，content.trim后唯一；对比前一个已记录todo write | 仅比较已记录状态；无baseline或更早未加载导致baseline不确定时显示对比不可用，不能全算新增；支持新增/删除/状态改变/保留项重新排序/未变分组；任务内容照原文显示 |
| ask_user_question / `ask-question-card-model.ts` + `ask-question-row.tsx` | questions需非空、稳定唯一id、question:string；options label/description，multi_select；结果answers[{id,selected:string[],custom?:string}]；按id严格一对一，不按数组位置猜配对 | answerable由userQuestions.active决定，结果pending并不代表现在仍能答；迟到答案从settled或inbox user-question-reply获取；已发未领取只读查看；ASK_CANCELLED/ASK_ABORTED显示取消/中断且不虚构答案；未回答关闭不提供回答按钮；配对不明退generic或仅可信计数 |

通用详情另外覆盖 goal/schedule/workflow/agent/job/terminal/LSP/inspection 等记录。这些需保守白名单 parser，未知格式保留完整输入输出和 inspection 能力。官方文件 `details-card-model.ts`、`control-details-model.ts`、`inspection-details-model.ts`、`details-row.tsx`；原生可逐类扩展，不能把 generic 的存在称为所有工具专用UI已经移植。

文件打开路径优先操作结果记录的绝对目标；展示标签可以是原参数、cwd相对或home缩写。不要从当前手机文件系统打开服务器路径。手机应在原生文件预览页面呈现同一个服务器目标。

## 6. 输入框、发送、附件与队列

### 发送事务

`plain/claimed -> adjudicating（未知斜杠命令）或 submitting（已认领命令）或 sending（普通消息） -> Host接受后 plain并清空；拒绝/失败 -> 原草稿继续编辑`。

- 同一会话只有一个冻结中的 submit attempt，重复点击/长按Enter不能并发重复发。等待期间 editor 只读，显示草稿原文；失败不清空、不悄悄自动重发。异步旧 attempt 回包不得提交新草稿。
- 普通空闲发送模式为 queue。运行中默认也 queue；用户 Host 偏好 `ui-conversation.busyEnter` 可改为 steer，主发送键和 Enter 同语义；Ctrl/Cmd+Enter选相反模式。Steer窗口已关闭由 Host 转下一次唤醒队列，UI不能声称必定立刻打断。
- 正在运行、无有效草稿时主键为 Stop；有可发送草稿为 Send（按queue/steer）。可继续的子会话保持Send为主、Stop独立。发送等待中若能stop则独立提供stop。
- 未连接/不可用/被owner阻止时不可提交。权限不允许prompt/cancel/upload时不提供相应操作，而不是做一个永远失败的按钮。
- 输入支持 IME保护、Shift+Enter换行、菜单高亮优先处理Enter、命令chip、引用、session/file reference。手机以显式发送按钮作为主动作，不能让输入法候选确认发送消息。外接键盘保留官方键义。
- 外接键盘Stop双Esc需要同一会话、turn、binding generation和输入region，独立两次按键有效。手机Back负责导航，不能替代Stop。

证据：`input/machine.ts:1-12,127-174,209-241`、`input/submission-policy.ts:20-41`、`skeleton/InputBar.tsx:59-173,354-385`、`input/editor/keymap.ts:1-16,258-278`、`stop-sequence.ts:41-57`。

### 附件

- 空文本但有附件可发；已选附件的上传pending或error都阻止发送，错误需重试或删除，不能静默忽略失败附件发送剩余消息。
- 图片数量、单图bytes、总bytes、mediaTypes来自服务投影imageLimits，前端预检查与Host最终验证并存。通用文件和图片是不同类型；子会话是否支持文件由能力判断。
- 消息内图像从持久引用经授权loader加载；文件卡显示名称/bytes。粘贴/拖入/选择均进入同一附件事务。手机用系统Photo/FilePicker替代桌面drop，但保留相同验证、上传、重试和删除逻辑。
- 草稿是语义结构（text/references/command/quotes），按session持久。引用范围必须有序不重叠且文本相符，非法存储不能生造chip；只保留string会丢引用语义。

证据：`InputBar.tsx:85-118,240-274,451-467`、`draft.ts:8-112`、`skeleton/DefaultConversationViews.tsx:23-31`、`packages/client/ui-attachment/src/client/ComposerAttachments.tsx`。

### 队列与本地回显

- next-turn queue为空不渲染；1项直接显示；多项默认收起计数，编辑中或操作中保持展开。原生不应只藏在三点详情里面。
- 未接纳的本地queue submission显示sending，不允许编辑/删除/steer。按source.user.rpcId与requestId对账，Host row到来后移除echo，不双显。
- 只有纯text blocks可编辑；混合图片/文件不能转成纯文本覆盖。移除/steer使用原itemId；steer仅运行中可用。一次busy操作锁定竞争操作，失败提示并保留原行。
- transcript echo开启下一轮，排在running状态之前；当前轮待领取steering排在running状态之后，开新轮之前已有steering按claim顺序放在新输入前。顺序不能随订阅事件先后跳动。

证据：`queue/QueueDock.tsx:26-29,120-180,245-351`、`chat/ChatFlow.tsx:29-130`。

## 7. 连接、缓存、历史与视口

- 连接有 connected/disconnected/connecting。旧generation必须停止增量投递并清理，再开新generation。准备好不仅是TCP/WebSocket open，而是逻辑订阅baseline与listeners就绪。
- 官方自动恢复采用指数退避，默认cap 500ms、倍率2、最高10000ms，实际取cap的50%-100%随机；离线时暂停，网络恢复/手动重连重置退避；ready警告3000ms、hard deadline15000ms。原生可以使用同样数值，网络状态由Harmony事件驱动。
- 重连保留已发布窗口，不清空屏幕；opening page完整追到新generation cursor后才发布replace。durable seq连续性与assistant revision各自校验；缺口需要repair，不能把工具/上下文被过滤后的UI行seq当日志连续性。
- 同步只恢复日志和状态，不重放用户prompt。结果不确定的提交用requestId和服务端记录核对，不直接新建另一条prompt。
- 短横幅按用户要求统一“连接中断，正在尝试重连”。不是把一个错误文本插入每条消息。认证失效走登录，草稿保留，但清除其他账户的授权缓存。
- 运行尾部为whale+状态/用时；真turn起点到达前不显示猜测时长。每秒更新，最小1秒，满60分钟显示小时；断开/重连冻结最后用时，恢复重新按起点计算；停止bit先到而turn/end稍后时暂保留隐藏槽位，避免尾部缩跳。
- 自动跟尾是用户意图，与当前位置区别处理；用户阅读手势中断自动动画，内容增长不把读旧内容的人拖到底部。自己的新输入可重新跟尾，其他客户端新输入不能抢阅读位置。
- 加载更早时锚定按钮下的第一个**可见业务内容**：收起组取组头，打开组取第一可见成员，跳过turn-process控件/隐藏/空行。新增记录放其上方，保留原位置；限高组先消化内部位移，余量外层补偿，不凭空增加底部空白。
- 不能用原始消息数量差推算分组后List index；分组、折叠、系统过滤和图片后加载都会改变几何。需稳定node/group/call anchor + 实际位置。

证据：[connection.ts:40-298](https://github.com/deepseek-ai/deepseek-harness/blob/f3803c96974ad4a94195fb97e5c637e9c2a3afe3/packages/client/connection/src/client/connection.ts#L40)、`connection/src/recovery-config.ts:7-35`、`api/gateway/src/client/journal-stream.ts:86-89`、`api/session-controller/src/client/transport.ts:167-205`、`chat/RunningStatus.tsx:31-62`、`README.zh.md:100-111`、`chat/use-scroll-follow.ts:70-172`。

## 8. 动效与手机适配边界

这些是**官方语义 + 明确手机转换**，不是把桌面像素放大。

- 过程折叠：官方fade70ms，关闭delay50ms+height110ms，easing(0.4,0,0.2,1)，同一viewport一次批处理。打开/关闭和阅读定位同一时钟完成，收起后不能再跳一次；新内容更新剩余运动，用户手势取消自动目标。减少动态效果直接落终态。
- 流式文字到来不为每个token重建整个气泡或整列表。运行指示跟随尾部位移不播入场动画；被领取steering换位才使用淡入遮盖间距。
- 移动保留官方颜色、glyph、标题/摘要语义、右侧人类/左侧回答、嵌套深度、卡片行上限。触控命中可扩至40-44vp，视觉行仍紧凑。不能为紧凑把完整内容永久截断。
- 横向表格、代码、终端列对齐使用局部横滚/完整阅读页；普通命令文本按宽度换行。整体页面不水平溢出。
- 键盘和安全区改变可用viewport；composer应被键盘顶起，内容只补实际composer高度与系统安全区，底部背景延伸到手势区；状态栏仍可见，遵守用户取消全屏的决定。
- 桌面右侧文件/工具inspection转换为原生详情页；Back先关闭当前详情，再回聊天，不能关闭整个设置/工作区。交互入口功能和数据目标不改变。
- Hover-only操作转换为触控可发现的icon/长按菜单；有权限/真实messageId/分支边界后才可操作。长按选择只在稳定正文上，copy/quote等应保持精确文本。

证据：`chat/flow-motion.ts:10-16,88-98,190-315`、`README.zh.md:100-111,138-145`、`InputBar.module.css:59-81,175-184,265-276`。触控尺寸、安全区、详情页是本项目移动适配决定，须在主spec作为差异记录。

## 9. 当前 Harmony 缺口（研究时快照，未视为完成）

当前未提交改动已经有精确工具分类、根/子配对、基本分组/整轮折叠、source过滤和紧凑输入框，但仍存在明确差距：

| 功能 | 当前实现观察 | 后续验收要求 |
|---|---|---|
| 工作步骤策略 | NativeTranscript基本固定standard近似；没有3个Host偏好完整状态机 | 四档+收起时机+保留回复共同控制同一node模型 |
| 工具卡 | NativeToolCallView主要raw args/output；失败用ellipsis/颜色，未保留各业务glyph | 按第5节纯model分派；原始记录保留generic安全后备 |
| source | 普通非人工过滤已加，但触发通知需要claim语义 | 隐藏Context同时保留自动化/后台唤醒等真正通知 |
| 文本 | 当前Markdown基础子集、停止/未知内容fallback较粗 | 完整引用/链接/代码/图片顺序，持久选择与完整复制 |
| 思考预览 | 当前可展开但无官方预览推进语义 | 完成首行+运行段落首行，按policy开关 |
| 草稿事务 | 发送成功后清空、失败保留已有；纯string缓存，sending锁 | 结构化草稿、requestId对账、稳定local echo、未知结果不重复发送 |
| 运行状态 | 有running bit，缺完整时钟和holding尾槽 | 真实turn time，断连freeze，停止/end分离不跳 |
| 附件 | 图片选择及base64发送；未完整generic file receipt/upload状态 | service限制、文件、pending/error门控、重试/删除 |
| queue | 三点菜单有edit/steer/remove | 输入区dock、单项直显/多项计数、rpcId消重、pending锁 |
| 分页/滚动 | 按消息数量差scrollToIndex，跟尾用isAtEnd | 稳定业务anchor和像素补偿，折叠/图片加载/手势协调 |
| 过程详情截断 | title按UTF-16切160，递归view最大8层 | grapheme正确；深树不得静默丢失，应有继续查看入口/完整inspection |
| 用户问题 | 目前NativeInteraction存在但不等同question transcript全生命周期 | active/settled/迟到inbox/取消/中断与只读记录配对 |

## 10. 可重复验收用例

后续实现应让同一事件fixture在官方模型与原生模型产生相同语义顺序；视觉在手机验收。以下为最低覆盖，不能以“能发一条纯文本”替代。

1. **CHAT-01** human→reasoning→read→bash→progress response→run_code/PTC→final，完成后阶段回复和final保留、过程整轮收起；类别切换不拆组。
2. **CHAT-02** 工具进行中插入human steering，保持原位置，整轮不可收起；仅对应组可展开。
3. **CHAT-03** 普通系统context不可见且不拆组；非人工next-turn自动化claim成为触发通知；真人正文写cwd等前缀仍可见。
4. **CHAT-04** delta→block-end→tool/call→tool/result同callId只有一行；dispatch子调用嵌套、重复callId去重；停止冻结partial。
5. **CHAT-05** 较新read完成、较早bash仍运行，实时标题回bash；150ms最小保持；完成摘要立即更新。
6. **CHAT-06** 四档切换+all/final+completion/next-input，不重建身份；分页前展开的工具后仍展开，外层显式关闭后内层复位。
7. **CHAT-07** read/search/diff/terminal/web/image/todo/question各合法和非法metadata fixture；非法不崩溃、不漏内容、回generic；后台回执不伪造job完成。
8. **INPUT-01** 发送中重复点击无第二prompt；Host拒绝/断线保留草稿；结果不确定重连对账不自动重发；成功才清空。
9. **INPUT-02** 空闲queue，运行默认queue，可steer，Host窗口关闭不误报；空草稿运行主Stop，非空主Send；中文IME确认不发送。
10. **INPUT-03** 图片/文件pending或error阻止提交，重试/删除可恢复，纯附件可发，混合queue不可纯text编辑。
11. **QUEUE-01** 一个直显、多个默认收起；pending echo与Host rpcId消重；steer/remove使用原ID、失败保留。
12. **RECOVERY-01** 自定义端口、有/无代理认证、LAN/public；断连旧页面可读、横幅单条、generation销毁、seq/revision缺口补齐、时钟冻结恢复。
13. **SCROLL-01** 读旧内容时新输出/其他客户端消息不抢位置；自己的提交跟尾；prepend、图片撑高、过程折叠均保持锚点；手势打断动画不二次落底。
14. **MOBILE-01** 窄屏/大字号/键盘/深色/减少动态效果；工具/代码局部横滚、无整体溢出、安全区背景一致、返回层级正确。

