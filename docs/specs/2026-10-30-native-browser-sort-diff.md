# 原生预览、文件浏览器、会话排序与 Diff 实施规格

日期：2026-10-30。状态：v1 冻结，按优先级实施。

对应[需求登记](../requirements/2026-10-30-native-browser-sort-diff.md)和
[调研记录](../research/2026-10-30-browser-sort-diff.md)。本 spec 不撤销
[原生交互总规格](../NATIVE-INTERACTION-SPEC.md)及
[现有原生完善规格](2026-10-30-native-polish.md)的未完成项。

## 1. 执行顺序

1. P0 正确性与可用性：安全区、图片/文件类型解析、真实文件字节、紧凑按钮、过程单层
   披露、Diff 专用模型、加载与断线分离。
2. P0/P1 工作流：文件浏览器、会话拖动排序、置顶、官方新会话入口。
3. P1 体验：动画矩阵、缓存/预加载、真机验证、脱敏和版本发布。

任何一步不得靠隐藏错误、复制 URL、显示系统注入 JSON 或退回兼容模式宣称完成。

## 2. 接口合同

### 2.1 网关

- `POST /pocket/api/native/file` 保留文本预览兼容，但先由 App 的 resolver 判断类型。
- `POST /pocket/api/native/file/stat`：
  body `{sessionId,path}`，返回
  `{absolutePath,version,bytes?}`。所有字符串限长，404/不可读分类为稳定错误。
- `POST /pocket/api/native/file/list`：
  body `{sessionId,path}`，返回
  `{path,entries:[{name,type,size?}],truncated}`；拒绝越界/非目录。
- `POST /pocket/api/native/file/bytes`：
  body `{sessionId,path,baseFile?,offset?,length?}`，默认 256 KiB、最大 2 MiB。
  成功响应只含原 bytes；`X-DSH-File-Window` 为 base64url JSON
  `{protocol:1,absolutePath,version,offset,eof,bytes?}`。不把 raw path 放入普通
  header 文本。
- operation 增加 `sessionInsertBefore`，只接受
  `{operation,workspaceId,sessionId,beforeSessionId?}` 并映射公开 RPC。

二进制上游调用必须严格解析 multipart：检查响应类型、metadata、rpcId、success、
attachment codec/path/part 唯一性和 body 长度。2xx 但 metadata/附件的 contract
不符视为失败，不保存半文件。

### 2.2 App resolver

统一输入：

```text
dsh-resource://file/session/<session>/<path>
workspace-relative path
absolute/UNC path
http(s) image
sentinel attachment image
```

点击普通 link 时：

1. 去掉 `<...>`、行号 fragment，规范 percent encoding。
2. HTTP(S) 默认外开；只有图片上下文或图片 MIME/HEAD 事实进入图片预览。
3. 有当前会话则先 `stat`：`file` → 进入预览；`directory` → `list` 并打开
   `NativeFileBrowser`；`other` → 错误提示。
4. 没有会话且不是远程图片时显示“请先在会话中打开此文件”，保留 URL 可复制；
   **禁止**把图片 URL 当成功预览并只复制。

预览服务按 `origin + identity + session + absolutePath` 隔离，内存缓存只保存近期
小图和文本窗口；URL 与文件路径不写进公开日志。

## 3. 内容与预览

### PREVIEW-01 图片

- 附件图片组件保持现有授权读取，缩略图首帧只解码足够尺寸。
- Markdown 图片 parser 增加 `isImage`、`alt`、`target`；图片节点不能作为普通 Span
  点击后复制。
- 远程 HTTP(S) 图片在进入预览前检查 scheme、响应类型和尺寸上限；失败显示 alt/错误，
  仍可重试。
- 工作区图片走 `file/bytes`，通过 ImageKit 判断/解码，不信任扩展名。
- 原图预览支持捏合缩放、双击复位、系统返回和 16–32vp 图标关闭按钮。

### PREVIEW-02 安全区

- `WindowAppearance` 发布 `nativeSafeTopVp`、`nativeSafeBottomVp`，由
  `TYPE_SYSTEM` 与 `TYPE_CUTOUT` 合并，向上取整；监听 avoid-area 变化。
- 所有 `bindContentCover` 根容器使用至少该 top/bottom；水平安全区同样处理。
- 键盘出现时内容/输入区由 ArkUI resize 模式处理，固定 padding 不得冒充避让。
- 真机必须覆盖状态栏、手势条、横屏、分屏、大字体和亮/暗主题。

### PREVIEW-03 紧凑控件

- 关闭/复制/返回为 32–36vp 视觉图标按钮，可触控范围经 `responseRegion`/容器扩到
  44vp；不显示“关闭预览”“复制全文”等宽文字按钮。
- “加载更早消息”改为居中的 chevron/loading 小控件，仅在到达顶部或显式点击时加载。
- 菜单、弹层 4vp 内边距、16vp 圆角；按压、忙碌、禁用有独立语义色。

### FILES-01 文件浏览器

- 覆盖层 header：返回上一级、路径面包屑（可截断但点击可展开）、刷新/关闭。
- 列表行：24vp 类型图标、名称、次级大小/状态、chevron；目录点击进入，文件点击
  预览，other 保持可见但禁用预览。
- 首次加载骨架；空目录、截断、无权限、越界、离线分别短文案并可重试。
- 文件浏览器打开期间保留聊天挂载、draft、scroll、disclosure；返回只退浏览器。

### FILES-02 预览

- 文本/代码限行/窗口读取，保留行号上下文；版本变化从头重载。
- Markdown/HTML 源码可读；HTML 脚本不执行。
- 常见图片原生显示；PDF/Office 下载到私有临时文件后通过 PreviewKit/系统打开能力
  打开，失败可重试/分享。未知类型提供“用其他应用打开”和“保存”。
- 不把未支持的二进制当 UTF-8 文本。

### PROCESS-01 过程披露

- 打开过程组意味着成员卡处于可见披露层；命令/工具卡外壳不再额外默认收起。
- 摘要行可直接看到命令；结果正文紧跟摘要。只有存在“检查/原始输入”等真实二级页时
  才出现第二层披露。
- 打开运行组从底部跟尾；历史组从顶部；减少动态效果时直接展开。

## 4. 会话与新建

### SESSIONS-01 拖排

- 可拖条件：非 blank、非 archived、当前工作区成员、manual 排序、有对应写权限。
- 拖动起始使用长按；拖拽限制在同工作区/同 pinned 区；目标半区显示 1–2vp 插入线。
- 乐观顺序保持完整 `sessionIds`，移除 source 后按目标 before/after 插回；隐藏成员不被
  删除。归档或 blank 不参与拖排。
- 调用 `workspace/insertSessionBefore`；成功后切 manual 顺序。失败回滚并显示
  “排序未保存，请重试”。
- 置顶/取消置顶由会话菜单调用 Host RPC；成功重绘分区，失败保持原状态。置顶项跨区
  拖动不发送请求。

### SESSIONS-02 会话入口

- 顶部 `new-chat-outline` 和行内工作区 plus 都直接创建/复用当前工作区 blank 会话。
- 创建时保留其他草稿；进入 composer 后立即可以输入。
- 工作区选择器只负责切工作区。cwd/preset 经过“新建选项”小弹层，默认不展开。
- 创建请求带 client requestId，超时后先刷新列表对账，不重复创建。

## 5. Diff

输入提取顺序：显式 `diffs` → `oldText/newText` → 标准 `@@` unified patch →
通用文本回退。

`NativeDiffBlock`：

- path/add/del/context/gap 行模型；
- 增绿/删红/上下文中性灰蓝，亮暗语义色；
- 默认 16 行头尾，展开/收起 110–200ms，复制全量，水平滚动/可切换换行；
- 多文件按路径分块；空 oldText 是新建，null oldText 不伪造删除行；
- `AUTO_REVIEW_DENIED` 或失败结果优先显示失败，不渲染成已应用成功；
- 未知结构保留原文，不用“文本含 +/-”冒认。

## 6. 动画矩阵

| 交互 | 时长 | 行为 | 减少动态效果 |
| --- | --- | --- | --- |
| pane 前进/后退 | 200ms | opacity + 4–8vp slide | 直接切换 |
| 菜单/模型气泡 | 100–150ms | fade + scale 0.98 | 直接出现 |
| 过程/思考披露 | 110–200ms | height/opacity + 图标旋转 | 直接展开 |
| 图片/文件覆盖层 | 240–300ms | fade + 5% scale | 直接显示 |
| 文件目录进入 | 180ms | 横向 8vp + fade | 直接切换 |
| 排序落位 | ArkUI spring | system drag preview + move | 禁用 spring |
| 加载更多 | 100ms | spinner/chevron 状态淡入 | 静态状态 |
| 列表插入/置顶 | 180ms | row fade + translate | 直接更新 |

流式 token、滚动内容和每次 projection 刷新不增加入场动画。动画不创建第二份数据或
延迟真实提交。

## 7. 缓存与预加载

- `NativeMetadataCache` 以 `originHash + identityHint` 为分区，schema `1` 保存
  sessions/workspaces/host settings/model catalog 的 JSON 快照与 60 秒 freshness。
- 页面 mount 同步读快照并立即发布给 list；refresh 在后台运行，旧缓存不因失败清空。
- 所有 GET/metadata operation 按稳定 key 去重；写操作不去重。
- `pause()` 只关闭 socket/取消进行中的 follow；不 reset 模型目录或配置缓存。
- 预加载队列在首帧和 idle 时运行，只取最近 3 个会话的 model catalog、sessions/
  workspaces；不打开 follow。
- 日志/验收指标只记录 endpoint 名、状态、耗时、字节数，不记录 URL query、路径或正文。

## 8. 自动化与真机验收

自动化：

- 网关：stat/list 参数校验、目录/文件/other、multipart 成功、binary placeholder/
  attachment 异常、2MiB cap、版本/offset/EOF、取消；insertSessionBefore 参数与错误码。
- parser：Markdown 图片/普通链接、resource path/line fragment、图片 MIME；
  unified/generic fallback；完整 membership 拖排；同 pinned 区限制。
- cache：冷/热首帧、并发去重、身份隔离、退出清理、失败保留旧快照。
- `node --test gateway/test/*.test.mjs` 与 ArkTS Debug/Release 构建必须通过。

真机：

- 点击 Markdown 图片、附件图片、工作区图片和远程图片，均进入正确预览；非图片文件
  进入文本/系统预览；目录进入浏览器。
- 预览顶部不遮状态栏，底部内容在手势区上方；亮/暗/横屏/返回正常。
- 展开过程立即看到命令和输出。
- 同区拖动、pinned 内拖动、跨区拒绝、失败回滚、置顶/取消置顶。
- 新建键直接进入 composer，不显示旧整页表单。
- Diff 的 add/del/context/path/gap、默认 16 行、复制和展开。
- 缓存热开首帧、冷开首个可读内容、真实断网横幅、恢复与前后台。

完成状态必须逐 ID 记录为“实现未验/自动化通过/真机通过”，不得用一份“已优化”概括。
