# Markdown 代码高亮与消息尾部研究

日期：2026-10-30

对应需求：[MD-01、MD-02、MSG-01、MSG-02](../requirements/2026-10-30-native-shell-performance.md)。

本记录区分现有代码事实、DSH 上游证据和建议方案，不代表功能已经实现。

## 当前原生实现

| 项目 | 当前事实 | 结论 |
| --- | --- | --- |
| 围栏代码解析 | 网关 `richBlocks()` 将三反引号识别为 `NativeTextBlock{kind:'code',text,language}`；`gateway/test/native-harness.test.mjs:357` 已有基础 fixture。 | 语言元数据和代码正文都可到达 App。 |
| 代码显示 | `NativeMessageView.ets:80-87` 显示语言名，然后调用 `NativeTextContent({monospace:true})`；后者只绘制单色等宽 `Text`。 | **没有语法高亮**。 |
| 行内代码 | `NativeInlineMarkdown` 只标记 `run.code`；`NativeInlineText` 用背景色和等宽字体绘制。 | 行内代码与围栏高亮应分开处理。 |
| 消息复制 | `NativeMessageView.copyMessage()` 对所有带正文的 user/assistant 行各画一个独立复制按钮；按钮位于 `Blank()` 右侧的新行。 | 运行中叙述、非最终 assistant 和 turn 尾部状态之间没有统一操作模型。 |
| 完成状态 | `nativeTranscript()` 把 `turn/end` 转为 `turn-footer`；`NativeWorkspace.ets:960` 单独绘制状态文本。最终 assistant 的复制按钮仍在自己的 `NativeMessageView` 内。 | “已完成”和复制天然被拆成两个 ListItem，无法稳定同行。 |
| 流式结束 | `nativeTranscript()` 对 non-live 的最后一条 assistant 没有记录“是否为本轮 closing reply”；最终回复资格只在 turn/control 折叠逻辑中局部推导。 | 需要显式投影最终操作归属，不能由 UI 根据当前可见行猜测。 |
| 长代码 | 全量正文保留；大文本阅读器按字符窗口分页，但普通代码块没有高亮 token 上限或增量解析策略。 | 高亮必须先定义性能上限和安全 fallback。 |

## DSH 上游基线

固定源码：`deepseek-ai/deepseek-harness@f3803c96974ad4a94195fb97e5c637e9c2a3afe3`。

- 官方唯一高亮器位于 `packages/client/ui-primitives/src/markdown/highlight.ts`：Shiki 4.4.3、JavaScript regex engine、CSS variables theme。
- 引导时只加载 TypeScript/JavaScript 家族、shell、JSON；其他语言惰性加载；未知语言回退 plain text。
- `CodeBlock.tsx` 保留原始代码，只对显示 token 着色；复制从渲染树读取并移除尾部一个换行。流式时按已完成行缓存，只重算新增尾部；超过阈值时视口外不高亮。
- 颜色定义在 `packages/client/ui-theme/src/styles/shiki.css`，亮/暗各一套；背景和前景使用 Markdown code-block token。
- 官方 assistant 复制动作属于 `TurnTailNodeView`，不在任意 assistant 正文节点上；运行中叙述不提前出现尾部复制。
- `assistantText()` 只拼接最终 closing assistant 的可见 prose blocks；turn-tail 的复制正是该内容。
- `AssistantMarkdown.module.css` 将正文与 actions 保持固定间距；移动端需要压缩尺寸，但应保留“正文之后一个操作行”的语义。

## 不建议直接打包 Shiki

Shiki 4.4.3 依赖 Node `>=20`，包含 TextMate/VSCode grammar 引擎、动态 grammar 模块和浏览器 HTML 输出路径。当前 HarmonyOS 原生应用没有 WebView 外的等价动态模块/HTML DOM 环境；直接打包会带来：

- HAP 体积、启动 grammar 初始化和大代码同步解析成本；
- Node 条件导出与 ArkTS 静态编译兼容风险；
- HTML/`dangerouslySetInnerHTML` 路径无法原样使用；
- 为获得基础高亮而引入一整套 TextMate 运行时，维护成本高于移动端收益。

## 推荐实现

### 1. App 内保持一个纯 ArkTS 高亮服务

新增 `NativeSyntaxHighlighter.ets`，输入 `{code, language, dark}`，输出有序 token：

```text
NativeCodeToken {
  text: string
  kind: plain | keyword | string | comment | number | constant |
        function | type | property | punctuation | variable | added | removed
}
```

约束：

- 原文必须逐字符保留，所有 token 拼接后严格等于输入正文；颜色不进入复制文本。
- 语言归一化只做稳定 allowlist/alias：`js/jsx/ts/tsx/json/shell/bash/sh/python/py/go/rust/rs/java/c/cpp/cs/csharp/kotlin/swift/powershell/ps1/html/css/scss/less/xml/yaml/yml/toml/sql/markdown/md/diff`。
- 未知语言、空语言、非法 fence info 一律 plain；不能用字符串拼接成动态正则或执行来源内容。
- tokenizer 只用有限、显式规则和状态机，不依赖 DOM、正则 DOM、Node API 或网络。
- 规则按语言 profile 复用：JS/JSON、shell、Python、C-family、markup/CSS、键值配置、SQL、Markdown、diff。相近语言共享 profile，维护成本低于逐语言复制。
- 注释、字符串、数字、关键字、常量、函数调用、类型/属性、标点使用独立 token kind；上下文难判定时回到 plain，不能乱改原文。

亮暗颜色直接映射 DSH Shiki 语义 token：

| kind | 亮色 | 暗色 |
| --- | --- | --- |
| comment | `#868E96` | `#ADB5BD` |
| keyword | `#D6336C` | `#FAA2C1` |
| string | `#2F9E44` | `#69DB7C` |
| number / constant | `#1C7ED6` | `#4DABF7` |
| parameter | `#E8590C` | `#FFA94D` |
| function | `#6741D9` | `#B197FC` |
| punctuation | `#495057` | `#CED4DA` |
| link | `#1971C2` | `#74C0FC` |
| plain | 主题主文字色 | 主题主文字色 |

### 2. 渲染与性能边界

- 新增 `NativeCodeBlock.ets`，负责语言标签、等宽正文、横向滚动和按 kind 上色的 `Span`。`NativeMessageView` 不再直接拼单色代码块。
- 首选 `Text + Span`：与现有 `NativeInlineText` 路径一致，ArkTS 类型稳定，不会把内容解释为 HTML。若后续实测 token 数很大，可把同一 token DTO 映射到 `StyledString`，语法服务无需改动。
- 代码块只横向滚动，整体高度跟随正文，由外层会话虚拟列表负责纵向裁剪；不嵌套纵向 Scroll/List。
- 已结束的代码块在首次进入可见区时解析一次，并把结果保留到同一 `LazyForEach` item 生命周期结束。网络重绘、主题切换不能重复扫描全文；主题切换只重映射颜色。
- 流式代码优先显示 plain。若实现增量高亮，按完整行缓存 lexer 状态并只重算新增尾部；单次 UI 更新控制在约 50ms 预算内，超出预算立即保留 plain。
- 初始实现建议硬限制：正文超过 64 KiB、1500 行或 token 超过 12,000 时不高亮，仍保持等宽、可滚动、可复制。这是性能保护，不是内容截断。
- 高亮不得阻塞列表滑动。解析期间先绘制 plain，完成后一次性替换该代码块 token，避免每个 delta 重排整个会话。
- 代码块原文和尺寸在缓存消息恢复时仍可直接显示；如果持久缓存保存 token，也必须带 tokenizer schema version，否则重新计算。

### 3. 最终回复 footer

不要把“已完成”和复制通过负 margin 或绝对定位硬压到一行。先修正数据投影：

1. 在 `NativeMessage` 的投影副本中增加仅供 UI 使用的最终回复/尾部字段，例如 `footerCopyText`、`footerCopyMessageId`、`footerOutcome`；不改变 Host journal。
2. `nativeTranscript()` 收集每个 turn 的最终 visible assistant prose，并在生成 `turn-footer` 时绑定该文本，语义对齐 DSH `assistantText(closing.blocks)`。
3. `NativeMessageView` 只在 user 消息保留用户复制按钮；非最终 assistant narration 不绘制复制按钮，避免运行中 footer 出现后移动。
4. 新增 `NativeTurnFooter.ets`：`Row({space:6})`，左侧状态文字（如“已完成”），中间 `Blank()`，右侧 28–32 vp 的复制/勾选 action。错误、停止和无最终正文时不显示复制。
5. 复制成功只把该 action 的图标在 1 秒内变为 check，不改变行高。`accessibilityText` 为“复制回复”和“已复制”。
6. 行样式使用 11–12 fp 次级文字、一个紧凑 28–30 vp action，和 DSH turn-tail 语义一致；不要同时保留原 assistant 行复制按钮。

### 4. 缓存交互

- 高亮只是 code block 的渲染派生值，不能成为持久正文的唯一副本。
- 内容缓存恢复时先按 plain 绘制；可见代码块再异步/惰性上色，避免打开长会话时一次高亮所有历史代码。
- 缓存 schema 更新、语言别名变更或 token palette 变化时，保持原文并重新计算结果；不能在旧 token 上叠加新 token。

## 自动化与 E2E

自动化应覆盖：

- JS/TS、shell、JSON、Python、Go、Rust、PowerShell、YAML、HTML/CSS、SQL、diff 的典型 token 分类。
- token 拼接与原文完全一致；换行、CRLF 规范化、Unicode、未闭合字符串/注释、非法语言、空代码块。
- 注释标记在字符串内不误判，字符串中的关键字不误判，URL/正则文本不能导致死循环。
- 语言别名归一和未知语言 plain fallback；64 KiB/1500 行/12,000 token 上限。
- 同一内容/语言二次渲染复用结果；主题切换只改颜色；超长跨块输入保持有限时间。
- `nativeTranscript()` 的 turn/end 将 final assistant 复制文本绑定到 turn-footer；运行中、无最终回复、失败和取消不产生“已完成＋复制”。
- 多个 assistant narration 只有最终 closing assistant 获得 turn-tail 复制。

设备 E2E 应覆盖：

- 亮/暗主题下各语言 token 对比度，横向滚动、缩放手势和超长行。
- 300–1000 行代码块滚动不卡顿，超阈值 plain fallback 可见且不截断。
- 流式回复从 plain 到高亮时不给当前阅读位置造成跳动。
- 最后回复下方状态与复制严格同一基线/行，复制内容完整。
- 多个历史 turn、窄屏、大字体、读屏 action 名、复制成功反馈。

## 实施顺序

1. 先写 token DTO、语言 alias、profile lexer 和纯函数测试。
2. 接入可见区代码块与主题映射，不改变消息历史结构。
3. 修正 `nativeTranscript()` 最终回复归属并新增 turn-footer 组件。
4. 删除非最终 assistant 的重复复制动作。
5. 增加性能阈值、缓存版本和真机长会话验证。
