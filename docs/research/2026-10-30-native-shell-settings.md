# Native Shell and Settings Research

Date: 2026-10-30

Requirements:
[2026-10-30-native-shell-performance.md](../requirements/2026-10-30-native-shell-performance.md),
IDs `NAV-01` through `NAV-11` and `SET-01` through `SET-05`.

## 1. Evidence and scope

This report records current repository behavior and design constraints before
implementation. It does not claim device verification.

The reference screenshots require a phone-width left drawer with a visible scrim,
the conversation retained behind it, a bold application name and search action at
the top, a primary new-conversation action, three global destinations, grouped
workspaces and sessions, and Settings anchored at the bottom.

The existing upstream interaction research remains applicable:

- Global Settings is a footer item in the official desktop sidebar.
- Plugins, Automation tasks, and More are global destinations, not session tools.
- Workspaces are durable Host entities. Membership comes from workspace
  `sessionIds`, not from comparing `cwd`.
- Host settings are capability-gated and writable only when
  `settings/describe` grants access.
- The official settings surface groups content and preserves secondary-page state;
  the phone adaptation must not flatten this into unrelated horizontal tabs.

Evidence:

- [upstream settings research](upstream-settings-visual.md)
- [upstream workspaces research](upstream-workspaces.md)
- [upstream extended interaction research](upstream-extended-ui.md)
- [current native interaction spec](../NATIVE-INTERACTION-SPEC.md)
- [current implementation coverage](../NATIVE-COVERAGE.md)

## 2. Current startup and navigation

### 2.1 Last conversation is not restored

`NativeWorkspace` initializes `selected = ''` and `showSessions = true`
(`NativeWorkspace.ets:99` and `:102`). After metadata refresh it requests only an
explicit notification/requested session or the in-memory
`client.selectedId` (`:204` and `:211`). Neither value survives process restart.

`NativeMetadataCache` persists sessions and workspaces but has no last-session
field (`NativeMetadataCache.ets:5`, `:28`, and `:42`). `Index` persists the server
origin and login mode, but not the selected conversation. Consequently a normal
cold start redraws the workspace list even when the user had a valid open chat.

The implementation needs a per-origin, per-identity `lastSessionId`. It must be
written when selection succeeds and validated against the refreshed session and
workspace snapshot before use. A notification target has priority over the
remembered session. Archived, deleted, unauthorized, blank-only, or otherwise
unavailable remembered targets fall back to the list without opening an empty or
broken chat.

The content cache work must make this restore useful: with a transcript cache, the
conversation can paint its last good snapshot while the background stream
reconnects. Without transcript cache, the remembered session still opens its chat
surface with a loading state rather than flashing the list.

### 2.2 The narrow-screen list replaces and unmounts chat

The current phone layout chooses either `sessionList()` or `conversation()` in a
single `Row` (`NativeWorkspace.ets:1074` onwards). `backToSessions()` sets
`showSessions = true` (`:257`), which swaps away the conversation. The drawer is
therefore really a full-page mode switch and breaks NAV-03.

The same boolean also controls selected-row highlighting. `sessionsChanged()` sends
an empty selected ID while `showSessions` is true, and `sessionRow()` only paints
the selected background while the list is hidden or the layout is wide. This
explains a missing current-conversation highlight when the list is visible.

The fix must separate three concepts:

1. `selectedSessionId`: durable current conversation.
2. `drawerOpen`: whether the overlay drawer is visible.
3. `drawerPage`: primary drawer, workspace management, search, plugin entry,
   automation entry, or More entry.

Opening the drawer must not change or clear `selectedSessionId`, and it must not
unmount the conversation component.

## 3. Recommended drawer architecture

### 3.1 Layout

For phone widths use an overlay container that keeps the chat subtree mounted:

```text
Stack / SideBarContainer(Overlay)
├── conversation surface (always mounted)
└── drawer when open
    ├── scrim over the conversation
    └── left panel
        ├── safe-top
        ├── DSH Harmony (bold)                  [search]
        ├── new conversation button
        ├── Plugins
        ├── Automation tasks
        ├── More
        ├── Workspace / search / management
        ├── scrollable workspace and session groups
        ├── fixed bottom Settings row
        └── safe-bottom
```

`SideBarContainer(SideBarContainerType.Overlay)` is the preferred platform
primitive: its API 8 contract explicitly overlays content without changing the
content width. `showControlButton(false)` lets the app use DSH's own semantic
hamburger/search controls.

`showSideBarWithGesture` is only available from API 26. The app's compatible SDK
is API 23, so the implementation must either provide its own edge-pan gesture or
guard any newer API without changing the navigation contract. Back and the close
action must close the drawer before allowing system Back to leave the app.

For tablet width, an embedded persistent sidebar may remain, but the phone
composition is always an overlay drawer. The same content components should be
used in both layouts.

### 3.2 Phone sizing and motion

- Panel width: approximately 84–88% of the available width, clamped to a
  practical reading width (about 320–380vp).
- Scrim: dims the conversation, closes on tap, and must not be part of the drawer.
- Motion: DSH-like short translate plus scrim fade. Follow reduced-motion and do
  not animate when disabled.
- Safe areas: panel background covers top and bottom; the bottom Settings item
  stays above the gesture area.
- Accessibility: the drawer has a label, its action targets are at least 44vp,
  focus stays inside while open where the framework permits, and closing returns
  focus to the conversation menu button.

### 3.3 Drawer content hierarchy

Fixed header:

- `DSH Harmony` in bold, using the current BuildInfo app name.
- Search icon, opening an inline global query field.

Fixed primary destinations:

- New conversation: the existing official start-session flow.
- Plugins: global plugin manager when native capabilities exist; otherwise an
  explicit capability-aware compatibility handoff. Do not hard-code an invented
  SPA route.
- Automation tasks: global schedule catalog when available; otherwise the same
  compatibility handoff model.
- More: global More actions and registered views, not a duplicate settings page.

Scrollable workspace region:

- Section label `工作区` with management and add-workspace affordances.
- One collapsible group per Host workspace.
- Pinned sessions retain their upstream global ordering and pin identity.
- Session rows show title, running state, schedule/unread state when available,
  and the anchored session menu.
- The selected conversation is highlighted whenever the drawer is open.
- Empty state is compact and offers new conversation/workspace creation.

Fixed footer:

- Settings row with a semantic gear icon, label, and safe-bottom padding.

### 3.4 Drawer navigation state

Suggested state transitions:

| Current | Event | Next |
| --- | --- | --- |
| Chat, drawer closed | tap hamburger or edge swipe | drawer primary, chat retained |
| Drawer primary | tap scrim/back/close | drawer closed, chat retained |
| Drawer primary | choose a session | selected session changes, drawer closes |
| Drawer primary | search | search route within drawer |
| Drawer primary | workspace management | management route within drawer |
| Drawer child route | Back | drawer primary |
| Drawer primary | Back | drawer closed |
| Drawer closed | Back | existing system/chat back behavior |

`NativeNavigationState` should model `drawerOpen` and `drawerPage` directly; it
must stop representing phone navigation as `sessions = false/true`.

## 4. Startup restoration flow

Recommended order:

1. Read origin-scoped metadata and optional cached transcript.
2. Validate authentication and fetch sessions/workspaces.
3. Read a notification target.
4. Resolve target order:
   notification session → remembered session → no selection.
5. Confirm the resolved target is visible, non-archived and accessible.
6. Open chat immediately; close the drawer.
7. Revalidate in the background. If invalidated, close chat and open the drawer
   with the reason, preserving any draft for a recoverable target.
8. Persist a new last-session value only after a session actually opens.

Logout, explicit connection reset, or identity mismatch removes the remembered
session and its cached transcript. Changing servers cannot reuse another origin's
target.

## 5. Settings architecture

### 5.1 Replace horizontal tabs

`NativeSettings` currently renders General, Application, and About as three
horizontal buttons (`NativeSettings.ets:379`–`:389`). Replace this with one
vertical root:

```text
Settings
├── DSH settings
├── Appearance and motion
├── Notifications
├── Desktop cards
├── Connection and account
├── About
└── Developer/test tools (if retained)
```

Each root row opens a secondary page in the same settings surface. Back follows
secondary page → root → close Settings. About is a secondary page, not a sibling
tab that visually replaces the whole settings chrome.

The root also needs a short build/version footer only if it does not duplicate the
full About page.

### 5.2 Control state contract

Every control should have one of these states:

- `ready`: interactive with committed value.
- `pending`: local intent shown with a small progress indicator; only that row is
  disabled.
- `unavailable`: control is visibly disabled with a short capability reason.
- `error`: last committed value restored or retained and a short inline retry.

Do not use one global `busy` flag to block unrelated controls. Today `setting()`
and `action()` share that flag (`NativeSettings.ets:168` and `:208`), while
`actionRow()` only reduces opacity and the handler silently returns during
pending. This makes valid taps appear dead.

Local preferences should use an optimistic update followed by Bridge persistence
and authoritative readback, with rollback on failure. Host settings should keep
per-namespace serialization and revision conflict recovery already present in
`NativeHostSettings`.

Every row must demonstrate a result through changed value, navigation, progress,
or an inline error. An action must not render as an ordinary enabled row when its
capability is absent.

### 5.3 Current settings audit

| Current control | Current implementation | Risk / finding | Required behavior |
| --- | --- | --- | --- |
| DSH `transcriptView` | `hostChoice` → `saveHost` → `settingsSet` | RPC mapping and revision tests exist; Select falls back to option 0 if current value is unknown. Shared busy/global error makes failure look inert. | Per-row pending, explicit unknown state, inline retry; hide if `ui-chat` absent. |
| DSH `collapseTiming` | Same Host path | Works only for writable `ui-chat`; disabled state has no explanation. | Explain unavailable/read-only; preserve scope across navigation. |
| DSH `foldedReplies` | Same Host path, conditionally hidden for verbose | Can remount and flash when mode changes; no row pending indicator. | Deterministic visibility and cached values. |
| DSH `busyEnter` | `ui-conversation` Host path | Correct namespace but mixed into General; capability failure is only a global error. | Keep in DSH settings, row-level status. |
| Theme Light/Dark/System | `theme()` → Bridge `themeMode` | Bridge validates and persists, but one global busy blocks all three buttons and failure is only status text. | Per-selection pending; readback and rollback; immediate scrim/theme update after commit. |
| Reduce motion | `setting('reduceMotion')` → `NativeExperience` | Persists and updates AppStorage. `detail` argument is currently ignored, so no explanation or availability state. | Keep, add description and per-row progress. |
| Reduce transparency | `setting('reduceTransparency')` | Same persistence path; no explanation of capability fallback or effect. | Keep, state effective fallback on old API/materials. |
| Notify approvals/completion/failure | Three booleans stored in one JSON object | State writes work locally, but toggles share one busy flag. There is no notification tier model yet. | Migrate to tiered per-category model; per-category pending; preserve older booleans. |
| Enable/disable Push Kit | `action('enablePush'/'disablePush')` | Works only when supported and server configured; global row looks clickable before capabilities are known. | Disabled capability row with reason; pending state; device registration result surfaced. |
| Background monitoring | `setting('backgroundMonitor')` | Store variant requests notification permission and updates AppStorage. It is only shown when Push is unsupported. No long-running active/failed state. | Separate background-delivery setting, runtime state, permission failure and stop conditions. |
| Show task name on card | `setting('widgetDetails')` → `WidgetStore` | Handler exists, but row can appear enabled before initialization and result is only transient global status. | Per-row state; privacy-off must immediately sanitize card snapshot. |
| Sync card now | `action('sync')` fetches overview then `widgetSnapshot` | Works in code; no visible progress on the row and stale/offline result is only global. | Row spinner, timestamp/result, retry. |
| Interface mode | Opens mode sheet through `onModes` | Functional, but Settings remains as an opaque layer and sheet wording is long. | Move under a clear root destination; preserve connected/chat state; compact copy. |
| Connection and login | Opens `connectionPage` | Back is hand-wired via `openPage('root')`; system Back also resets payload, but route model is just one string and future pages are fragile. | Typed route stack; secondary Back → root. |
| Logout | `action('logout')` | Server logout is best effort and local cleanup is available, but the row only has opacity feedback. | Confirmation only if required by current policy; per-row progress and failure reason. |
| About | Currently a horizontal tab | It looks like leaving the Settings shell and makes Back ambiguous. | A secondary root row with stable header/back. |
| General/Application categories | Horizontal tab buttons | Violates SET-01 and separates controls that belong together semantically. | Vertical information architecture above. |

No code path was found that intentionally makes every local setting a no-op.
The observed "large numbers do not work" is most plausibly the combination of:

- controls are globally disabled while one setting is pending;
- capability-gated controls look active before state is known;
- errors are distant, short-lived, or visually unchanged;
- horizontal tabs and detached About make context appear to disappear;
- some rows render but have no Host/remote capability and no explanation.

### 5.4 Bottom immersive treatment

The Settings root column has a background but its content only gets static bottom
padding (`NativeSettings.ets` root build, near line 400). It does not currently
use the measured bottom safe area.

The page background and system bar must share the Settings theme and extend under
the gesture area. Scroll content gets `nativeSafeBottom + content padding`;
About is the same Settings secondary page rather than an exception.

## 6. Global destinations

The three fixed entries are global application surfaces:

- Plugins belongs to `pluginManager`/`pluginMarket` or their compatibility view.
- Automation tasks belongs to the schedule catalog, changed events and task
  detail flow.
- More belongs to registered global actions/views and workspace management.

Availability is capability-driven. A missing native implementation opens a named
compatibility destination or shows an accurate unavailable state; it must not be
a decorative row. Do not hard-code undocumented page paths solely from a guessed
URL.

## 7. Validation

Pure/state tests:

- Last-session resolution priority and invalidation.
- Drawer state machine and Back precedence.
- Selection highlighting independent of drawer visibility.
- Settings migration from three booleans/horizontal categories.
- Per-control optimistic update, rollback and concurrent independent writes.
- Redaction of origin/secret data in logs.

CLI build:

- `NativeMetadataCache`, `NativeNavigation`, settings and list reducer tests.
- ArkTS Release build after the drawer/settings implementation.

Device E2E:

- Cold start opens the last conversation; notification overrides it; archived
  target falls back cleanly.
- Drawer overlays without resizing or unmounting chat, retains scroll/draft, and
  closes by scrim, Back, swipe and session selection.
- Screenshot ordering and fixed bottom Settings match the requested composition.
- Dark/light, automatic theme, reduced motion, large text, split-screen and
  rotation preserve safe areas and usable widths.
- Every Settings row and subpage is exercised twice to confirm persistence and
  rollback behavior. No row may silently do nothing.
- Plugins, Automation tasks, More and About each reach a real destination.
