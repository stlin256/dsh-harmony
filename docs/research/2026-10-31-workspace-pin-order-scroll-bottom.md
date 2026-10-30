# 置顶分区、工作区排序与回到底部调研

日期：2026-10-31  
代码基线：`193cde0`  
状态：研究结论与实施建议，尚未修改生产代码

相关材料：

- [DSH 工作区上游审计](upstream-workspaces.md)
- [原生交互总规格](../NATIVE-INTERACTION-SPEC.md)
- [原生浏览器、会话排序与 Diff 规格](../specs/2026-10-30-native-browser-sort-diff.md)
- [原生壳层、缓存与设置规格](../specs/2026-10-30-native-shell-settings.md)

## 1. 结论摘要

本轮要求把“置顶”从会话行上的一个标记，提升为列表的一级分区：

```text
置顶
  [工作区标识] 会话 A
  [工作区标识] 会话 B

工作区
  ⠿ 工作区 A                         2
    最近交互的会话
    更早的会话
  ⠿ 工作区 B                         1
    最近交互的会话

其他会话
  不属于任何已注册工作区的普通会话
```

规则如下：

1. 非归档、非空白且 `pinnedSessionIds` 命中的会话进入固定“置顶”区，跨工作区统一展示。
2. 置顶行必须显示所属工作区的简短标签；否则跨工作区同名会话无法辨认。
3. 取消置顶后，会话回到其 Host `workspaceId` membership 对应的“工作区”分组，不改变归属。
4. 工作区内普通会话固定按最后交互时间降序排列；置顶状态不改变会话归属。
5. 工作区组本身可按 Host 顺序拖动重排，调用 `workspace/insertBefore`。
6. “置顶”“其他会话”是固定分区，不参与工作区拖动；Settings 继续固定在抽屉底部。
7. 聊天向上阅读时暂停自动跟尾，并显示“回到底部”按钮；点击后恢复跟尾并回到最后一条消息。

## 2. 当前实现差异

| 能力 | 当前实现 | 差距 / 风险 | 建议 |
| --- | --- | --- | --- |
| 置顶数据 | `NativeWorkspaceSnapshot.pinnedSessionIds` 已保存 Host 全局集合 | 当前只在分组内部把 pinned 排到普通会话之前，没有独立顶层区域 | 新增 `pinned` section，先于所有 workspace 组输出 |
| 会话时间 | `NativeSession.updatedAt` 已由 gateway 透传 | 当前仅在没有 manual 顺序时生效；加载工作区后默认 `manualOrder=true` | 工作区内始终以 `updatedAt DESC + id ASC` 排序 |
| 会话拖动 | `dropSession` 会调用 `workspace/insertSessionBefore` | 新规则要求按最后交互排序，会话手排会与之冲突 | 从主抽屉移除会话拖动；保留 Host membership，不伪造跨区 |
| 工作区顺序 | `NativeHarnessSnapshot.items` 数组体现 Host 顺序 | `NativeWorkspaceItem` 未声明 `createdAt/updatedAt`；UI 没有工作区拖排 | 保留并扩展 Host 字段；拖动组标题调用 `workspaceOrder` |
| 工作区排序合同 | gateway 已支持 `workspaceOrder` → `workspace/insertBefore` | 原生 UI 尚无入口，相关 operation 未被工作区列表使用 | 新增 optimistic reorder + 失败回滚 |
| 回到底部 | 已有 `followTail` 和 `scroller.scrollEdge(Edge.Bottom)` | `onScroll` 只更新布尔值，没有按钮、显示阈值或新消息提示 | 增加悬浮按钮、延迟显示、无未读/有未读状态 |
| 加载稳定性 | 普通列表按 `LazyForEach` 发布 | 直接重算可能造成整表闪动或错误位移动画 | grouping/sort 切换时不做逐行移动动画；仅本地操作播放局部过渡 |

关键代码证据：

- `NativeSession.updatedAt`：`harmony/entry/src/main/ets/services/NativeSessionModel.ets:39-48`
- pinned/archive 集合：同文件 `:52-55`
- 当前会话排序：同文件 `:74-91`
- 当前列表分组：同文件 `:105-135`
- gateway 透传 `updatedAt`：`gateway/src/native-harness.mjs:128-140`
- 当前会话拖动与 `sessionInsertBefore`：`NativeWorkspace.ets:388-442`
- gateway `workspaceOrder`：`gateway/src/native-harness.mjs:344-346`
- 当前回到底部逻辑：`NativeWorkspace.ets:1194-1252`

## 3. Host 合同与来源

### 3.1 工作区

上游工作区是 durable entity，至少包含：

```text
workspaceId
path
title
sessionIds
createdAt
updatedAt
```

`sessionIds` 是该工作区的真实 membership。不能根据 `cwd`、标题或本机路径重新推断归属。

顺序更新使用：

```text
workspace/insertBefore
{
  workspaceId,
  beforeWorkspaceId?         // 省略表示移到末尾
}
```

该操作已经在 gateway 的 `workspaceOrder` 中映射；原生需要发送：

```json
{
  "operation": "workspaceOrder",
  "workspaceId": "source",
  "beforeWorkspaceId": "anchor"
}
```

### 3.2 会话

置顶和取消置顶继续使用 Host 合同：

```text
workspace/pinSession   { sessionId }
workspace/unpinSession { sessionId }
```

置顶集合是 Host 全局集合。`unpin` 只撤销 pinned 身份，不移动会话 membership，不删除本地滚动、草稿或缓存。

### 3.3 最后交互时间

优先使用 Host 返回的 `NativeSession.updatedAt`：

- 时间更新通常覆盖会话内容或活动变化。
- 使用数值时间戳，不根据标题、选中状态或行位置猜测。
- 降序排列，时间相同时以完整 session ID 升序打破平局。

为保证用户刚打开会话后下一次进入抽屉立即体现最近交互，可增加一层本地观察值：

```text
effectiveLastInteraction =
  max(hostSession.updatedAt, localLastInteractionAt(scope, sessionId))
```

`localLastInteractionAt` 按 hashed login scope 持久化，并只在以下事件更新：

- 成功打开会话；
- prompt 被 Host 接受；
- 收到新的 durable 会话记录；
- interaction 已完成并回到聊天。

它只是排序提示，不能改变 Host 的 `updatedAt`，也不能参与归档、授权或 membership 判断。若产品决定严格只认 Host 时间，则应删除这层本地提示，避免两端语义混淆。

## 4. 推荐数据模型

扩展现有模型，不另造第二份工作区状态：

```ts
export class NativeWorkspaceItem {
  workspaceId: string = '';
  path: string = '';
  title: string = '';
  sessionIds: string[] = [];
  createdAt: number = 0;
  updatedAt: number = 0;
}

export class NativeWorkspaceRow {
  kind: 'pinnedHeader' | 'pinnedSession' | 'workspaceHeader' |
        'workspaceSession' | 'otherHeader' | 'otherSession';
  sectionId: string = '';
  pinned: boolean = false;
  workspaceTitle: string = '';
  session: NativeSession = new NativeSession();
}
```

推荐派生顺序：

```text
1. 从 sessions 过滤顶级 subagent、归档、不可见空会话
2. 建立 workspaceId -> workspace 与 sessionId -> workspace 两个 Map
3. pinnedRows = visible.filter(pinned)
4. pinnedRows.sort(byUpdatedAtDescThenId)
5. 对 snapshot.items 保持 Host 工作区数组顺序
6. 每组的非 pinned 会话 sort(byUpdatedAtDescThenId)
7. 未归属成员 append 到“其他会话”，同样按时间排序
8. 搜索和折叠只隐藏行，不删除 membership、手动顺序或 pinned 状态
```

当前 `manualOrder` 不应继续参与主工作区会话顺序。若仍有其他设置视图需要手动顺序，应使用独立字段，不能让它覆盖本页要求的最近交互排序。

## 5. 置顶分区交互

### 5.1 展示

- 只有至少一个可见 pinned 会话时显示“置顶”区。
- 分区标题右侧显示数量，例如“置顶 · 2”。
- 每个置顶行在标题下方或右侧显示所属工作区短标签。
- 工作区标签应单行省略，完整值放入无障碍文本。
- pin 图标为实心；运行中、待确认状态仍优先显示。
- 置顶区与普通区域之间使用 1px 分隔和 16–20vp 间距，不用另一张浮夸大卡片包裹。

### 5.2 操作

```text
未置顶 -> PIN_PENDING -> PINNED
PINNED -> UNPIN_PENDING -> UNPINNED_BY_RECENCY
```

- 菜单项立即关闭。
- 只有该行显示 pending，其他行和菜单不锁死。
- Host 成功后更新 `pinnedSessionIds`。
- Host 失败时恢复原分区并显示短提示。
- 取消置顶后按 effective last interaction 回到原工作区；不回到旧的手动位置。
- 不播放整个列表“搬家”动画；采用行淡出、分区数量更新、目标区行淡入的局部过渡。
- 减少动态效果时直接切换分区。

### 5.3 撤销

取消置顶没有必要提供全局撤销。用户可重新执行置顶。若加入 toast，文字应短：

```text
已取消置顶
```

## 6. 工作区内排序

固定规则：

```text
普通会话：effectiveLastInteraction DESC，sessionId ASC
置顶会话：属于置顶区，不重复出现在工作区
当前刚创建且正在显示的空会话：若必须显示，固定在该 workspace 其余普通会话之前
```

切换工作区、重新打开抽屉、从后台返回时都采用同一排序。不要让“打开抽屉”本身改写 Host 数据。

以下变化可以引发重排：

- 收到新 durable 输出；
- prompt 成功；
- 当前会话被明确打开；
- Host 返回新的 `updatedAt`；
- 置顶或取消置顶成功。

以下变化不播放逐行移动动画：

- 首次加载；
- 搜索词变化；
- 工作区筛选变化；
- 折叠/展开；
- 账号/Host 切换；
- Host 完整 baseline 替换。

新增消息造成会话自然上移时，可只播放一次 160–200ms 的轻量位置过渡；运行中 token 不得每帧触发列表排序。

## 7. 工作区拖动排序

### 7.1 可拖动对象

- 仅 Host 注册工作区组标题可拖动。
- Settings、“置顶”标题、“其他会话”标题不可拖动。
- 工作区内的会话行不参与主视图拖动，因为排序权已经交给最近交互时间。
- 折叠按钮与拖动手柄是两个命中区：

```text
[chevron]  工作区名称                          [grip] [count] [+]
```

在手机窄屏可只显示 grip 于长按态或标题尾部，但必须有稳定的 44vp 命中区。

### 7.2 状态机

```text
IDLE
  -> long-press/gesture arm
ARMED
  -> move beyond 6–8vp
DRAGGING
  -> drop above midpoint
DROP_BEFORE
  -> drop below midpoint or at list end
DROP_AFTER
  -> optimistic local reorder
PENDING_ORDER
  -> Host success
ORDERED
  -> failure
ROLLED_BACK
```

取消拖动时回到 IDLE，不发送网络请求。

### 7.3 视觉反馈

- 被拖组标题进入 `scale(1.01)`、轻微阴影或系统 drag preview；不放大整组会话。
- 目标和下一个组之间显示 2vp 品牌色插入线。
- 目标不合法时插入线消失，使用禁止姿态。
- 放下后本地先重排，180ms 内完成位置变化。
- 失败时恢复完整旧 `items` 数组，不用倒序动画逐行回滚。
- `reduceMotion` 时取消缩放和阴影，只保留插入线与即时重排。

### 7.4 请求算法

先把 source 从工作区顺序中移除，插入 target 前或后，得到 `nextWorkspaceIds`。请求锚点是 source 新位置之后的工作区：

```text
next = source 之后的工作区
if next exists:
  beforeWorkspaceId = next
else:
  omit beforeWorkspaceId
```

必须保留每个工作区的 `sessionIds`，工作区拖动只改变 `items` 数组顺序。

## 8. “回到底部”按钮

### 8.1 显示条件

建议使用带滞回的状态，不让按钮在底部附近闪烁：

```text
AT_END:
  followTail = true
  hide button

READING_UP:
  user moved away from end
  after 100ms debounce:
    followTail = false
    show button

JUMPING_TO_BOTTOM:
  button immediately begins exit transition
  scroll to final row

AT_END again:
  hide badge
  restore followTail
```

若设备 API 可准确取得距底部像素，使用 `64vp` 阈值；否则用“不在末尾且停止滚动 100ms”作为保守条件。不要仅因一次 overscroll 弹性立即显示。

### 8.2 布局

- 作为聊天 List 外层 `Stack` 的浮动按钮，不插入 ListItem。
- 位于输入框上方 10–12vp、右侧 12–16vp，避开底部安全区。
- 圆角约 18–22vp，直径 40–44vp，背景与 DSH 次级 surface 一致。
- 图标使用向下箭头；不添加长说明文字。
- 当离开底部后新增消息，可在按钮右上角显示 6–8vp 小点或一位/两位计数。
- 键盘打开、模态菜单、文件预览或设置页打开时不显示。

### 8.3 行为

点击时必须：

1. 立即把 `followTail` 置为 true，防止后续 stream delta 被当成阅读暂停。
2. 滚动到最后一个稳定行。
3. 在 `onReachEnd` / `isAtEnd()` 后隐藏按钮并清空未读徽标。
4. 如果用户手势打断滚动，重新计算 `isAtEnd()`；未到末尾则恢复按钮。

普通模式使用约 260–320ms 的平滑滚动；减少动态效果时直接跳到底部。滚动期间不逐帧更新按钮尺寸。

### 8.4 无障碍

- 无新消息：`回到底部`
- 有 3 条新消息：`回到底部，3 条新消息`
- 动画结束后焦点保持在按钮原位置或回到聊天输入框，不把焦点丢到列表。
- 大字体下使用图标按钮加 accessibility text，不能依赖小字标签。

## 9. 动画与感知流畅

| 场景 | 建议 |
| --- | --- |
| 普通行进入/退出 | 140–180ms，opacity + 4–8vp translate |
| 置顶/取消置顶 | 180–220ms，先局部离场再局部入场；不要整列表飞动 |
| 工作区拖动抬起 | 120ms 达到 scale 1.01，避免明显弹跳 |
| 插入线出现 | 100–140ms opacity |
| 成功落下 | 160–200ms EaseOut；保持行宽不变 |
| 失败回滚 | 160ms 回到旧数组；显示短错误/重试 |
| 回到底部按钮出现 | 140–180ms opacity + scale 0.92→1 |
| 回到底部按钮退出 | 100–140ms opacity + scale 1→0.96 |
| 平滑滚动 | 260–320ms；长距离不要用瞬间高速 |
| 新消息徽标 | 160ms opacity；不要无限 pulse |

统一原则：

- 先说明状态变化，再追求快。
- 同一帧只允许一个主要动效 owner。
- 拖动期间只更新最近的插入目标，不触发布局动画。
- 完整 baseline、筛选和搜索重排使用静态替换。
- token streaming 不驱动会话列表排序动画。
- `NativeExperience.reducedMotion()` 优先于所有时长配置。

## 10. 持久化与并发

- 工作区顺序由 Host 的 `items` 数组保存，App 不另存一份可漂移的全局工作区手排。
- pinned 集合由 Host 保存。
- session effective recency 若采用本地提示，按 hashed scope 隔离，登出清理。
- 拖动请求进行中再次拖动：取消旧 UI intent，只有最新 generation 可更新可见顺序。
- 旧 `workspaces()` 响应晚到，不能覆盖更晚的本地 RPC 成功结果。
- Host baseline replace 优先于旧 unary 结果；采用 generation/request counter 对账。
- 失败时恢复完整旧 snapshot，保留 selection、草稿、滚动和缓存。

## 11. 自动化测试设计

### 11.1 纯模型测试

1. 两个工作区各有 pinned 会话，输出顶层 pinned section，且不重复出现在工作区。
2. 取消最后一个 pinned 后，pinned header 消失。
3. unpin 后 session 回到正确 workspace membership，并按 `updatedAt` 插入。
4. 时间相同按 session ID 稳定排序。
5. blank 会话不会污染普通历史；当前正在显示的新会话按确定规则可见。
6. 搜索仅隐藏不匹配行，不删 membership。
7. workspace 拖到前、后、末尾时 anchor 计算正确。
8. 工作区拖动不改变任何 `sessionIds`。
9. 旧响应晚到不能覆盖新的工作区顺序。
10. pinned 行显示 workspace label，长标题不截断到不可辨认且 accessibility text 完整。

### 11.2 交互状态测试

- pin pending 仅锁当前行。
- pin 失败恢复原 section。
- 拖动取消不发请求。
- 拖动到固定 pinned/other/settings 区域时 DROP_DISABLED。
- 回到底部按钮在离底后显示、到达底部后隐藏。
- 用户在按钮滚动中重新向上拖动时，按钮恢复。
- route switch/logout 清理新消息 badge 和 followTail。

## 12. 设备 E2E 清单候选

建议追加到统一 E2E 表：

- [ ] 在 A、B 两个工作区各置顶一个会话；抽屉顶部只出现一个“置顶”区，两行均显示正确工作区标签。
- [ ] 取消 A 的置顶；会话只出现于 A 工作区，不重复、不丢失、不改变 membership。
- [ ] 在 A 内依次打开/发送/接收输出；会话按最后交互时间上移，`updatedAt` 相同时顺序稳定。
- [ ] 长按并拖动 A 工作区到 B 前、B 后和列表末尾；重启后 Host 顺序保持。
- [ ] 拖动工作区期间折叠按钮不可误触；取消拖动不发请求；断网失败后恢复原顺序并提示。
- [ ] 置顶区和“其他会话”不能作为拖动目标，Settings 固定在底部。
- [ ] 聊天向上阅读后出现“回到底部”；继续收到输出时不自动抢回底部。
- [ ] 点击“回到底部”平滑回到最后一条消息；新输出按钮可显示新消息 count/dot。
- [ ] 大字体、横屏/平板、减少动态效果下，按钮和拖动插入线仍清晰且可操作。
- [ ] 打开设置、文件预览、菜单或键盘时，回到底部按钮不覆盖交互。

## 13. 验收标准

- 置顶会话绝不会同时出现在工作区普通区。
- 任意会话取消置顶后只能回到唯一正确的工作区。
- 工作区内普通会话顺序只由 effective last interaction 决定，并有确定性平局规则。
- 工作区拖动成功、失败、取消、重启四条路径语义一致。
- 回到底部按钮不以频繁显隐干扰阅读，点击后恢复跟尾。
- 所有动效都能在 `reduceMotion` 下安全降级。
- 不改变 Host 文件、membership、归档权限或账号隔离。
