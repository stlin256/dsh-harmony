# Native Shell, Performance, Settings, Push and Widget Requirements

Date: 2026-10-30

Status: recorded before implementation. This document is the source list for the
research and implementation specs produced in this work cycle.

## Navigation shell

| ID | Requirement |
| --- | --- |
| NAV-01 | On a warm or cold app start, restore and open the last active conversation when it is still valid and available. Do not land on the workspace list when a last conversation can be restored. |
| NAV-02 | If the last conversation is archived, removed, unauthorized or otherwise unavailable, fall back deterministically to the session list or workspace home without showing a broken chat. |
| NAV-03 | The workspace/session list is a left-side overlay drawer, not a full-screen navigation page. The conversation remains visible behind a scrim and keeps its scroll and input state. |
| NAV-04 | The drawer is narrower than the window, respects all system safe areas, supports edge-swipe open and swipe/back close, and uses HarmonyOS-native drawer motion and scrim animation. |
| NAV-05 | The top row contains the bold application name and a search icon. Global search covers workspaces and visible sessions. |
| NAV-06 | Below the top row, show the primary new-conversation button. |
| NAV-07 | Below the new-conversation button, show these destinations in order: Plugins, Automation tasks, More. |
| NAV-08 | Below those destinations, show workspace groups and their sessions. Groups can be expanded/collapsed, searched, filtered, sorted, pinned and managed without shrinking the conversation layout. |
| NAV-09 | The current conversation is visibly selected in the drawer. Exiting chat or changing groups must not leave stale selection highlighting. |
| NAV-10 | Settings is a fixed bottom item in the drawer, separated from the scrollable workspace region. |
| NAV-11 | The drawer and conversation use the DSH semantic icon style, compact spacing, light/dark themes, reduced-motion behavior and accessible labels. |

## Settings

| ID | Requirement |
| --- | --- |
| SET-01 | Replace horizontal settings tabs with one vertically navigable settings structure. The hierarchy and visual language follow the DSH interface. |
| SET-02 | Every displayed setting control must be wired to persistent state and a concrete action. Disabled or unavailable controls must state why and must not look enabled. |
| SET-03 | Audit toggle, selector, text field, navigation row, destructive action and account action behavior one by one. Values must survive leaving and reopening settings. |
| SET-04 | Secondary settings screens preserve settings context and provide predictable back navigation; back must not jump directly out of settings. |
| SET-05 | The settings page extends behind the bottom gesture area with a theme-correct immersive background while keeping interactive content above the safe area. |

## Conversation loading, cache and virtual scrolling

| ID | Requirement |
| --- | --- |
| PERF-01 | Persist conversation content in app-private local storage so a previously opened conversation renders from cache before network refresh. Store enough message metadata and content to restore the visible transcript, tool/process state and pagination cursors. |
| PERF-02 | Use stale-while-revalidate: cached content renders immediately, then a background refresh applies newer revisions and sequence cursors incrementally. |
| PERF-03 | Persist all opened conversation content, including messages, code, reasoning, tool results and structured blocks. Cache is segregated by server identity and session, cleared on logout, and bounded by an explicit retention/eviction policy. |
| PERF-04 | Preload older history aggressively before the user reaches the top. Scroll-direction prediction, distance thresholds and concurrent page limits must prevent repeated manual pulls and visible stalls. |
| PERF-05 | Prefetch adjacent or recently used sessions where useful, coalesce duplicate requests, and retain in-flight/request cursors across UI rebuilds. |
| PERF-06 | Render long conversations through virtualized/lazy lists with bounded item caches. Cached data must not cause the entire transcript to render at once. |
| PERF-07 | Cache and preload work must survive reconnect and must not show a disconnected banner merely because a background refresh is pending. |
| PERF-08 | History replacement, archiving, deletion, logout and server changes must invalidate the correct cached records without deleting unrelated sessions. |

## Markdown and message presentation

| ID | Requirement |
| --- | --- |
| MD-01 | Verify native fenced-code rendering. Add syntax highlighting for common programming languages when it is absent, including light/dark token colors and safe fallback for unknown languages. |
| MD-02 | Syntax highlighting must preserve copy, horizontal scrolling, selection/readability and very long code blocks without parsing the entire conversation on every scroll. |
| MSG-01 | For a completed assistant reply, place the completed indicator and copy action on the same compact footer row. |
| MSG-02 | The footer must align with the DSH message content width and remain legible in both themes without adding excessive explanatory text. |

## Push notifications

| ID | Requirement |
| --- | --- |
| PUSH-01 | Replace a single notification switch with tiered preferences. Define levels for task completion, task failure, approval/input required, and optional system/connection events. |
| PUSH-02 | Levels must distinguish disabled, silent/background only, normal notification, and prominent/alerting where the HarmonyOS entitlement permits it. Unsupported categories must degrade safely. |
| PUSH-03 | Notification settings must work for both the Push Kit self-built variant and the store-oriented variant without Push Kit entitlements. |
| PUSH-04 | Push Kit delivery stores no chat body and deep-links to the correct conversation, including cold start. |
| PUSH-05 | The no-Push-Kit variant may use the existing background-monitor option to receive task signals while active; it must stop and clean up when disabled, logged out or finished. |
| PUSH-06 | Server and app must apply the same per-level filtering contract, with retries, deduplication, expiry and logout revocation preserved. |

## Widgets and desktop cards

| ID | Requirement |
| --- | --- |
| CARD-01 | Define a deterministic widget update plan tied to task lifecycle events, app foreground sync and bounded periodic refresh. Avoid updating on every token or streaming delta. |
| CARD-02 | Card layouts show task state, title, workspace context where permitted, counts and a direct conversation target. Do not expose chat body or secrets. |
| CARD-03 | Define compact, medium and expanded information priorities, empty/offline/loading states, privacy defaults and light/dark appearance. |
| CARD-04 | Card taps must route to the same session identity used by notifications and the drawer. |

## Delivery sequence

1. Commit this requirements record.
2. Produce focused research records without production-code edits.
3. Produce implementation specs with contracts, migrations and validation.
4. Commit each spec or coherent documentation phase.
5. Implement the navigation shell and settings architecture.
6. Implement persistent cache, preload and virtual scrolling.
7. Implement Markdown highlighting and message footer polish.
8. Implement push tiers and widget update/layout contracts.
9. Run local tests and Release builds after each coherent implementation phase.
10. Only after all code is complete, connect the device for one consolidated E2E pass.
11. Fix E2E gaps, then create the release tag and publish without checking GitHub Actions.

## Privacy and compatibility constraints

- The public repository must not contain the owner's private service hostname, IP addresses, cookies, credentials, signing material or real conversation bodies.
- Passkey and native login behavior must remain compatible.
- Existing data and signed updates must preserve login/session state where possible.
- Cached transcript content must live only in the app sandbox and must be removed by logout or explicit cache clearing.
- The implementation must remain compilable from CLI without starting DevEco Studio GUI or computer-use automation.
