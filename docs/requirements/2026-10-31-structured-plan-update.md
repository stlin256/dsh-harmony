# Structured Plan Update and Floating Task List

Date: 2026-10-31

Status: implementation requested.

## User Requirements

- `PLAN-UI-01` Expanding an operation labeled `更新了计划` must display a
  structured task plan instead of the raw tool JSON.
- `PLAN-UI-02` Each task must preserve its text and expose one of the three DSH
  lifecycle states: completed, in progress or pending.
- `PLAN-UI-03` The current task list is always available as a floating
  component directly below the conversation title.
- `PLAN-UI-04` The floating component does not reserve a column or list row.
  It overlays the conversation, stays compact while collapsed, and expands
  downward after a tap.
- `PLAN-UI-05` Expanding the floating component reveals task rows and status
  marks. Its expanded height is bounded and scrolls internally.
- `PLAN-UI-06` Partial streaming JSON and malformed metadata must never flash as
  raw text.
- `PLAN-UI-07` The collapsed `更新了计划` operation preview must describe the
  change from the preceding complete plan, including created, completed,
  otherwise updated and removed item counts.
- `PLAN-UI-08` The floating task component must remain compact and close to the
  conversation title while the expanded transcript stays readable over chat.
- `PLAN-UI-09` Top-floating conversation controls must live in one reusable dock
  group so future plan-like components can join the same visual and interaction
  contract.
- `PLAN-UI-10` The circular back-to-bottom control must stay above the dock group
  and anchored at the transcript's bottom-right edge.

## Constraints

- Accept the pinned upstream `todo_write` payload and tolerate a repeated
  payload in a tool result.
- Preserve item order and treat the newest complete plan as the current plan.
- An empty replacement plan removes the floating component.
- Keep all plan operations and the task list read-only.
- Follow DSH density, icons, neutral surfaces, DeepSeek blue active state and
  Quiet Precision motion.
- Respect light, dark, reduced-transparency and reduced-motion modes.
- Shared ArkUI changes must build for both `default` and `store` Release.

## Acceptance Criteria

- A completed `todo_write` operation expands to a task list with status marks,
  per-status counts and no JSON braces, property names or raw array syntax.
- Its collapsed one-line preview compares the update with the preceding
  complete plan and reads as a concise Chinese diff such as
  `创建 2 · 完成 1 · 更新 1 · 移除 1`.
- The conversation title has the same compact status summary in its floating
  task control whenever the current plan is non-empty.
- The floating control stays visible while chat scrolls without shrinking the
  transcript viewport.
- The dock group and a populated plan stay compact near the title; expanded
  content uses an opaque themed surface and remains bounded for long lists.
- A tap expands or collapses the task list with directional motion; long lists
  remain within the floating surface and scroll internally.
- Future components can be rendered in the same top dock group without adding
  independent absolute-position rules.
- The back-to-bottom control renders above the plan dock at the bottom-right and
  never appears under the dock or at the top-left.
- Parser tests cover arguments, output fallback, malformed input, empty
  replacement, duplicate content, status counts and plan-to-plan diffs.
- Device evidence is recorded separately for light, dark, reduced-motion and
  long-list cases.
