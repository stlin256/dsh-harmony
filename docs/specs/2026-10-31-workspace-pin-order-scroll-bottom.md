# 置顶分区、工作区排序与回到底部实现规格

日期：2026-10-31

状态：本地实现；自动化与 Release 构建已通过，真机 E2E 待执行。研究依据见
[工作区置顶、排序与回到底部调研](../research/2026-10-31-workspace-pin-order-scroll-bottom.md)
和 [HarmonyOS 7 动效策略](../research/2026-10-31-harmonyos7-motion-strategy.md)。

## 1. 数据合同

### 会话排序

普通工作区会话使用：

```text
effectiveLastInteraction = max(host.updatedAt, local.lastInteractionAt)
sort: effectiveLastInteraction DESC, sessionId ASC
```

- `host.updatedAt` 是跨设备权威时间。
- 本地时间只在用户成功打开会话或 prompt 被 Host 接受时更新，按 hashed origin/account
  隔离持久化；退出时清除。
- 本地时间只影响列表排序，不回写 Host，不改变内容、归档、权限或 membership。
- 当前正在编辑的 blank 会话可固定在本工作区普通会话之前，但不得进入置顶区。

### 置顶

- `pinnedSessionIds` 是 Host 权威全集。
- 可见、非归档、非 subagent 的 pinned 会话只进入全局“置顶”区。
- 普通工作区投影必须排除 pinned 会话。
- 置顶行携带原 workspace title，仅用于显示和无障碍语义。

### 工作区顺序

- `NativeWorkspaceSnapshot.items` 顺序即 Host 权威顺序。
- 拖动请求：

```json
{
  "operation": "workspaceOrder",
  "workspaceId": "source",
  "beforeWorkspaceId": "anchor"
}
```

- 移到末尾时省略 `beforeWorkspaceId`。
- 工作区排序不得修改任何 `sessionIds`。

## 2. 行投影

`NativeWorkspaceRow` 明确定义以下 section：

- `pinnedHeader`
- `pinnedSession`
- `workspaceHeader`
- `workspaceSession`
- `otherHeader`
- `otherSession`

生成顺序：

1. 过滤 subagent、归档、不可见 blank、当前筛选和搜索。
2. 建立 session 到 workspace 的唯一 membership 索引。
3. 生成 pinned 排序行；至少一行时生成 pinned header。
4. 按 Host items 顺序生成工作区 header 和普通会话。
5. 未归属会话放入“其他会话”。
6. 搜索只过滤显示，不修改 membership 或 pin。
7. 折叠 pinned/workspace 只隐藏其内容行。

## 3. 置顶交互

- 菜单点击后立即关闭。
- pin/unpin 乐观更新 `pinnedSessionIds`，只锁当前动作。
- Host 成功后刷新权威 workspace/session 元数据。
- Host 失败时恢复完整旧 snapshot、旧分区和旧顺序，显示“置顶未保存”或
  “取消置顶未保存”。
- 动画只允许源行局部退出、目标区局部进入和计数更新；持续减少动态效果时直接切换。
- 置顶行与普通工作区行不跨区拖动。

## 4. 工作区拖动

### 状态

```text
IDLE
  -> DRAGGING(source)
  -> DROP_BEFORE / DROP_AFTER(target)
  -> OPTIMISTIC_ORDER
  -> CONFIRMED | ROLLED_BACK
```

- 只有真实 workspace header 可拖动；pinned、其他、设置和会话行不可作为拖动源。
- 长按 header 启动拖动；grip 提供可见提示和 44vp 命中区。
- 目标按 header 垂直中点决定放在前方或后方。
- 无效目标显示 `DROP_DISABLED`。
- 手势期间不发送 RPC；释放时才形成一个请求。

### 乐观更新与并发

- 保存最近一次成功 snapshot 和 request generation。
- 释放后立即重排 `items`，保持每个 item 的全部字段和会话 membership 不变。
- 只有最新 generation 可以回滚或确认。
- 成功刷新元数据，但晚到的旧 baseline 不得覆盖更新的请求。
- 实际 Host 写入按用户操作顺序串行执行，界面可以继续乐观更新并排队后续动作。
- 中途写入失败时停止队列，恢复到最近一次 Host 已确认顺序；提交成功后刷新失败只
  显示刷新错误，不回滚已成功写入的顺序。
- 取消拖动、拖到非法目标或手势被系统中断时清除源行、目标行和插入线状态。
- 搜索激活时仍可显示顺序，但拖动入口禁用，避免把过滤结果误当完整序列。

## 5. 回到底部

### 状态

```text
AT_END
  -> user scrolls away
READING_UP
  -> stable away for 100ms
VISIBLE
  -> tap
RETURNING
  -> reached end
AT_END
```

- `followTail` 只在用户离开尾部时关闭。
- 流式输出在 `READING_UP/VISIBLE` 时不改变滚动位置，只点亮新内容圆点。
- 用户手动回到尾部时清空圆点、隐藏按钮并恢复跟尾。
- 切换会话、退出登录、打开全屏预览或抽屉时清理滚动返回状态。

### 视觉

- 按钮位于聊天 List 外层 Stack 的右下角，输入卡上方 8–12vp。
- 40vp 视觉尺寸、44vp 命中区、主题 raised surface、0.5–1vp 描边。
- 使用向下箭头；有新输出时显示 6vp 蓝点。
- 出现 140ms fade + 4vp 上移；消失 120ms fade + 4vp 下移。
- 无障碍文本为“回到底部”；有新输出时为“回到底部，有新内容”。

### 点击

1. 设置 `followTail=true` 并隐藏按钮。
2. 减少动态效果时直接 `scrollEdge(Edge.Bottom)`。
3. 普通模式滚动到最后一个已发布行，并在布局完成后校正到真实底部。
4. 用户手势可中断返回；中断后按实际是否在尾部恢复状态。
5. 重复点击不创建重叠滚动。

## 6. 自动化测试

- pinned 跨两个工作区时只有独立 pinned header，且不重复出现在工作区。
- unpin 后回到唯一正确 workspace，并按有效最后交互时间排列。
- 时间相同时 session ID 升序。
- 搜索、折叠、空白会话和当前选择不修改 membership。
- 工作区移到前、后、末尾的 anchor 计算正确。
- 重排保持所有 membership 原值。
- 取消拖动不发请求；失败按 generation 回滚。
- 回到底部状态机覆盖离尾、显示、点击、到位、减少动效和再次手动离尾。

本地模型测试已覆盖置顶去重、取消置顶回归 membership、最近交互排序、稳定平局、
工作区拖动锚点、回到底部可见条件和流式新内容标记。RPC 队列、真实滚动位置、
手势中断和动画观感保留在真机 E2E。

完整自动化测试 71/71 通过；`default` 与 `store` Release HAP 均构建成功。真机
E2E 仍为待执行状态。

## 7. 完成门槛

- 纯模型测试通过。
- `default` 与 `store` Release 构建通过。
- 发布脱敏和 `git diff --check` 通过。
- 真机按 [E2E 表](../testing/2026-10-31-motion-workspace-scroll-e2e.md)通过后才能标记功能完成；
  本轮只写表，不宣称设备已验证。

