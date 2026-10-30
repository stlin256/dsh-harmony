# DSH Harmony 原生完善实施规格

日期：2026-10-30。对应[用户要求逐项登记](../requirements/2026-10-30-native-polish.md)。本文细化[原生交互总规格](../NATIVE-INTERACTION-SPEC.md)，不撤销其中未完成的交互。三类研究均已完成并逐项复核，本规格v1冻结后恢复实现。已有工作树补丁均为未验实现，不能据此标记修复。

## 1. 依据与工作顺序

- 官方源码基线：`deepseek-ai/deepseek-harness@f3803c96974ad4a94195fb97e5c637e9c2a3afe3`，`0.2.2-alpha.2`。Git HEAD继续更新不自动改变本轮合同。
- App/插件已提交基线：`b2906a3cb21c8e65372f325567595d46664d0f50`。本轮开始时未提交补丁必须重审、重新编译和验证。
- 主题与设置研究：[theme-settings](../research/2026-10-30-theme-settings.md)。
- 连接、性能与工作区研究：[connection-workspace](../research/2026-10-30-connection-workspace.md)。
- 内容、预览与执行呈现研究：[render-preview](../research/2026-10-30-render-preview.md)。
- 上游完整设计目录：[Chat](../research/upstream-chat.md)、[Workspaces](../research/upstream-workspaces.md)、[Settings](../research/upstream-settings-visual.md)、[扩展模块](../research/upstream-extended-ui.md)。

执行顺序：先冻结需求与spec → 连接/加载状态和有效设置 → 工作区/列表 → 内容预览与表格 → 过程/输入/动效 → 真机回归、部署和发布。正确性优先于动画；不能通过隐藏错误、丢弃消息、静默截断内容缩短表面加载时间。

## 2. 连接、加载和性能

### 2.1 状态与生命周期

每个会话分别记录数据状态和传输状态。数据为`empty / cached / current`；连接为`idle / opening / syncing / live / retrying / authRequired / paused`。仅真实失败进入`retrying`；TCP/WebSocket打开不等于权威快照完成。缓存可先展示，刷新不清空原消息、草稿、附件、披露状态或阅读锚点。

首次打开：直接显示内存缓存，没有缓存显示短加载状态；仅启动一次权威follow，不同时发HTTP历史页。snapshot完成切到`current+live`。普通`state/projection`更新不能重新触发历史解析。用户切会话/进入兼容/前后台变化先递增generation并取消旧连接，旧HTTP/WS/计时器不能写新会话。

用户显式打开聊天按官方`activate:true`，后台目录/工作区读取不激活会话。固定上游没有`afterSeq/resumeCursor`输入，不发明这些参数。required history与optional state/projections/control分流管理；可选端点明确unsupported时每Host generation记能力并降级，不反复探测，更不能杀掉健康history。snapshot携带projections和assistant revision；durable seq缺口或transient revision/index缺口必须安全rebaseline/repair，保留缓存与分类原因，不能静默跳过。

真实失败：保留已显示内容，短横幅“连接中断，正在尝试重连”；指数退避带抖动，手动重试可立即进行。401转登录，403显示权限状态，网络/协议/游标缺口分别记录安全的原因码。不能对认证失败无限重连，也不能把主动暂停标成断线。所有诊断只含时长、计数、状态/关闭码、字节数，不含文本、路径、token、私人入口。

### 2.2 数据、投影与测量

现有归一化把文本复制到`text/blocks/segments/contentRaw/journal`，合成100KiB纯文本约膨胀6倍。新协议需保留一份权威raw journal，显示字段在App解析/归一化时生成；迁移应显式版本化，兼容旧App，不在旧协议上直接删除字段。分页要保留`hasMore`、cursor和replace边界。初始窗口有限但可完整补页，不删长工具结果。

具体迁移选择：手机显式请求`wire=journal-v1`，新版网关只为该模式发送单份journal事件和流式/投影元数据；旧模式继续protocol 2。App解析成现有typed view model，Markdown块缓存按event/source revision生成；原始journal仍完整。版本化HTTP page也采用同一opt-in；遇旧网关明确能力缺失才降级，不因任意超时重发提交类请求。需以协议夹具验证新旧两条链路和缺字段拒绝。

消除投影中每轮`findIndex/slice/some`与每条Assistant`rows.some`的重复全表扫描，预索引turn结束/首process/末reply；在模型revision或偏好改变时才重建投影，状态帧不重做历史。运行流更新合并，不按每个token重建完整已提交历史；`LazyForEach`本身不能解决投影成本。

测量分开记录打开→缓存首帧、握手、权威snapshot、JSON解析、归一化、投影、布局和总字节。合成fixture覆盖小会话、长文本、多工具、多turn；桌面脚本数字不作为手机性能。真机目标：有缓存首帧不等待网络（目标100ms以内）；正常测试网络冷打开首个可读窗口目标2s以内；P95单次主线程投影目标16ms以内；若未达标如实记录阶段耗时和剩余瓶颈。所有目标均须测量，不能以预算宣称实测。

| ID | 实现决定 | 验收 |
| --- | --- | --- |
| CONNECT-01 | 分离loading/syncing/retrying，替换分散boolean推断 | 冷开慢网无断线横幅；真实拔网才有横幅 |
| CONNECT-02 | 单follow、缓存首帧、有限初始窗口、去重复载荷与投影索引 | 冷/热各至少5次，记录阶段/字节/中位与P95 |
| CONNECT-03 | 对照Mux原始stream错误/close及App原因码定位；可选stream故障不杀history | 原生与Passkey链路持续连接；实际故障注入与恢复，不只截图 |
| CONNECT-04 | 身份隔离缓存、generation、锚点；退出清理；预览与设置保留聊天实例 | 切会话/设置/预览/前后台后内容和草稿不丢；换身份不串数据 |
| CONNECT-05 | 请求ID存本次提交状态，以回显/queue对账；断线不发新ID重试 | 模拟提交后丢响应，无第二次prompt |
| CONNECT-06 | 先读取同一client最后成功Host镜像，再异步刷新；每身份最多1个read在途+1个rerun | 热开P95≤100ms、已有缓存0空白帧，断网仍有旧内容与短状态 |
| CONNECT-07 | 单个横幅与短状态，不把传输错误插入聊天正文 | 同时最多一条重连提示；恢复消失 |

## 3. 工作区与会话列表

Host的Workspace是实体，不以cwd字符串猜归属。`workspace/follow` baseline与replace/upsert/remove/order/archived/pinned增量更新同一模型。工作区加载失败保留最后好快照，显式区分旧Host不支持、认证、网络、超时、解析/合同错误；HTTP200空数组不能代表所有失败。

“全部工作区”按真实workspace分组，有名称和可折叠标题，保留官方全局置顶顺序；未注册的会话独立“其他会话”。单工作区只显示membership成员，列表标题与新建默认归属跟随选择。按官方`updatedAt DESC + id`稳定排序，显式手动顺序才用Host顺序。空对话与顶级subagent过滤仍作用于所有分组，当前刚创建的空会话在正在显示时可保留。

选中视图身份、最近访问身份和菜单目标必须分开。手机返回列表不再显示当前聊天选中背景；宽屏聊天仍显示时可保留。菜单打开期间只高亮对应行的扁平三点触发区，关闭/切目标/完成后清除。不要为清高亮删除会话缓存。

标题全程保存原字符串，不`slice`业务数据。列表自然多行并增加必要行高；会话顶栏使用允许完整阅读的标题区，必要时点击展开完整标题。完整标题必须有直达路径，不能仅靠复制ID或重命名看到。菜单错误保留目标上下文，点击忙碌不落到其他行。

| ID | 实现决定 | 验收 |
| --- | --- | --- |
| WORKSPACE-01 | baseline/follow模型、全部分组、单个筛选、其他会话 | 至少2个不同实体+未归属会话，切换不混组 |
| WORKSPACE-02 | 目录浏览/创建、注册/改名/移除/排序、会话归属、归档/恢复/置顶按官方RPC | 验证请求参数和恢复；移除注册不删除磁盘目录 |
| WORKSPACE-03 | 错误分类+保留快照+重试；复核手机真实接口与Host | 请求失败→重试成功可恢复；不永久停在“暂不可用” |
| WORKSPACE-04 | 列表当前选中由视图可见性派生 | 手机返回列表无旧高亮；重新打开草稿/缓存仍在 |
| WORKSPACE-05 | `menuTarget`驱动触发区active样式，独立于selected | 先A后B菜单只有B高亮；dismiss清除 |
| WORKSPACE-06 | 去业务截断；多行/展开读全，适配大字体 | 中英文长标题可逐字阅读，不丢原串 |
| WORKSPACE-07 | blank/origin/source有依据过滤，空会话复用 | 不显示系统注入空壳，不误隐藏用户图片会话或运行会话 |
| WORKSPACE-08 | sidebar五项、header导出utilities、view菜单分离 | 顺序/图标/禁用/锚定/归档Undo/活动确认/fork无重复 |
| WORKSPACE-09 | 稳定排序、去重、名称/ID/工作区及内容搜索 | 命中归属明确；内容搜索不能伪装仅title过滤；大字体可操作 |

## 4. 主题与设置

ArkUI根作用域的系统主题与DSH显式语义色必须同步；单改背景不算完成。`WithTheme`覆盖设置、菜单、Select、Toggle、输入占位、弹层与预览；所有显式背景/文字/描边使用同一明暗语义，不把SVG stroke当fill染色。

以上是实施目标，SDK只保证组件作用域。独立builder/ComponentContent/新窗口需传同一Theme snapshot；已打开Popup/PromptAction重绘须真机验证。Select按钮、option、selectedOption与menu颜色分别覆盖。每项本地设置独立pending；flush失败把Preferences内存与UI均回滚至lastCommitted，同一缓存getSync不是落盘成功证明。

主题所有权决定：本地“应用外观”控制所有原生surface，包括兼容模式唤出的原生设置、登录和预览；General的Host字段显示为“网页外观”，保留其跨客户端意义。网页仍由官方ui-theme服务决定，Web观察值不得覆盖显式App偏好。系统栏在纯网页surface可随观测网页色，进入原生设置/预览立即采用App色；退出恢复网页色。没有两个同名开关争写`nativeDark`，也不在用户改本地外观时暗自修改其他客户端的Host偏好。

设置根保持“通用 / 应用 / 关于”同一header与TAB栏。About是第三TAB内容；二级详情在原设置容器内，Back为详情→父级→关设置。兼容模式在DSH左侧侧栏注入本地平面齿轮；优先通过App打包的可信client模块注册官方`sidebar.footer.action` slot（参数wide），点击调用同一原生设置。不要依赖旧Lucide选择器、CSS module哈希、avatar launcher或任意parentElement层数；页面未完成模块初始化时可重试注册，模块卸载清理自身slot。

通用设置先呈现缓存镜像，刷新不清空已知选项；首次没有镜像显示明确加载状态。Host写入每ns串行、最新revision；冲突刷新后由用户重试，不能覆盖外部修改。所有本地项也经过`控件→Bridge→持久化→回读`核对；未知Bridge命令视为错误，不能先涂成功。

通知级别以一次合法`notificationLevels`调用写完整对象。Push授权、系统token、本地开关和远端设备注册分别建状态；仅本设备更新/撤销，不用`allForSession`误撤其他手机。新增项目自有`GET /pocket/api/device?id=<id>`，仅返回该owner的`{id,registered,notifications,revision}`，绝不返回token；POST/DELETE返回同一receipt。配置请求的答案不明时GET对账。

关闭后停止App主动发布本地通知；发送前复查等级/注册状态并取消未发的对应jobs。已交华为的系统notification不能由本地业务开关拦截。远端注销失败显示“关闭待同步”，保留持久待对账意图，下次认证处理，不能承诺完全停发或重新打开用户已关的开关。

| ID | 实现决定 | 验收 |
| --- | --- | --- |
| THEME-01 | App统一light/dark/system，原生/兼容/登录/预览全部生效 | 三模式跨页面矩阵，系统主题变化自动生效 |
| THEME-02 | WithTheme+语义色审计+真实控件弹层 | 输入/占位/下拉/Toggle/菜单无错误对比色 |
| THEME-03 | 状态栏保留，按安全区布局，不提供全屏开关 | 顶部不遮内容，设置无全屏项 |
| THEME-04 | 底部系统区域随页同色，键盘正确避让 | 列表/聊天/设置/读图与键盘开关实机截图 |
| THEME-05 | 减少动效/透明传递到实际挂载组件 | 系统/App开关可回读，token不触发入场动画 |
| SETTINGS-01 | 共享原生设置容器+官方sidebar本地入口 | 原生/兼容均可进入；无穿透/失效cover |
| SETTINGS-02 | 三TAB同容器/About embedded | 切关于header/TAB不消失；返回路径一致 |
| SETTINGS-03 | 单导航状态派生Back | 各二级页Back只退一级 |
| SETTINGS-04 | 每项有持久化/异步状态/回读/错误对账 | 逐控件开关→离开→回来→重启→断网失败矩阵 |
| SETTINGS-05 | 三通知级别真实事务、仅本机token注册/撤销 | 三种任务各开关组合；关一个不影响其他等级/设备 |
| SETTINGS-06 | 本地Push版优先，现有无Push后台能力保留且如实呈现 | 杀进程Push与通知点击；无Push不显示虚假Push成功 |
| SETTINGS-07 | Host describe/mutate镜像驱动真实投影与输入偏好 | 最新revision写入、冲突、四档/折叠/queue生效 |
| SETTINGS-08 | 本地logo/作者头像/版本/版权许可/仓库/Issues | 离线可见素材；链接指向实际仓库；版本来自构建元数据 |
| SETTINGS-09 | 上游设置节奏、紧凑行、短反馈 | 小屏/大字体/暗色/长值无溢出，无长篇技术说明 |

## 5. 内容、文件和执行呈现

图片附件`session/attachment`仍是JSON base64，不能当multipart解析。immutable附件只保证Host存下来的图像，`originalDimensions`不是未保留的原始照片字节。Markdown图片与普通链接分别解析；图片自动加载缩略图、稳定占位、失败重试，按身份/会话/attachment缓存并限制内存。离屏只释放该组件自己的thumbnail lease，overlay仍持有的full/source不得release。

文件使用官方`workspaceFiles`命名参数：`workspaceFileScopeId,path`；text read另有`range`，bytes read另有`options.range/baseFile`，不能包`request`。`version`是opaque字符串，不解析成数字。二进制RPC遵循官方multipart codec；分块读校验相同version，版本变化不拼接。文档内相对目标才传该文档baseFile；绝对target不得同时传baseFile，Chat普通相对文件按点击时workingDirectory。行号片段保留；不把Host已授权的工作区外可读生成文件一概禁掉。

二进制边界选择研究推荐方案1：Gateway按Content-Type使用严格上游等价decoder（完整metadata/rpcId/attachment/path校验），再通过固定受认证native endpoint把窗口元数据与原bytes下发。App用requestInStream直接写cache文件，不把binary转UTF-8/base64。文件窗metadata带absolutePath/version/offset/eof，特殊值不进入响应header原文；错误body绝不能保存为成功文件。generic FileAttachmentRef没有已核实的历史下载合同，保持明确未完成，禁止猜存储路径；本轮远端workspace文件预览不据此宣称generic附件已完成。

具体framing：`POST /pocket/api/native/file`只读，body为`{sessionId,path,baseFile?,offset?,length?}`，默认256KiB、最大2MiB窗口；成功`application/octet-stream`原bytes，`X-DSH-File-Window`为base64url编码的JSON `{protocol:1,absolutePath,version,offset,eof,length,bytes?}`，header不承载raw路径字符串。App校验协议/请求offset/实际length/版本与EOF后才提交窗口；metadata超界、2xx HTML、截断/超长body均失败，不保存成功标志。

Index层统一前景预览导航，聊天保持挂载。图像、文本/代码/Markdown原生预览；PDF/Office等在下载到版本化临时文件后用可转授权URI调用PreviewKit系统预览，并真机验证URI权限。`canPreview`不等于已获权限。未知类型提供保存/分享/用其他应用打开和复制链接；预览失败留在可重试状态，不静默退化为复制链接。缓存仅App私有目录，退出清理；名称和MIME由内容/Host事实确定，不信任远端任意跳转。

GFM表格在块解析层识别，不能由inline regex冒充。分隔行、对齐、转义pipe、inline code、链接、缺列/多列使用规范化网格；宽表仅表格横向滚动，页面仍纵滚；复制仍保留原Markdown。图片/表格在列表异步撑高和过程折叠后恢复业务锚点，阅读旧内容不强制拉尾。

| ID | 实现决定 | 验收 |
| --- | --- | --- |
| RENDER-01 | 附件/Markdown图片自动缩略图+共享前景读图 | 实际图像可见、点开、返回、失败重试；不只有按钮 |
| RENDER-02 | 块级GFM表格+原生网格 | 对齐/escaped pipe/code/宽表/复制原文fixture |
| RENDER-03 | resource resolver→scope/baseFile→text/bytes→实际预览 | 相对/绝对/行号、文本/代码/图片/PDF/Office逐类实机 |
| RENDER-04 | 授权、multipart codec、version/baseFile与取消generation | 变更版本不混页，换会话不误打开，错误可返回/重试 |
| RENDER-05 | 上游块顺序和图标，本地素材；专用工具card保留原始字段 | 混合文字/思考/工具/图片顺序与官方fixture对照 |
| RENDER-06 | Chat投影过滤system source；raw journal完整 | 上下文隐藏，真人/steer/有效唤醒和回答不误删 |
| RENDER-07 | 按总spec逐工具card、分组与过程生命周期 | call/result/PTC/preparing/失败/停止/四档对照；通用JSON不算专用完成 |
| RENDER-08 | 思考header整行宽度，标题固定，首行预览layoutWeight | 完成首行；运行中最近完整段落首行，未完整不刷新；compact隐藏完成预览；可用空间不被挤占 |
| RENDER-09 | 去重复padding/gap，成员内容间距2vp，保留触控区 | 思考紧接工具无多余空行；折叠按钮可触达 |
| RENDER-10 | 业务ID锚点、补页/图片/折叠高度协调、长文本虚拟化 | 手动读旧消息不拉尾；加载旧页无跳动/丢失 |
| INPUT-01 | 上游公开发送/停止/queue/steer/模型/附件/交互合同 | 原生实际发送和回复可用；不以兼容页代替原生完成 |
| INPUT-02 | requestId回显对账、Queue Dock、claim/continued/settled | 无重复prompt/审批；断线恢复活动状态正确 |
| INPUT-03 | 页面/菜单/折叠协调动画，减少动态效果生效 | Back/中断/快切无残影或失触；逐token不播入场 |
| INPUT-04 | 默认显示任务名，隐私选项真实影响通知/卡片 | 默认有名称；开隐私后遮蔽，关闭恢复；快照有过期清理 |

通用文件上传硬合同：先`POST application/octet-stream /api/session/uploadFileBinary?sessionId&name[&mediaType]`得到receiptId，再prompt引用`{type:'file',receiptId}`。pending/error附件阻止发送；混合附件queue禁止文本edit。历史通用附件下载与此上传receipt是不同能力，不能混为一谈。

## 6. 登录、维护和发布约束

| ID | 实施/保留要求 | 验收 |
| --- | --- | --- |
| AUTH-01 | 默认原生访问密钥登录；LAN/公网、HTTP/HTTPS按Host规则 | 只装插件的入口可登录/退出，Passkey不抢默认 |
| AUTH-02 | Pocket ID选项在下方，HTTPS、取消/失败/重试/回跳 | 真实Passkey登录与失效退出，无绕过服务端认证 |
| AUTH-03 | 简洁配置向导，失败仍可改地址/模式/退出 | 新装、错误地址、错误密钥、取消Passkey逐路径可恢复 |
| RELEASE-01 | DSH Harmony独立身份，CLI签名构建安装 | build成功才安装；记录versionCode/签名包hash |
| RELEASE-02 | DSH升级保留旧runtime/状态备份与回退 | 已验alpha.2认证/会话/工作区/设置/导出/FFI/PTY；升级日志脱敏 |
| RELEASE-03 | 不启动GUI，CLI/HDC布局与截图验证 | 开发/编译/安装/真机检查全用CLI |
| RELEASE-04 | 锁上游hash、源码依据/差异、spec/证据分离 | README/状态表链接一致，不能把目标表当完成表 |
| RELEASE-05 | 私人配置与素材证据在ignored artifacts，不入历史 | staged+reachable history发布扫描通过 |
| RELEASE-06 | 中英文README含logo、有效仓库/Issues、tag | 提交/推送/tag完成；不检查Actions |
| RELEASE-07 | 可选Passkey部署流程与工具保留仓库 | 文档默认原生路线独立可用；秘密只从本地配置读取 |
| RELEASE-08 | 已授权重启，仍保留原子部署和回退 | 失败不安装旧HAP冒充新包；远端健康通过才切成功 |

## 7. 验收记录规则

1. 每个实现提交标注本表ID，更新独立实施记录：未开始/实现未验/自动化通过/真机通过/已知缺口，不能合并成“全部完成”。
2. 自动化只测真实合同、状态转移、解析/排序/投影和故障恢复，不写与实现同义的低价值测试。设备视觉/响应/系统URI权限不能由Node测试替代。
3. 每个阶段执行相关测试、ArkTS release构建；构建成功后再签名安装。真机覆盖亮/暗/自动、三个TAB及二级返回、设置回读、双工作区、标题/菜单、冷/热聊天、重连、图片/表格/文件。
4. 远端使用不可变release+原子切换，验证插件、Host、原生/Passkey链路，不改其他App的relay服务。测试文件与临时授权随后清理。
5. 最后更新版本、双语README和实际验证记录，检查diff/脱敏，再commit/tag/push。不查询Actions；不宣称尚未完成的原生页面与上游100%等价。
