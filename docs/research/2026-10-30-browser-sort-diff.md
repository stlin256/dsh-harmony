# 原生预览、文件浏览器、会话排序与 Diff 调研

日期：2026-10-30。

对应[需求登记](../requirements/2026-10-30-native-browser-sort-diff.md)与
[实施 spec](../specs/2026-10-30-native-browser-sort-diff.md)。

## 1. 上游基线

- 官方源码：
  `deepseek-ai/deepseek-harness@f3803c96974ad4a94195fb97e5c637e9c2a3afe3`
  （`dsh-v0.2.2-alpha.2`）。
- 工作区浏览器：
  `packages/client/ui-workspace/src/client/rows/WorkspaceBrowser.tsx`。
- 会话行：
  `packages/client/ui-workspace/src/client/rows/Rows.tsx`。
- 文件 API：
  `packages/api/workspace-files/src/index.ts` 与 `src/types.ts`。
- Diff：
  `packages/client/ui-primitives/src/DiffBlock.tsx`。
- Markdown 图片和灯箱：
  `packages/client/ui-primitives/src/markdown/render.tsx` 与
  `packages/client/ui-primitives/src/ImageLightbox.tsx`。

## 2. 当前 App 根因

| 现象 | 当前代码路径 | 根因 |
| --- | --- | --- |
| 图片链接被复制 | `NativeInlineText.open()` | 无 `sessionId` 时所有非 HTTP 链接统一复制；inline parser 不记录 `![]()` 的图片语义。 |
| 文件预览侵入状态栏 | `NativeInlineText`、`NativeTextContent`、`NativeImageView` 的 `bindContentCover` | 覆盖层直接 `padding(16)`，未读取 App 窗口安全区。 |
| 预览按钮过大 | 上述覆盖层与 `NativeWorkspace` 的“加载更早消息” | 使用 38–44vp 文本 Button，缺少官方紧凑 icon surface。 |
| 文件夹不能打开 | `NativeHarnessClient.file()` | 只有 `workspaceFiles/read`；没有 `stat/list/readBytes` 的 Gateway 映射与文件浏览器。 |
| 命令需要点两次 | `NativeProcessView` + `NativeToolCallView` | 过程组和内层命令卡各自默认收起，披露层重复。 |
| 首页不能拖排 | `NativeWorkspace.sessionList()` | `LazyForEach` 无 `onMove`；`nativeWorkspaceRows()` 强制 updated 排序。 |
| 新会话表单粗糙 | `NativeWorkspace.newSessionForm()` | 把工作区、cwd、preset 做成整页创建表单；官方 plus 是直接 `startSession(workspaceId)`。 |
| Diff 不正确 | `NativeToolCallView` | 没有专用行模型、增删色、路径头、折叠/复制/横向滚动。 |
| 加载慢、闪断线 | `NativeHarnessClient` + `NativeWorkspace.reload()` | 每次等待 state 和 sessions 后才结束 loading；元数据缓存仅进程内或没有；多个读取不共享在途 Promise。 |

## 3. 文件与图片合同

`workspaceFiles` 的公开方法参数为：

```text
list(workspaceFileScopeId, path)
stat(workspaceFileScopeId, path)
read(workspaceFileScopeId, path, range)
readBytes(workspaceFileScopeId, path, options)
```

`stat` 返回 `{ absolutePath, version, bytes? }`；`list` 返回
`{ path, entries: [{name,type,size?}], truncated }`；`readBytes` 返回
`{ absolutePath, version, bytes?, offset, data: Uint8Array, eof }`。

Connection 对包含 `Uint8Array` 的一元结果使用 multipart：JSON 元数据位于
`metadata` part，二进制字段以 `null` 占位，随后 part 名由 `attachments[].part`
指出。当前 Gateway 的普通 `response.json()` 不能解码它。

实现选择：网关增加严格 `rpcWithBytes`，校验 `type/rpcId/result.ok`、multipart
metadata、attachment path 和唯一 part 后才重建字节；App endpoint 只返回原始
`application/octet-stream` 和 base64url 编码的窗口元数据。不得把错误 JSON 当文件，
也不得把二进制转 UTF-8。目录路径只能由 `stat/list` 判断，不能凭扩展名猜测。

Markdown `![alt](url)` 与普通 `[label](url)` 分开建模。HTTP(S) 图片可作远程图片；
工作区/资源图片通过会话 scope 和可选 `baseFile` 解析。图片普通链接、附件图片和
Markdown 图片最终进入同一前景预览器。Host 返回版本变化时中止拼接并重新从 offset 0
加载。

## 4. 会话排序与新建

官方行为：

- 拖拽只修改同一工作区、同一 pinned/unpinned 区域内的顺序。
- pinned 和普通会话不能互相拖入；blank 不可拖；隐藏/归档/搜索未命中的成员保留。
- 持久化 RPC 为
  `workspace/insertSessionBefore({ workspaceId, sessionId, beforeSessionId? })`。
- 置顶/取消置顶继续使用 `workspace/pinSession`/`workspace/unpinSession`。
- 行内 plus：
  `setGroupExpanded(true)` 后直接
  `startSession(workspaceId, { clearPreviousDraft: false })`。
- 新会话进入 composer；cwd/preset 只作为按需高级选择，不能抢占默认创建流程。

当前 ArkUI SDK 提供 `ForEach/LazyForEach.onMove` 与 `List.onItemMove`。由于列表含
工作区分组，不能直接对全部行排序；实现以“可拖会话行”为数据项，在落点计算目标会话
和 before 锚点，再对完整 membership 顺序做稳定变换。它不静默删除未渲染成员。

## 5. Diff

官方 `DiffBlock` 接受 `{path, oldText|null, newText}`，默认最多显示 16 行，收起时
显示头部和尾部，中间以 gap 表示。行类型为 path/add/del/context/gap；有复制、换行
和横向滚动。当前 App 工具信息只是拼接字符串，无法可靠区分这些行。

实现先做可验证的文本行 diff 服务：

1. 仅从工具记录中明确存在的 `oldText/newText`、标准 unified diff 或 patch 参数提取。
2. 统一为文件、行类型和原文；无法判定时回退普通文本。
3. UI 做行级颜色、路径头、默认 16 行头尾、展开、复制和横滚。
4. 禁用“内容包含 diff 字样就猜测成功”的启发式。

## 6. 鸿蒙动画与安全区

- 现有 `NativeExperience.reducedMotion()` 已连接系统减少动态效果。
- `animateTo`、组件 `animation`、`transition` 和 `bindContentCover` 可用于统一
  pane、菜单、过程、预览和列表动画。
- 列表有 `onMove`/`onItemMove` 和拖拽结束事件；使用系统拖拽反馈与 spring 落位，
  不通过定时器逐帧改坐标。
- `Window.getWindowAvoidArea(TYPE_SYSTEM/TYPE_CUTOUT)` 返回 px，需除以 display
  `densityPixels` 转为 vp。根页面监听 `avoidAreaChange`，前景/旋转时刷新。
- 原生覆盖层使用该安全区；网页 surfaces 继续由原 `env(safe-area-inset-*)` 控制。
- 页面动画时序取 100ms（小状态/淡出）、200ms（常规展开/导航）、300ms（大 pane /
  全屏预览），减少动态效果时直接切换。

## 7. 缓存与预加载

现状：

- `NativeHarnessClient.reload()` 先等待 state，再等待 sessions，首帧被串行网络阻塞。
- 会话列表和工作区没有持久快照；`modelDirectory.reset()` 让 pause 丢掉可复用配置。
- 聊天和草稿只在内存，这是正确的隐私边界。

方案：

- 以规范化 `origin + 登录身份` 作用域保存会话列表、工作区、模型目录和 Host 设置
  describe 的短时 metadata；每条记录带 schema version 和时间戳。
- 打开首页先同步读最后快照绘出，再发一个后台 refresh。只有没有快照时才显示 skeleton。
- 按 endpoint 保存 in-flight Promise；重复刷新复用同一请求，完成后清空。
- 首屏只预取当前/最近会话的模型目录和会话元数据；不激活未打开聊天。
- 退出登录清空对应身份缓存；聊天正文、附件数据、未发送草稿只存内存。
- 加载不等于断线；真实 socket/HTTP failure 才进入 `retrying` 横幅。

目标指标：缓存首帧 ≤100ms；正常测试网络冷开首个可读窗口 ≤2s；记录 cold/cached
首帧、状态/列表响应、首帧消息、socket 打开和 snapshot 完成的分阶段耗时。指标是
验收目标，不把预算写成已实测结果。
