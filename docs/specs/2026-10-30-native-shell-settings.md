# Native Shell and Vertical Settings Specification

Date: 2026-10-30

Requirements: NAV-01 through NAV-11, SET-01 through SET-05

Research:
[native shell and settings](../research/2026-10-30-native-shell-settings.md)

## 1. Goals

The phone shell must behave like a normal DSH client: a selected conversation
remains the main surface, the workspace and session browser opens above it as a
left drawer, and Settings is a polished, vertical secondary surface rather than
a row of tabs. A cold start restores the last valid conversation and paints it
from cache while authentication and live transport reconnect.

## 2. Navigation state

Replace the phone-only `showSessions` boolean with independent state:

```text
selectedSessionId: string
drawerOpen: boolean
drawerPage: primary | search | workspaces | plugins | automations | more
settingsOpen: boolean
settingsPage: root | dsh | appearance | notifications | cards | connection | about
```

Rules:

1. `selectedSessionId` identifies the visible conversation.
2. `drawerOpen` only controls the overlay. Opening or closing it never clears or
   changes `selectedSessionId`, transcript scroll, draft, attachment draft or
   open process groups.
3. `drawerPage` is an internal drawer route. Back from a child route returns to
   the primary drawer; back from the primary drawer closes it.
4. `settingsOpen` and `settingsPage` own the settings stack. Back from a settings
   child returns to the settings root; back from the root closes Settings.
5. Modal sheets and menus retain precedence over drawer and settings back
   handling.

`NativeNavigationState` and `nativeCanGoBack()` become the single source for app
Back behavior. A short state-machine test must cover every transition.

## 3. Startup restoration

Persist `lastSessionId` per hashed origin and login scope in navigation metadata.
The saved value is a routing hint, never authorization.

Resolution order:

```text
notification/deep-link target
  -> lastSessionId
  -> empty selection (workspace drawer)
```

After metadata refresh, validate that the target exists, is visible, is not
archived and belongs to the current scope. If valid:

1. Set `selectedSessionId`.
2. Start a cache-first conversation mount.
3. Keep the drawer closed.
4. Connect/reconnect the live stream in the background.

If invalid, request the conversation body only long enough to distinguish
`404/410/archived/unauthorized` from a transport failure. Remove an invalid
remembered target, preserve any recoverable draft, and open the workspace
drawer with a compact unavailable row. Never show an empty broken transcript.

Selection is persisted only after a conversation surface has actually been
opened. Logout and identity changes clear the saved route and matching transcript
cache.

## 4. Phone drawer

Use one overlay layout shared by primary navigation and workspace management.
The conversation subtree remains mounted underneath a scrim.

Dimensions:

- Width: `min(max(320vp, 86vw), 380vp)`, capped at `windowWidth - 48vp`.
- Panel background extends behind top and bottom system gesture areas.
- Interactive content begins after top safe area and ends above bottom safe
  area.
- Scrim follows the theme and closes the drawer on tap.

Motion:

- Panel enters from the left over 180–220ms with ease-out.
- Scrim fades in concurrently.
- Closing reverses promptly.
- Reduced motion replaces translation/fade with an immediate state change.

The app implements its own hamburger and edge-swipe affordances while keeping
compatibility with API 23. System Back closes an open drawer before navigating
away from the app.

Content order:

1. `DSH Harmony` in bold plus search.
2. New conversation.
3. Plugins.
4. Automation tasks.
5. More.
6. Scrollable grouped workspace/session region.
7. Settings fixed at the bottom.

Search filters workspace names, session titles, paths and IDs. Workspace groups
can collapse, reorder sessions, pin sessions and open a management page. The
active session always receives a visible selected background, including while
the drawer is open. A three-dot menu highlights its own hit target.

Plugins, Automation tasks and More must open a real capability-supported surface.
When the current Host lacks that capability, the row includes a compact
unavailable state and an explicit compatibility-mode handoff.

## 5. Vertical Settings

Settings uses one vertical root and a child-page stack:

```text
DSH 设置
外观与动效
通知
桌面卡片
服务与账户
关于
```

Each item is a full-width 48–56vp row with semantic DSH icon, title, optional
current value and trailing chevron. The About page is a child page and keeps the
same header/back surface as other settings pages.

The root and all children share:

- Theme-aware page background.
- Top safe-area handling.
- Scroll content with `nativeSafeBottom` bottom inset.
- Theme-colored background under the bottom gesture area.
- Header back action and system Back routed through the settings stack.
- Compact DSH spacing, icon weight, corner radii and motion.

## 6. Per-control state

Remove the global `busy` guard. Every row owns a state:

```text
ready
pending
unavailable(reason)
error(message, retry)
```

Behavior:

- Local preference: apply optimistically, persist, read back, roll back on
  failure.
- Host setting: serialize writes per namespace, show only that row pending,
  preserve the last authoritative value on failure and expose an inline retry.
- Capability action: render disabled while capability state is unknown; when
  unavailable, show the reason in the row and do not accept taps.
- Navigation row: navigate immediately, independent of any network action.
- Destructive action: report progress on that row and keep a clear result.

No enabled-looking row may silently do nothing. Every tap must cause one of:
value change, navigation, local progress, or inline failure feedback.

## 7. Settings content audit

The implementation must preserve existing functionality while moving it:

| Destination | Controls |
| --- | --- |
| DSH 设置 | transcript view, collapse timing, folded replies, running-message send behavior |
| 外观与动效 | light/dark/system, reduce motion, reduce transparency |
| 通知 | per-event level matrix, Push Kit registration, no-Push background delivery |
| 桌面卡片 | task-name privacy, task count/rows, sync now |
| 服务与账户 | interface mode, server/login details, logout |
| 关于 | logo, app name, version/build, author avatar/name, repository, copyright, report issue |

Theme and local preferences must survive closing Settings and process restarts.
About assets are bundled locally. No private hostname or signing value appears in
the About screen.

## 8. Acceptance

Automated:

- Route resolution priority and invalid-session fallback.
- Drawer/Back/settings route stack.
- Selected highlighting independent of drawer visibility.
- Per-row pending/error concurrency.
- Local setting round trips and rollback.

Consolidated device checks:

- Cold start opens the last valid chat; notification target wins.
- Open/close drawer during streaming; scroll, draft and input retain state.
- Drawer ordering, fixed Settings footer, scrim and edge gesture behave.
- Every settings row is exercised twice with no silent no-op.
- Child back returns to Settings root, then closes Settings.
- Bottom safe area is theme-correct in light/dark and large text.

