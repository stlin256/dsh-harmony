# 历史连续预取 E2E

日期：2026-10-31

状态：待实机执行。

## 会话历史

| ID | Scenario | Expected | Status |
| --- | --- | --- | --- |
| HIST-E2E-01 | Open a long session, stay at the tail, and allow live snapshot to complete. | Older pages continue loading until history is exhausted; no manual top scroll is required. | Pending |
| HIST-E2E-02 | Make the first and second history-page requests fail transiently. | Automatic retries occur after 600 ms and 1200 ms; the page eventually loads without another scroll. | Pending |
| HIST-E2E-03 | Keep page requests failing for more than one minute. | Retries continue at no slower than the 8-second cap; the app does not settle into a stopped state. | Pending |
| HIST-E2E-04 | Disconnect and restore the network while history is still loading. | Live recovery starts a fresh immediate attempt and successful pages reset the failure delay. | Pending |
| HIST-E2E-05 | Rapidly switch sessions while an older page request is in flight. | No old rows, `beforeSeq`, or retry timer modify the newly selected session. | Pending |
| HIST-E2E-06 | Scroll up and remain in old content while background prefetch continues. | New pages are prepended and the visible readable row remains anchored; the viewport does not jump to the tail. | Pending |
| HIST-E2E-07 | Open the same large session after its history has loaded. | The cached transcript paints before the live snapshot; encrypted split-cache read does not fail with a shared-block error. | Passed |
| HIST-E2E-08 | Return `hasMore=true` with the same cursor and no rows in a protocol mock. | The app backs off and retries instead of issuing a tight request loop. | Pending |
| HIST-E2E-09 | Leave the native session while retries are pending. | The timer is cancelled and no background error banner appears in another screen. | Pending |

## 寻址与权限

| ID | Scenario | Expected | Status |
| --- | --- | --- | --- |
| HIST-E2E-10 | Open a history page after the login expires. | The app routes to the existing login flow; it does not keep displaying a generic page error. | Pending |
| HIST-E2E-11 | Log out and inspect a later login with another account. | The previous scope's split transcript chunks are unavailable to the new login. | Pending |

## 消息操作

| ID | Scenario | Expected | Status |
| --- | --- | --- | --- |
| MSG-E2E-01 | Long-press a user message containing text, links and multiple lines. | The full original message is copied and the bubble height does not change. | Pending |
| MSG-E2E-02 | Compare final assistant footers in light, dark and large-text modes. | Completion state and copy action stay on one compact row without wrapping or overlap. | Pending |
| IMG-FLOW-E2E-01 | Open an image sent in the user's own bubble and use the header download action. | The lightbox matches the workspace image preview header order, shows a download action, preserves pinch/pan, and completes the gallery save flow. | Pending |

## 构建

| ID | Check | Expected | Status |
| --- | --- | --- | --- |
| HIST-VAL-01 | Run `gateway/npm test`. | All tests pass with no private host or transcript fixture. | Passed |
| HIST-VAL-02 | Build `default` Release. | Build succeeds. | Passed |
| HIST-VAL-03 | Build `store` Release. | Build succeeds. | Passed |
| HIST-VAL-04 | Install the personal Release on the connected device. | Critical history rows pass with observed device evidence. | Pending |
