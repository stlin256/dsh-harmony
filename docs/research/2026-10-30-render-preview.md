# 2026-10-30 内容、预览与输入交互研究

本文覆盖 [需求登记](../requirements/2026-10-30-native-polish.md) 的 RENDER-01～10、INPUT-01～04。研究先于实现；当前未提交补丁只是待验证输入，不能由本文推导修复完成。本轮只读取代码与 SDK、编写研究文件，没有修改 App/Gateway 实现，没有读取真实凭据或对话。

## 1. 基线与证据范围

- 官方 `deepseek-ai/deepseek-harness`，锁定 `f3803c96974ad4a94195fb97e5c637e9c2a3afe3`（本轮 alpha.2 基线）；复用已核实 origin 的 clone，`git show` 读取 sparse 之外文件。
- 前轮完整聊天研究仍有效：[upstream-chat.md](upstream-chat.md)。这里聚焦图片、文件、Markdown、密度和输入遗漏，不重新把未实现的全部功能声明完成。
- App/Gateway：研究时工作树包含未提交的思考行 `width('100%')`、28vp 高、reasoning padding=0、过程成员 gap=2 等补丁。它们未经过本轮构建/真机视觉验收。`NativeImageView`/`NativeTextContent` 仍使用局部 `bindContentCover`。
- 鸿蒙能力以本机 DevEcoStudio 26 SDK 的 `@kit.PreviewKit.d.ts`、`@hms.filemanagement.filepreview.d.ts`、`@ohos.file.fileuri.d.ts`、`@ohos.fileshare.d.ts` 为依据。系统预览的 URI 委托权限和实际文件类型仍必须在在线设备验证，不能把 `.d.ts` 可编译当成可用。
- GFM 表格语法另核对 [GitHub 官方 GFM 规范 §4.10](https://github.github.com/gfm/#tables-extension-)；SDK本地文档比网页检索摘要更直接。华为 [文件预览指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/preview-filepreview) 本轮文本抓取超时，未用转载内容代替官方事实。

## 2. 逐项事实、根因和 spec 输入

| ID | 源码事实/根因 | spec 中必须定义的修复与验收边界 |
|---|---|---|
| RENDER-01 | `NativeImageView.ets:20` 只置 mounted；只有用户点击按钮才 `load()`，没有自动缩略图；同一个未限尺寸 PixelMap 作为缩略图和放大图；`NativeInlineMarkdown.ets:39-59` 把 `![alt](...)` 当普通链接，丢失 image 语义；`NativeImageView:63` 每个列表项绑定 cover | 独立 image node；可见/预取范围自动load，loading/loaded/error/retry；稳定cache；聊天图像与根级原生预览overlay分开；关闭/Back回原会话及阅读位置；单图保持比例、多图统一tile |
| RENDER-02 | `gateway/native-protocol.mjs:15-35` 只按空行和三反引号正则拆heading/quote/text/code，无table AST；NativeTextBlock只有kind/text/language；inline scanner不解析表格 | 保留未经改写的Markdown源及source span；table块独立语法模型，表格单元复用inline模型；宽表局部横滚；无表格时普通pipe文本不可误判 |
| RENDER-03 | `NativeInlineText.ets:23-33` http(s)一律外开，其余一律复制；没有openFile delegate/文档页面；未解析dsh-resource、行号、相对base；图片inline也落入这条路径 | 统一TypedLink/RemoteFileTarget解析；点击远端文件进入App文档overlay，外链按Host偏好；复制链接是次操作；文本/代码/MD/图像原生，PDF/Office等系统预览为明确手机映射 |
| RENDER-04 | Gateway `rpc():22` 对所有响应直接json；未允许workspaceFiles namespace；Native request()只返回string；预览无version/cache/cancel身份 | 接入真实scope参数与multipart decoder；文本range/byte options不混；版本化页和二进制缓存；认证同源代理、无token URL；旧request迟到无效；更版不混页 |
| RENDER-05 | 简化block splitter改写正文列表前缀；未保留图片和文件块完整语义；tool仍是原始args/output；纯图片也可能显示“高级内容”占位 | 内容有序AST；官方glyph/类型/状态；合法block使用原生视图，未知类型保守完整fallback且不破坏原文；图片-only/空协议块不制造空消息；Markdown原文复制不复制装饰文本 |
| RENDER-06 | normalizer `sourceKind&&!['user','client','steer'].includes` 直接返回null；journal新增留存是好方向，但未利用claim投影wake/answer；Modern source在data.source | 隐藏是Chat视图规则，journal仍完整；独立context/wake/steering/question-reply；有效claim决定wake；Context内tool-addition/tool-removal可见通知例外；旧前缀只用于无source日志，不吞真人 |
| RENDER-07 | 现有category/call/PTC/偏好已部分实现；专用tool card仍缺；`normalizeRecord` 的parts只选择user/assistant/root result，PTC result的data.content未纳入images/contentRaw；stream compact只汇总text/reasoning，丢实时块交错位置 | raw journal为权威，预览/专用模型保存meta/content/error/call；PTC与根一致但严格model可decline；保留live block index及顺序；四档/折叠/完成边界用官方fixture逐项核对，不只看一条纯文本 |
| RENDER-08 | 当前已有 `nativeReasoningPreview`；此前Row和Button缺width导致intrinsic宽度挤掉layoutWeight；未提交宽度补丁可修几何但未证实；当前preview也依赖message.preview/stream status正确 | 标题、separator、summary同一行，summary占剩余宽度、单行ellipsis；保留完整展开文字；已完成首行/运行中最近完整段落首行；compact隐藏已完成preview；实测窄屏/大字号/流式 |
| RENDER-09 | 外层List space12、process组gap、成员gap、NativeMessageView Column space6及padding、tool展开gap/padding叠加；重复空节点和复制操作行增加高度；最新gap2补丁仅一层 | 定义同组过程行4vp官方基准、标题到正文8vp，手机视觉行与命中区域分离；消除空块/双padding；不同语义边界保留层级；不要全局把所有gap归零 |
| RENDER-10 | 分页已有id+offset的未验改进，但图片没有预留精确比例导致迟到撑高；NativeTextContent在8192后按raw字符串分片，不能保证table/code语法完整；每次paint仍跟尾滚底 | AST-first按块虚拟化；稳定node/group/call及像素anchor；图片先占已知尺寸；用户滚动优先、阅读时更新不抢尾；长文本可全部查看，补页/图片/折叠同步补偿 |
| INPUT-01 | 现有send/stop、queue/steer/模型/交互不是空壳，但attach只接受四种图片，完整聚合base64；无generic file staging；NativeInteraction一次铺全部题，单选custom没有互斥；queue不在输入dock | 按第8节逐项补齐state/receipt/能力；审批/问题/plan-review使用独立carrier；禁止把“兼容模式可做”算作原生完成 |
| INPUT-02 | NativeHarnessClient.prompt内部生成requestId但只存uncertain session集合，不保存attempt与requestId对账；无官方pending echo，收到权威Inbox可先于HTTP受理回包这一路未完成 | pendingAttempt固定requestId/content/attachments/placement；日志/Inbox user.rpcId对账；超时结果未知保持可读待确认，不能新ID重发；tool/reasoning/回答依持久事实构建 |
| INPUT-03 | 目前大量局部animateTo(200 EaseInOut)，fold仅110，未与滚动布局协调；cover导航与根Stack不一致；NativeExperience已读取reduceMotion | 根overlay一个导航owner；动画按功能时钟定义；过程采用官方70fade+50delay/110height协调，stream不重复位移；后台/减少动效终态直达 |
| INPUT-04 | `WidgetStore.detailsEnabled`默认true，用户已非匿名；15分钟缓存有效期存在；退出清空存在；但更版/身份切换/过期重新发布及隐私开关全链路需实机核对 | 名称默认可见；隐私关立即移除已存标题并更新卡片；按identity隔离；过期只显示状态及更新入口，不能冒充实时；标题数据/真实截图不可写进仓库 |

## 3. 上游图片合同：两条读取路径不能混淆

### 3.1 持久聊天图像

源码：`packages/attachment/attachment/src/types.ts`、`packages/api/session-controller/src/types.ts:SessionAttachmentRequest/Value`、`src/index.ts:attachment`、`src/commands.ts:attachment`。

请求是普通JSON Remote：

```json
{
  "type": "client-request",
  "rpcId": "one-fixed-rpc-id",
  "method": "session/attachment",
  "payload": {
    "args": {
      "request": {
        "sessionId": "session-fixture",
        "attachment": {
          "attachmentId": "opaque-id",
          "mediaType": "image/png",
          "bytes": 1234,
          "width": 640,
          "height": 480
        }
      }
    }
  }
}
```

成功value为 `{attachment:ImageAttachmentRef,data:base64String}`。Host `readImage` 验证ID/格式/byte length/尺寸；sessionId是Gateway授权scope，不能在App把它解析成storage path。此接口仍为JSON/base64，**不能错误地给它套“必定multipart”假设**。

`ImageAttachmentRef` 是一份不可变的**规整后**图像，不保证保留上传照片的最初字节。`originalDimensions`只是EXIF方向处理后、规整降采样前的尺寸事实，不是原图下载凭证。预览可显示该持久图像完整可用分辨率，不能承诺恢复服务器未保存的原始照片。工具返回的工作区图像若要原文件字节，应按其记录路径走workspaceFiles/readBytes。

上游 `ui-attachment/src/MessageImage.tsx` 在effect自动load，提供同步peek缓存、attempt重试和liveness防护。单图最长边240px保持比例，多图64px方tile，lightbox复用可用完整图；缩略图不是“查看图片”按钮。

### 3.2 Markdown图片和工作区原文件

- settled本地目标由 `parseFileLink` + owner delegate解析，使用当前会话的workingDirectory投影，再由workspace scope解析。图片里的 `![alt](path)` 不能变成文本链接。
- 相对某份文档的图片/依赖应从该文档**服务器回报的absolutePath目录**解析，不能从手机cache目录、站点URL目录或当前聊天cwd解析。`readBytes.options.baseFile`让Host完成解析，不在App猜POSIX/Windows执行世界。
- 外部http(s)图片与同源授权资源分路。外部请求不得携带Pocket ID/DSH cookie，不能把任意URL交Gateway带凭据抓取；重定向、MIME、大小、解码错误有界处理。
- 原始Markdown内代码块/转义示例不能被当作图片加载。官方仅对未转义、独立image-only paragraph内带裸空格的明确本地图片进行恢复，见 `ui-primitives/src/markdown/local-image-syntax.ts`。

## 4. workspaceFiles 真实wire与二进制transport

### 4.1 方法和参数

官方文件：`packages/api/workspace-files/src/index.ts`、`types.ts`；实际wire证据是 `tests/binary-rpc.spec.ts`。Host函数中的scope lookup wire名是 **workspaceFileScopeId**，不是 `sessionId`，不是 `workspaceId`，不要套 `{request:...}`。

| method | `payload.args` | 返回/边界 |
|---|---|---|
| `workspaceFiles/stat` | `{workspaceFileScopeId,path}` | `{absolutePath,version,bytes?}`，opaque version不解析 |
| `workspaceFiles/read` | `{workspaceFileScopeId,path,range:{offset?,limit?}}` | `{absolutePath,version,bytes?,offset,text,lines,eof}`；行从1开始，range必为对象；末行换行不是额外空行 |
| `workspaceFiles/readBytes` | `{workspaceFileScopeId,path,options:{range?:{offset?,length?},baseFile?:string}}` | `{absolutePath,version,bytes?,offset,data:Uint8Array,eof}`；byte从0开始；完整文件options={}；baseFile存在时target必须为relative |
| `workspaceFiles/list` | `{workspaceFileScopeId,path}` | `{path,entries:[{name,type,size?}],truncated}`；用于workspace-relative目录树，不是document读取 |
| `workspaceFiles/changes` | `{workspaceFileScopeId,path}`（stream） | ready确认watch完成，后续 `{kind:'change',change:{absolutePath,version}|{absolutePath,absent:true}}` |

默认Host cap：maxBytes=2MiB、maxFileBytes=32MiB、maxLines=5000、maxEntries=2000，均部署可变。超cap**失败而非静默截断**。所有offset/length/limit为安全整数；bytes/read的范围不能混用。read/stat/readBytes可读取Host授权的绝对普通文件，包括工作区外文件；list/目录watch有workspace confinement。App/Gateway不能用错误的“所有绝对路径拒绝”改变上游合同，也不能放松Host权限或把路径映射到手机。

### 4.2 multipart binary response

上游：`packages/client/connection/src/client/rpc.ts:parseBinaryResponse`；完整边界测试见 `connection/tests/binary-rpc.host.spec.ts`。

同一个POST endpoint返回根据结果类型为JSON或multipart/form-data。binary不是base64 JSON，也不是普通response.arrayBuffer直接当图像：

```text
part metadata (string JSON):
{type:'server-response',rpcId,result:{ok:true,value:{...,data:null}},
 attachments:[{path:['data'],codec:'bytes',part:'bytes-0'}]}
part bytes-0 (Blob): exact bytes
```

必须按Content-Type分派，校验唯一metadata string、server-response/rpcId、ok true及attachment表，逐path把对应null占位替换为Uint8Array。拒绝重复字段/part/path、缺part、text冒充binary、未认领part、错误codec、非法/不存在数组索引、非own-property、非null占位、截断body、错误rpcId、取消后的迟到数据。特殊键不能原型赋值。上游支持nested/optional/root attachment path，不能只实现固定 `value.data` 的字符串查找就声称通用decoder。

当前Gateway `response.json()`必然无法读workspaceFiles/readBytes的multipart。修复顺序应先有独立Connection codec及fixture，再给NativeFileService使用，避免在每个preview view手写另一套decoder。

建议的App边界有两种，主spec必须选定并测试一种：

1. **推荐**：Gateway复用/忠实移植上游binary decoder，在一个固定同源受保护endpoint校验后，将有界window的元数据和原bytes分开下发；ArkTS用requestInStream写临时文件，避免base64和UTF-8二次转换。metadata协议须显式version/offset/eof，非2xxbody不可当文件写成成功。
2. 同源Gateway透传已校验multipart，ArkTS实现同等严格codec。工作量更大，不能用split(boundary)处理任意二进制，因为合法bytes可包含相同字节串及分片边界。

不得把multipart `data:null`直接JSON.stringify到App当“空文件”。NativeHarnessClient目前string-only request需新增binary方法，metadata方法继续JSON，两者共享认证、generation、取消、错误映射。

## 5. 文件目标与resource URI解析

官方纯函数：`packages/util/workspace-path/src/file-address.ts`；Markdown目标：`ui-primitives/src/markdown/file-link.ts`；Chat owner：`ui-chat/src/client/apply.ts:263-285`；文档：`ui-sidebar-documentpreview/src/client/rpc.ts`、`html/read-relative.ts`。

### 5.1 分三类目标

- `ExternalLink {url}`：allowlist http/https/mailto；不携带Host cookie。外链选择遵守Host linkOpening，不能把所有http都当远端文件。
- `SessionFile {originKey,identityKey,sessionId,path,line?,baseFile?}`：真正可请求Host的文件。
- `UnresolvedFile {absolutePath,...}`：dsh-resource absolute scope本身无session，**不具有授权身份**；上游resource provider拒绝unknown-workspace。App不可凭绝对URI擅自选择其他账户或最近session。

`dsh-resource://file/session/<encoded-id>/<component-encoded-path>` 保留相对或绝对path；POSIX绝对path会有session/id后双slash；Windows drive的colon保留，反斜杠normalize为slash，UNC前导空segment保留。每segment decode一次，不能对全URI先decode两次。#/?文件名必须encoded；URI导航fragment/query与文件identity分开。

普通Markdown链接 `path#L12-L20` 仅接受正安全整数、end>=start，导航定位first line；path中裸query不当文件；非法percent/control/fragment-only/其他scheme不当文件；drive-rooted Windows路径例外。文件身份不含行号，同一文件从L1跳L400应复用同一preview状态。

Chat相对路径按点击时workingDirectory投影解析，缺省才用session cwd。文档嵌套相对目标按baseFile目录解析，Host解析后以其absolutePath+version返回作为cache键，不让手机字符串拼接模拟服务器filesystem。baseFile存在时absolute目标应走不带baseFile请求，不能同时传一个Host明确拒绝的组合。

### 5.2 文件扩展与能力矩阵

上游文档registry先extension priority、再最长复合suffix、再注册顺序；区分 `text-pages` / `bytes-complete` / `renderer`。二进制后缀不提供假“纯文本”fallback。原生需要同样registry式分派，不能只用“所有文件Text”或“所有http外链”。

| 文件族 | 官方行为依据 | 手机目标与fallback |
|---|---|---|
| txt/log/配置/代码 | text-pages及code viewer，行号、source、wrap、load more | App内native reader，UTF-8分页/行定位/复制；not-text改binary提示，不用替代符伪造解码 |
| md/markdown | GFM+math、frontmatter、相对图片，累计text，EOF才settled parse | App内native Markdown与source切换；table/image/links完整；math若未原生实现必须列未完成并保留源码，不显示已完成 |
| png/jpeg/gif/webp/bmp/ico/svg | bytes-complete image，zoom/pan/版本更新；SVG仍可看XML source | App内image overlay；格式/解码能力以本机SDK及设备为准，SVG不执行脚本；不支持格式转系统可用preview或保留下载，不声称已显示 |
| pdf | bytes-complete PDF viewer与view state | 优先通过PreviewKit实际系统预览；App保留文件身份与返回上下文。这是明确平台映射，不假称等同官方PDF viewer所有工具 |
| doc/docx/ppt/pptx | 官方由officeToPdf授权Host转换、PDF复用及缺字体反馈 | PreviewKit本地版本化文件实际预览；若严格等同转换/字体警告还需officeToPdf另列任务；系统不支持时可选Host转换，不能自动安装/运行本机Office |
| xls/xlsx/csv/tsv | 官方Excel viewer读原bytes，不依赖Office转换 | CSV/TSV可原生网格；Office格式可系统preview，设备可用性有明确错误；不得把二进制显示乱码当预览 |
| html/htm | 官方独立HTML body，相关本地依赖经Host readBytes(baseFile)打包、隔离执行上下文 | native source reader始终可用；若提供实际页面预览，另走隔离document surface+同源授权依赖，只是纯文本不能标实际HTML呈现完成；PreviewKit可作平台预览但其依赖/脚本行为需单独真机验证 |
| audio/video | 上游这里无全部原生文档保证；SDK PreviewKit支持若干格式 | 仅在可预览能力存在且用户点击时系统preview；格式/codec失败保留简短错误 |
| zip/unknown binary/超cap | 不冒充文本或专用viewer | 提供文件信息、明确不支持/过大、下载/系统打开的显式用户动作；不自动解压执行，不把复制链接作为唯一操作 |
| 持久generic FileAttachmentRef | 只有opaque attachmentId/name/bytes，不能等同workspace path | 本地上传草稿可预览本地选中URI；历史ref要有合法下载合同才下载，不能猜storage目录。当前基线只核实session/attachment读image，没有核实generic file读取Remote；这项必须单独补插件授权端点或官方路径资料，不能伪造workspaceFiles路径 |

## 6. 鸿蒙预览能力与导航设计

### 6.1 已核实SDK，尚未证明设备端权限

本机SDK导出 `import { filePreview } from '@kit.PreviewKit'`：

- `canPreview(context,uri):Promise<boolean>` 检查存在与类型；不检查转授权是否满足。
- `openPreview(context,{uri,mimeType,title?})`，必须UIAbilityContext；1秒内重复open不生效。
- `hasDisplayed`、`closePreview`、`loadData`；预览window singleton，loadData 100ms节流；多文件API为API12起且2-in-1有限制。
- 文档明确调用方须确保URI可delegated access。支持清单含PDF、doc/docx/xls/xlsx/ppt/pptx/csv/ofd、若干文本/HTML/图像/音视频。不能从后缀推导所有设备成功。
- `fileUri.getUriFromPath(cachePath)`可把本App缓存文件路径转换为App文件URI；它不等于授予任意远端路径读取权。`fileShare.persistPermission`是持久化既有用户文件权限，不能拿它凭空授予系统读任意路径。不要为临时预览申请不必要持久权限或把privileged uriPermissionManager API当普通App可用。

实施时把完整且校验过version/bytes的文件写到本App cache版本目录，用保留扩展名的安全leaf name，禁止把服务器目录结构原样拼入本地路径。完成fsync/close后生成本App URI，canPreview，再openPreview。SDK明确要求delegate；具体App-own URI授权可用性要用无敏感fixture PDF/DOCX在设备验证。若需要外部ability fallback，用标准read-only URI grant和限定用户点击动作，不授予写权限；不能把“返回Promise<void>”误记为文件内容已经正常渲染。

系统preview是系统window，并非可嵌入ArkUI的PDF/Office组件。本App的图像/文本/Markdown仍应在自己的原生overlay中，系统预览仅作为文件类型适配，返回落回原preview/chat。系统界面不可强行套App主题；App wrapper/loading/error则必须跟主题。

### 6.2 App内一个overlay owner

现有设置曾经cover无响应，已转Stack；图片和长文本仍分散cover，不能确认它们一定同故障，但有同类挂载/生命周期风险。设计应采用Index/Workspace共同的PreviewNavigator：

```text
chat mounted
  -> preview loading(target, generation, openerAnchor)
  -> image/text/markdown/file-info ready
  -> nested file preview（保留前页状态）
  -> system preview（只用于支持类型）
Back: system -> wrapper -> parent preview -> chat
```

- 由统一Stack/Navigation路径渲染，底层chat常驻Hidden，禁止每个LazyForEach item都创建全局modal owner。
- opener保存sessionId、view、anchor、focus；Back只弹当前层，不退出会话/设置。启动系统preview前后foreground切换不清空chat，避免pause误重置modelDirectory/preview。
- preview request有targetKey+generation+abort；target变化/关闭/登出取消所属读取。旧请求回到新target不得更新UI。
- 图像PixelMap/Source按cache lease计数，缩略图组件消失不能release仍被overlay使用的对象；overlay关闭才release自己的full decode。缓冲与读盘尽量异步，有限并发，不在UI线程把多张原图一起完整解码。
- image fit初始contain、双击/捏合zoom、pan边界、重置、关闭；保存每张视图状态；手势区与status bar安全区正确，系统Back优先关闭preview；reduceMotion无装饰性弹跳。

## 7. 保守模型、缓存与失败恢复

建议新增纯模型，不让ArkUI组件直接理解任意Remote JSON：

```text
RemoteTarget = AttachmentImage(ref,sessionId) | SessionFile(scope,path,baseFile?,line?) | ExternalImage(url)
ResourceIdentity = originKey + identityKey + scope + resolvedAbsolutePath
FileVersion = opaque string
ContentBlock = Text/Reasoning/Code/Heading/Quote/List/Table/Image/File/Unknown
Table = sourceSpan + raw + align[] + header.cells[] + rows[].cells[]
PreviewState = idle/loading/ready/error/stale/closed
UploadState = picked/uploading/ready/error/cancelled/consumed
SubmitAttempt = requestId + immutableDraft + orderedAttachmentIds + mode + placement + phase
```

### 文件与图片缓存

- immutable attachment cache键包括origin/identity/session授权scope/attachmentId/验证media与bytes；不解析ID。request coalescing使同一附件多个视图共享一次fetch。错误不永久缓存，用户retry有新attempt。
- 文件cache键包含origin/identity/scope/Host absolutePath/version/content-kind。第一页version与后页不同则停并提示“文件已更新”，重新加载成一致窗口，不能把新旧页拼在一起。文件watch absent时保留可读旧快照标stale，不假装仍最新。
- 文本page retained、image thumb与full decode分预算；磁盘二进制LRU+总bytes上限，展示中的lease不被回收；写临时.part原子rename，非EOF/byte长度不符不可publish。
- 关闭preview取消当前read（公共cache其他订阅仍需要时不误取消），回chat保持preview opener位置。切账户/站点/登出清空相关bytes/URI/PixelMap/授权状态；日志只记稳定错误码和耗时，不记完整私密path/body/token。
- 任务卡15分钟与文件cache不是一个TTL；immutable附件可复用直到identity清除或容量回收，mutable文件必须version验证。不要用15分钟假定文件未改。

### 错误分类

| 失败 | 用户面与恢复 |
|---|---|
| 401/认证失效 | 返回可达登录/退出，不把二进制登录HTML当图片；身份切换失效对应cache |
| lookup-not-found/unknown-workspace | 显示文件scope不可用，保留当前chat，不偷换session读取 |
| not-found/absent | 文件不存在，可重试；旧快照标记，不显示成功 |
| not-text | 切合适binary viewer或file-info，不替代字符解码 |
| too-large | 显示明确大小限制/选择局部分页或用户发起下载；不能静默缺尾 |
| malformed multipart/ref/MIME/decode | 简短加载失败+retry，保留原始未知block可读fallback，不崩溃 |
| network cancelled | 关闭/切页正常取消不toast；retryable断网保留旧内容，重连由资源owner恢复 |
| URI不支持/权限失败/PreviewKit异常 | wrapper显示“无法预览”+重试/可用导出，不宣称系统已打开；不在后台疯狂重复open |

## 8. GFM表格与原生排版的规范算法

### 8.1 不用空行split后猜表格

与上游 `ui-primitives/src/markdown/parse.ts` 一致采用块先于inline。优先直接移植可测试纯语法层，或生成受限AST DTO而保留原文；不能在Gateway和ArkTS各维护一套不同的模糊语法。最终主spec须选定解析owner和版本。ArkUI负责native渲染，语法结果不得混入网络/系统API。

最低table parser：

1. 在非code、非raw HTML例子区域读取候选header及紧接delimiter行，允许首尾pipe省略；header列数必须与delimiter列数相同，否则原文paragraph。delimiter cell仅合法hyphen及首尾colon；按上游GFM语法，不错误强制所有delimiter至少3横线（GFM例199的center delimiter为 `:-:`）。
2. 先识别未转义pipe切单元，再做inline。**反引号内的裸pipe仍是GFM列分隔符**；要显示pipe必须写 `\|`，包括code span内部。不能用“跳过code span里的所有pipe”偏离GFM。转义slash按奇偶配对，保留原始source用于copy。
3. body行遇空行/其他block起始结束；body少列补空，多列按header列数截断显示，原始内容仍在raw source。单元仅inline，不把换行后的段落误塞表格。
4. 单元trim表格padding后走同一inline grammar，处理code、bold、link、image、转义。引用表格递归在blockquote context解析，link目标/文件delegate保持相同。
5. streaming时只冻结已确认块；未收到完整delimiter前仍显示可读tail，补到合法表格后同source offset更新身份；append每token不重新parse全部历史。final parse与上游fixture比对，不用自造特殊规则凑样例。

官方render（`render.tsx:renderTable/Row`）：4列以上且不在blockquote时natural width+wide hook，其余填满内容列并wrap；有align时每行按align列数pad/truncate。手机保持语义，所有宽表只在自己的横向Scroll中；外层List继续垂直滚动。column width由可用宽度、header/body测量和min/max单元宽共同计算，不能按最长文本无限撑宽。cell Text用inline runs、对齐、padding、轻分隔，中性header，字号跟Host；大行数按行虚拟化，不嵌套全高度巨大Column。提供复制原始table/正文，不能只复制被截断cell。

### 8.2 其他Markdown保真边界

未经用户同意不把 `- item`改成`• item`后丢失原文；fenced/indented code、quote、list、task list、reference link、autolink、strikethrough、heading、image都有结构。raw HTML按官方当literal，不注入脚本。当前inline只实现基础子集，表格修复不能借此声称完整GFM+math已完成；仍需feature coverage。

## 9. 思考预览、工具密度与运行呈现

- 上游 `ReasoningRow.tsx` settled preview是原文本第一行去`**`；running preview是最近已完整首行的非空段落，未完整行保持上次preview，正文始终完整。compact可隐藏settled preview，但运行preview仍按上游policy；用户当前若选择详细，不能误用compact分支。
- UI一行中leading14vp/标题固定内容宽、分隔符、summary `layoutWeight(1)`，Row/Button都100%；text color显式取secondary语义；summary ellipsis不侵占glyph/标题。触控目标可独立扩大，不以button默认padding挤掉空间。
- 当前未提交宽度/padding补丁只能当几何假设；要由CLI layout确认summary bounds宽度>0，截图确认显示的是正确首行并随主题更新，再记录通过。
- 官方过程组体gap4px、header展开padding-bottom8px，视觉行高约24px随字体delta。手机可在保持命中区的前提下紧凑，但不应同时让外层12+组8+成员4+消息上下padding重复。spec给每层唯一owner：消息exchange gap、组header/body gap、组内process gap、单卡body inset。未展开的工具不创建空body，只有协议块的Assistant不创建空行，图片-only不加高级内容提示。
- PTC保留父子层级，不因深度而静默丢尾；过深树有完整inspection或虚拟化继续查看。每层相同原子renderer，具体card model可严格decline缺metadata的子结果。
- 运行时title至少150ms，不按最后output夺活动；四档、整轮资格及完成/失败/停止使用前轮研究的同一模型。native原始JSON展开仍只是generic fallback，read/search/diff/terminal/web/image/todo/question专用模型未完成就列未完成。

## 10. INPUT-01～04 的完整实施分解

### 10.1 prompt、stop、queue、模型

- pendingAttempt在发起前创建固定requestId（传到Gateway/Host），包含不可变语义草稿、ordered attachments、mode、placement、state；重复点击不创建第二attempt。
- Host `user.source.rpcId`、Inbox可以在HTTP回包前确认受理；权威受理即清草稿、转持久echo，不被迟到失败倒退。未知结果保持同requestId核对，不能只用session uncertain布尔而丢ID；用户明确重新提交时须知道先前结果。
- 空闲始终queue；running按Host `ui-conversation.busyEnter` queue(default)/steer，主Send与Enter一致，accelerated相反；闭合steer窗口由Host决定转next-turn。running空草稿为Stop；有draft为Send；sending/continuable子会话需要独立Stop；receipt只表示请求已发，不代表Turn已停止。
- queue Dock：0隐藏、1直显、多项计数默认收起；local pending操作禁用，按rpcId消重；纯text才可edit，含附件不允许改成纯text；steer/remove按原itemId，busy/error与已被claim收敛。
- model/effort由Host directory+selection投影驱动；不存在/无权限/断线的值不保存成功。模型不支持image时在上传/submit时明确Host错误，不删除已选附件。

### 10.2 图片与generic文件上传

上游raw路由 `POST /api/session/uploadFileBinary?sessionId=<id>&name=<name>[&mediaType=<image>]`，Content-Type application/octet-stream；response HTTP200里仍须校验 `{ok,value|error}`。file receipt `{receiptId,file}`；image receipt `{receiptId,image}`。后续prompt发送 `{type:'file',receiptId}`，其权限只属于同一准确Agent/session，不把attachmentId当receipt。inline image base64只作支持场景的另一合同；不是泛型文件输入。

源码：`packages/client/file-upload/src/protocol.ts`、`http-route.ts`、`types.ts`；`ui-conversation/src/client/service.ts:sendSession/createDrafts`；`api/session-controller/src/commands.ts:resolvePromptFileReceipts`。

- 文件选择立即生成有序draft descriptor和本地preview URI/文件事实，上传状态独立，导航不丢失。失败可重试/移除，pending/error均阻止整条send，不悄悄跳过失败附件。
- 从system picker读stream或有界chunk传Gateway，proxy必须raw streaming且可abort，避免先JSON base64聚合大文件。现在maxSelectNumber1+全读内存+只四图是明确缺口。
- 移除取消当前upload；没有resume合同，retry从byte0开始重新创建stream；取消后已存入Host的bytes可能仍存在，不伪报已删除。
- 受理前附件属于草稿；受理并echo对账后转持久图缓存/释放本地URI；失败保留；切账户清理。receipt不能跨session复用。

### 10.3 审批/问题/plan-review

- 现有NativeInteraction没有完全遵守官方逐题UI、单选custom互斥、timed focus/engage和计划审核行为。current code每appear重建answers，切页/重连可能丢draft；只是阅读到代码，不代表已复现实机每种情况。
- 以session+callId+batch/event身份保存draft，live foreground stream和continued Remote两条路径分开；deadline从首帧/attachWait而非本地随意默认；只有活跃请求可作决策。历史question reply气泡与tool transcript都保留身份，不能被普通非user过滤吞掉。
- 单选custom/option互斥，多选可并存；推荐预选仅draft；逐题导航、跳过/缺失定位；pending/settled/late-answer/inbox waiting只读状态逐项遵循上游。plan全文查看、批准标签和要求修改回编辑器各走正确carrier。

### 10.4 动画与任务名称

- 导航/菜单采用已有官方100/200/300档，但过程折叠独立70ms fade+50ms delay/110ms高度，由viewport一个批时钟与anchor协调。插入pending echo只一次，正式记录接替不再次动画；stream deltas不抖整行；reduceMotion系统和App立即生效。
- taskNames默认true保留；privacy关同步清除快照标题、卡片内容并发布，不只是隐藏当前设置；cache observedAt与syncAt不是同一事实，15分钟过期不能冒充任务真实结束。identity隔离及logout清理与通知点击一致。这里任务名要求针对卡片，不改聊天原始内容。

## 11. 可重复验收矩阵

| 场景组 | 必须断言 |
|---|---|
| IMAGE-A | user/assistant/tool-root/PTC result各一图；cached立即显示、cold自动load；单图比例、多图顺序，纯图片无额外占位；name/originalDimensions可选 |
| IMAGE-B | 超大尺寸thumbnail decode有界、full preview显示所有可用pixels；捏合/平移/Back；列表item离屏仍可预览、不use-after-release；重复视图只一次fetch |
| IMAGE-C | Markdown绝对/相对/带space/中文/#?文件名、外部https、错误ref、MIME冲突、401、missing、retry；外部请求无Host凭据 |
| TABLE-A | 1/2/3/4+列，colon对齐，省略首尾pipe，header/delimiter不等，少/多body列，空cell，quote/list嵌套，fence内假table |
| TABLE-B | `\|`、多slash奇偶、code中的escaped pipe/裸pipe，bold/link/image cell，stream delimiter分片，复制等于raw source，宽表只局部横滚 |
| FILE-A | POSIX/Windows/UNC、dsh-resource session/absolute、encoded#?/%/space、非法percent、L1/L12-L20/非法range、workingDirectory变化、文档baseFile相对图片 |
| FILE-B | JSON text/read +真实multipart readBytes；0/128/255字节，empty、subarray、nested/root附件；rpcId错误/重复part/缺part/原型键/截断/取消均拒绝 |
| FILE-C | read range1-based与bytes0-based、Host caps、eof、跨page version变更/absent；未知文件/401/lookup scope失败；取消迟到不污染另一文件 |
| FILE-D | 无敏感fixture txt/md/png/pdf/docx/xlsx逐型在线设备canPreview/openPreview；实际可见文件内容、URI委托、系统Back；不支持格式有fallback；SDK声明不是验收 |
| PROCESS-A | 思考preview在light/dark/font/窄屏正宽度；完成首行/运行段落首行/compact；工具紧接且无重复padding；official14类glyph、call/PTC/失败中断fixture |
| SCROLL-A | 初次图像占位/解码撑高、table变宽、补页、整轮折叠期间读者anchor稳定；手势打断不二次scrollBottom；长文所有block可读 |
| INPUT-A | 一次提交一个requestId、Inbox先受理/HTTP迟到失败、断线unknown、Host拒绝、重试不重复；草稿/附件只有受理后清 |
| INPUT-B | queue/steer/stop、busyEnter、continuable子会话、queue edit附件禁用、file receipt同scope；picker取消/上传失败/删除/重试与Limits |
| INPUT-C | 多题/推荐/单选custom/多选/skip/timed/continued/他端先答/plan-review修改批准，进出预览及重连不丢draft、不重复授权 |
| INPUT-D | privacy开关立即卡片更新、15分钟过期、未来时间、跨identity/登出；reduceMotion/后台无重复decorative animation |

测试用fixture与临时文件不得含真实部署域名、凭据、用户聊天和本机敏感目录。协议、纯parser和状态测试先行；ArkUI布局/图像/PreviewKit权限/触控与返回必须真机CLI验证。测试记录需逐ID填证据，不能一次构建通过就关闭整组RENDER/INPUT。

## 12. 依赖顺序与未决事项

1. 主spec先冻结类型/overlay导航/解析owner、真实binary合同和错误分类，保留本研究指出的未完成状态。
2. 先做独立binary codec+typed File API、URI parser及版本cache测试，再接图片autoload与root overlay；否则先做UI仍会拿不到bytes。
3. Markdown保留raw源和block AST，先table/image/file-target，再扩其他GFM语法；每项与官方fixture对照，不能把新增partial parser称完整移植。
4. 思考preview/密度属于局部几何修复，但仍在主spec之后落代码；验证现有未提交补丁是否真正解决，而不是直接追加更多padding。
5. 输入事务/receipt与question状态机是独立P1链路，按其官方合同实现；不能等所有文档viewer完成才保留requestId。
6. **需设备事实**：本App-own URI到PreviewKit的delegation、PDF/Office实际呈现及系统返回；本轮没有启动GUI或执行此设备验证。
7. **需补明确合同**：历史generic FileAttachmentRef下载；已核实的session/attachment只读ImageAttachmentRef，不允许通过猜测opaque ID绕过。
8. **需明确平台差异**：系统PDF/Office preview不是官方网页viewer所有工具的逐项重写。若要求包括同样的页码/annotation/字体提示，必须后续单独移植；主spec应公开差异，不藏在“预览成功”一句话内。
