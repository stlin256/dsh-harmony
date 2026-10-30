# Transcript Cache, Aggressive Preload and Virtual Scrolling Research

Date: 2026-10-30

Scope: PERF-01 through PERF-08 in
`docs/requirements/2026-10-30-native-shell-performance.md`.

This document records current code behavior and a recommended design. It does
not claim device performance results.

## 1. Current behavior

### 1.1 Persistent cache only covers navigation metadata

- `NativeMetadataCache` stores up to 200 sessions and workspace membership in a
  Preferences entry. Its comment and implementation explicitly exclude message
  bodies.
- `NativeHarnessClient.models` and `NativeWorkspace.model` are in-memory objects.
  Drafts, image drafts, uncertainty state, loaded history, disclosures and
  stream text all disappear when the process exits.
- `NativeSessionModel` retains the complete text of loaded messages; it does not
  truncate message bodies. The gap is persistence, not content truncation.
- `NativeHarnessClient.clearLocalState()` clears only in-memory state.
  `Index.resetConnectionState()` clears navigation metadata and selected
  in-memory maps, but there is currently no persistent transcript store to
  remove.

Consequence: a process restart always opens the workspace list, and even an
in-process session switch is fast only when that `NativeSessionModel` is still
in the `models` map.

### 1.2 The first chat window depends on the live socket

- The gateway starts a selected-session follow stream with
  `maxMessages: 24` (`gateway/src/native-harness.mjs`, selected-session follow).
- `NativeWorkspace.select()` creates or retrieves an in-memory model, renders
  it, then calls `follow()`.
- `follow()` changes the phase to `syncing`; the conversation shows the loading
  row until the live `snapshot` arrives.
- `hydrateHistory()` exists, but there is no call site. It is dead code and does
  not provide a cached or optimistic first paint.
- The page endpoint requests at most 60 normalized messages
  (`native-harness.mjs`, `/pocket/api/native/page`).

Consequence: a cold chat opening waits for WebSocket setup, upstream history and
normalization before readable content appears. A socket delay is easily
perceived as slow loading, even before there is a real retryable failure.

### 1.3 Older history is requested only after reaching the exact top

- The list calls `older()` only from `.onReachStart()`.
- `older()` permits one request at a time and leaves the default visible page
  button as another manual path.
- There is no distance trigger, scroll-direction prediction, background pager or
  next-page prefetch.
- The list source reloads after each page. It attempts to preserve an anchor with
  `getItemRect` and `scrollToIndex`, but the page sentinel participates in index
  arithmetic, making this fragile.

Consequence: a user can reach the top repeatedly and wait for one page each
time. Repeated downward drags are expected with the current algorithm.

### 1.4 Lazy components exist, but projection still processes all loaded rows

- The conversation already uses `LazyForEach` and `cachedCount(6)`, so ArkUI
  does not instantiate every off-screen row.
- `MessageSource.set()` emits a full `onDataReloaded()` for almost every update,
  including a streaming token that only changes the tail.
- `paint()` calls `nativeTranscript()` and `nativePresentTranscript()` over the
  complete model, then replaces the full source array.
- Prior synthetic research measured projection growth from about 0.33 ms at
  100 visible rows to 44.12 ms at 3,200 visible rows on the desktop runtime.
  This is not a phone benchmark, but it proves that LazyForEach alone does not
  bound model-side work.
- `NativeSessionModel.apply()` uses repeated array concatenation and replacement
  filtering. Every stream tick therefore has work proportional to the loaded
  history.
- The current normalized transport repeats a long text body in several fields
  (`text`, blocks/segments projections, raw content and journal). Prior synthetic
  measurement showed about 6x payload expansion for a simple long assistant
  message. A larger initial window would multiply transfer, parse and storage
  cost unless the payload is compacted.

Consequence: simply increasing `maxMessages`, `cachedCount`, or fetching every
page into memory would make jank worse. Persistence, bounded projection and
incremental source updates must ship together.

### 1.5 Request deduplication is incomplete

- `state()`, `sessions()` and `workspaces()` collapse concurrent calls.
- `page()` does not deduplicate. Reconnect, selection and a manual older action
  can request the same page independently.
- There is no durable per-session pager state or low-watermark scheduler.
- Late page responses are checked against `selected` and `mounted`, but they are
  not stored if the user switches away. Potential useful cache is discarded.

### 1.6 Reconnect behavior is better than the first-load path, but not incremental

- `NativeSessionModel.apply(snapshot)` preserves loaded rows before the new
  snapshot boundary and applies replacement ranges.
- `NativeSessionModel.prepend(page)` deduplicates rows by sequence and honors
  replacement ranges.
- Those model rules are a solid base.
- The client still has no durable cache to hydrate before reconnecting, so the
  model rules only help within the same process.

## 2. Recommended storage architecture

Use an encrypted HarmonyOS relational database for durable transcript content.
Preferences are appropriate for route identity and small settings; they are not
appropriate for multi-megabyte conversations.

### 2.1 Store boundary

Open one app-private encrypted RDB with `encrypt: true` and the strictest
practical local security level. The database must never be imported by the
widget/form extension or exposed to ArkWeb.

Recommended logical tables:

| Table | Purpose |
| --- | --- |
| `cache_scope` | Hashed gateway/login scope, schema version, last access, total bytes and retention metadata. Never store a raw cookie or URL here. |
| `session_state` | Session id, title snapshot, cursor, `beforeSeq`, `historyCut`, `hasMore`, running/waiting flags, active attempt revision, last access and byte count. |
| `message_row` | One normalized `NativeMessage` JSON row keyed by `(scope, session, seq)`. Insert only when changed; delete by replacement range. |
| `loaded_range` | Non-overlapping sequence ranges successfully loaded into `message_row`, including `throughSeq`, `beforeSeq` and whether the range touches the start. |
| `replacement_range` | Applied surface replacement ranges. Delete matching message rows in the same transaction. |
| `stream_checkpoint` | Active attempt id, next index, accumulated text/reasoning and last persisted time for crash recovery. |
| `attachment_ref` | Attachment id, media type, dimensions and app-private file path/hash; image bytes live outside the database. |

`message_row.payload_json` should contain one canonical normalized message
object. Do not persist `text`, every rich block, segment projection, raw content
and journal copies in separate columns. Derived blocks and process grouping are
rebuilt lazily. If raw event inspection is required later, persist one capped
raw record in a separate optional table rather than duplicating user text in
every render representation.

### 2.2 Identity and isolation

- Use the existing hash derived by `NativeHarnessClient.cacheKey()` as
  `scope_id`; do not persist the source cookie.
- A different login scope must not see an older scope's rows.
- Startup validates the last active session against freshly loaded navigation
  metadata. A missing, archived or unauthorized session falls back without
  flashing its cached transcript.
- Logout deletes the active scope database rows and attachment directory in a
  cleanup transaction/job. Changing server also drops the old in-memory client
  generation immediately.

### 2.3 Consistency

- Insert messages and update range/cursor state in one transaction.
- Upsert by `(scope, session, seq)`. A newer snapshot wins for range ownership;
  an older page must not overwrite a row already removed by replacement.
- Persist `historyBefore` only after the corresponding range is committed.
- Do not infer contiguous history from filtered UI messages. Persist explicit
  successful page ranges.
- On a corrupt row or unsupported schema version, discard only that session's
  cache and rebuild from Host; do not prevent login.
- Checkpoint active assistant text at a low frequency (suggested 500 ms) and
  force a final checkpoint on end/background. Never write on every token.
- Serialize writes in one asynchronous queue and batch in transactions to avoid
  UI-thread stalls.

### 2.4 Retention

- Keep every loaded message and structured block for opened sessions.
- Use a global byte quota with LRU eviction of inactive sessions. Suggested
  starting point: 512 MiB, user-adjustable or clearable from settings.
- Never evict the active session, a session with an unsent draft/attachment, or
  an unconfirmed submission.
- Attachment image bytes use the same retention policy but remain outside the
  text database.
- Do not truncate a large message to meet quota. Evict whole inactive sessions
  instead.

## 3. Cache-first lifecycle

```text
connect
  -> resolve navigation metadata (cache first, network refresh in parallel)
  -> resolve last-active route
  -> load cached session window and checkpoints
  -> paint readable chat immediately
  -> open one selected-session live stream
  -> validate/merge authoritative snapshot
  -> persist new rows
  -> start low-priority history pager
```

Rules:

1. Cached chat remains readable while the WebSocket is `syncing`.
2. The reconnect banner appears only after a real failed attempt, not while the
   initial cache refresh is pending.
3. Resolve the last active conversation from a small persisted route record,
   separate from transcript rows. Validate it against fresh metadata.
4. Restore the nearest saved reading anchor after hydration. On a normal re-open
   without an anchor, open at the latest readable tail.
5. Publish one cache generation at a time. Late responses from an older scope,
   session or route generation may be committed to their own cache but must not
   mutate the visible model.

## 4. Aggressive but bounded preload

### 4.1 Initial window

- Paint all immediately available cached rows around the saved anchor or tail.
- After the first valid live snapshot, do not issue a duplicate HTTP page for the
  same boundary.
- Run a low-priority pager against `historyBefore`/`historyCut` until at least
  180–240 messages or three 60-message pages are available around the current
  position.
- Continue filling the complete history when the app remains active, but yield
  between pages and pause on hidden app, screensaver/lock-like inactive state,
  or explicit power-saving mode.

### 4.2 Scroll-driven prefetch

- Estimate motion from consecutive `onScroll` measurements and
  `onScrollFrameBegin`; detect movement toward older content without relying on
  an unverified sign until device validation.
- Start fetching when the first visible row is within roughly 20–24 rows of the
  loaded start, before `onReachStart`.
- Request one page immediately and queue a second while the user continues
  toward the top. Keep at most one upstream page request per session active;
  allow at most two sessions to prefetch concurrently.
- `onReachStart` remains a final fallback, not the normal load trigger.
- Coalesce requests by `(scope, session, beforeSeq, throughSeq)` and reuse an
  in-flight Promise.
- Stop on `hasMore=false`, repeated cursor, empty page, route invalidation,
  logout or an unrecoverable page error. Retry transport errors with backoff,
  not an infinite immediate loop.

### 4.3 Recent session warmup

- After the current chat is readable and its first prefetch is committed, warm
  metadata for the most recent two or three visible sessions.
- If the device is not in power-saving mode, hydrate each from disk; network-page
  warmup is lower priority than the active chat and should be bounded to one
  page/session per idle cycle.
- A prefetched response is persisted even if the user has switched sessions;
  it is applied to UI only if scope/session/generation still match.

### 4.4 Large payload protection

- Keep every actual message, but pace by both record count and bytes.
- Yield after a page whose decoded payload is large. Do not append another page
  in the same frame.
- Compact the native snapshot/page protocol so display text is not repeated in
  six representations. A compatibility decoder can support older responses.
- Never solve memory pressure by silently deleting parts of a user-visible
  message.

## 5. Virtual scrolling and incremental publication

### 5.1 UI virtualization

- Keep `LazyForEach` with stable message keys and increase `cachedCount`
  modestly from 6 to about 8–12 after device measurement.
- Do not create rich UI bodies for collapsed process groups, off-screen code
  blocks or closed image previews.
- Preserve `List` item identity across prepend and append.
- Keep both the tail and the anchor in the virtualized model. For very long
  histories, a DB-backed window can retain at most roughly 600–800 normalized
  rows around visible content while the complete cache remains on disk.

### 5.2 Data-source updates

Replace full reload behavior with precise notifications:

- append one settled message: `onDataAdd` or equivalent insertion notification;
- prepend an older page: insert a range and then restore the visual anchor;
- streaming tail: change only the affected stable item;
- replacement: delete/replace only affected rows;
- metadata-only updates: do not rebuild the transcript source;
- process disclosure: rebuild only that process group or affected turn.

The first implementation can continue publishing whole arrays if ArkUI
notification APIs make partial updates risky, but it must skip publication when
the row identities and render revision have not changed.

### 5.3 Projection cost

The cache work depends on removing current projection hot spots:

- pre-index turns, calls, user boundaries and replacement ranges;
- recompute only the changed turn plus its presentation row;
- retain stable projection rows across streaming updates;
- avoid full `concat`, `filter` and `some` over all loaded history per token;
- debounce at frame rate rather than every model mutation;
- defer rich syntax/table parsing off-screen or cache parsed blocks by message
  revision.

## 6. Failure and migration behavior

- Existing users have no transcript cache. First launch after upgrade creates
  the database lazily and falls back to the current network path.
- A cache open/migration failure is scoped to caching: the app still logs in and
  loads from network.
- A corrupted session row is removed; a corrupted database may be recreated only
  after preserving no credentials (none belong in it).
- A network page failure keeps cached rows visible and offers a compact retry
  affordance. It does not become a global disconnected banner unless the live
  transport is truly failing.
- On logout, hide cached content before asynchronous deletion completes so the
  next login cannot briefly see another identity.
- If history replacement arrives while a page request is in flight, commit the
  replacement first and validate the page against the replacement map before
  insertion.
- If assistant stream attempt changes, clear the checkpoint for the old attempt.

## 7. Metrics and acceptance targets

Collect content-free local counters only:

| Metric | Definition |
| --- | --- |
| `cacheRows` / `cacheBytes` | Committed normalized rows and bytes by scope/session. |
| `cacheFirstPaintMs` | Route select to first cached readable row; N/A on first-ever open. |
| `authoritativeReadyMs` | Route select to validated live snapshot merge. |
| `prefetchPages` | Pages requested before user reaches start. |
| `pageDedupHits` | Requests served by an existing in-flight page. |
| `projectionMs` | Publish/change stage duration, reported as p50/p95. |
| `frameDrops` | Long frames during scroll/prepend/stream, bucketized. |
| `cacheEvictions` | Whole sessions evicted by quota, never partial content. |

Initial acceptance targets:

- A warm process with cached data paints readable chat without waiting for HTTP
  or WebSocket.
- Reopening a cached conversation does not display “connection interrupted”
  during refresh.
- Reaching the top normally never requires more than the initial visible load
  action because older pages are already preloaded.
- Repeated upward scrolling starts prefetch before the top edge and does not
  produce duplicate page requests.
- Scroll anchor remains visually stable when a page is prepended.
- Appending a short message or streaming token does not cause a full transcript
  source reload or full history re-projection.
- Cache clears on logout; another scope cannot load the prior rows.
- A 2,000-message synthetic session scrolls without rendering all messages at
  once; real phone p50/p95 and memory are recorded only during consolidated E2E.

## 8. Automated tests

1. Relay/store adapter tests for encrypted database schema migrations.
2. Cache scope isolation by origin/login hash; logout purge; corrupt-row
   fallback.
3. Snapshot merge with cached older rows and replacement ranges.
4. Page prepend deduplication, explicit gap tracking and cursor-cycle rejection.
5. Late page after route switch is persisted but not published.
6. In-flight page deduplication and bounded concurrent prefetch.
7. Active attempt checkpoint save/restore/attempt-change discard.
8. Quota eviction excludes active, draft and uncertain sessions.
9. Source notification tests: append changes one row; prepend inserts a range;
   disclosure changes one turn; metadata update does not reload transcript.
10. Projection benchmark for 25/100/200/400/800 turns, checking that streaming
    does not scale with all turns.
11. Page size/bytes pacing and power-saving/yield behavior.
12. Legacy app behavior when database initialization fails.

## 9. Consolidated E2E pending after implementation

- Cold start with a valid saved conversation; confirm it opens the chat from
  cache before the network becomes available.
- Kill and reopen the app repeatedly; verify reading position, drafts, expanded
  process groups and structured content restore.
- Scroll rapidly upward and use fling; confirm prefetch starts early, no repeated
  “更早” taps, no anchor jump, and no full-history slow paint.
- Put the device briefly offline while cached chat is displayed; verify readable
  cache remains and only the real retry banner appears.
- Reconnect and verify newer events merge without duplicates or resurrected
  replaced content.
- Open several large sessions, return to each, and verify all previously loaded
  content is available incrementally.
- Exercise process details, code blocks, tables, images, files and diff blocks
  during cached/virtualized scrolling.
- Switch to another login or logout; verify no previous transcript appears and
  the old scope is removed.
- Measure cold cache paint, authoritative refresh, projection p95, long frames,
  page counts and memory under normal and power-saving modes.
