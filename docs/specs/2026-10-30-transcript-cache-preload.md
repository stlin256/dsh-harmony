# Transcript Cache, Preload and Virtualization Implementation Specification

Date: 2026-10-30

Requirements:
[PERF-01 through PERF-08](../requirements/2026-10-30-native-shell-performance.md)

Research:
[Transcript cache, aggressive preload and virtual scrolling](../research/2026-10-30-transcript-cache-scroll.md)

## 1. Outcome

Previously opened conversations paint readable content from app-private local
cache before the network refresh. New data merges incrementally. Older pages are
preloaded before the user reaches the top, while the rendered viewport remains
bounded by a lazy list and a bounded in-memory window.

Cache-first behavior must not hide real transport failures. The reconnect banner
appears only after a failed live attempt, not while a cache or initial refresh
is loading.

## 2. Storage boundary

Use an encrypted app-private relational store. The implementation may stage the
service behind an interface, but persisted production content must not be placed
in a public directory, widget extension storage, ArkWeb storage or source
control.

Logical schema:

```text
cache_scope(scope_id, schema_version, last_access, bytes)
session_state(scope_id, session_id, navigation_json, before_seq,
              through_seq, history_cut, has_more, updated_at, last_access)
message_row(scope_id, session_id, seq, revision, payload_json, bytes)
loaded_range(scope_id, session_id, before_seq, through_seq, complete, bytes)
replacement_range(scope_id, session_id, from_seq, through_seq)
stream_checkpoint(scope_id, session_id, attempt_id, text, reasoning, updated_at)
route_state(scope_id, selected_session_id, last_opened_at)
```

`payload_json` stores one canonical normalized message. Derived Markdown blocks,
process groups and syntax tokens are rebuilt from source/revision and are not
six duplicate copies of the same text.

Scope identity uses the existing one-way gateway/login cache key. Raw URLs,
cookies and secrets do not enter the database. Rows of another scope are never
returned after an identity switch.

## 3. Service interfaces

Introduce a `NativeTranscriptCache` service with asynchronous methods:

```text
openScope(scopeKey): Promise<void>
loadRoute(scopeKey): Promise<RouteRecord | undefined>
saveRoute(scopeKey, sessionId): Promise<void>
loadSession(scopeKey, sessionId, window): Promise<CachedSession>
appendSnapshot(scopeKey, session, snapshot): Promise<void>
prependPage(scopeKey, session, page): Promise<void>
saveStreamCheckpoint(...): Promise<void>
clearSession(scopeKey, sessionId): Promise<void>
clearScope(scopeKey): Promise<void>
trimToQuota(): Promise<void>
```

Writes are serialized and transactional. Snapshot message rows, cursor updates
and replacement deletion commit together. A late response from an old scope,
session or generation may be persisted in its own cache but must not mutate the
visible model.

## 4. Cache-first lifecycle

1. Resolve cached navigation and route metadata.
2. Load the last valid session around its saved anchor or latest tail.
3. Publish cached rows immediately with connection phase `syncing`, not
   `retrying`.
4. Open one live follow stream for the selected session.
5. Merge the authoritative snapshot and persist the new rows/ranges.
6. Start a low-priority history pager for the remaining older range.
7. Warm recently used sessions only while the current session is readable and
   no higher-priority request is waiting.

If no cache exists, show the compact loading state once and use the existing
live snapshot path. Do not issue a duplicate HTTP page for a range already
covered by the snapshot.

## 5. Preload policy

Normal active policy:

- maintain at least 180 messages or three 60-message pages;
- detect movement toward older content within 20 messages of the loaded start;
- request one page immediately and queue at most one more;
- allow one in-flight page per session and at most two prefetching sessions;
- coalesce requests by scope/session/beforeSeq/throughSeq;
- keep manual “older” as a fallback, not the common path;
- stop on no-more, repeated cursor, empty page, invalid route or logout.

The active conversation has priority over recent-session warmup. Warmup loads
cached content for two or three recent sessions and makes at most one network
page request per session in an idle cycle.

Page pacing uses both row and byte limits. A large response yields before the
next request. Power-saving/background modes pause network prefetch while
preserving already loaded content.

## 6. Virtualization and publication

The UI keeps `LazyForEach` with stable keys. Increase `cachedCount` only after
measurement, starting at 8. The in-memory transcript window is bounded; the
database may hold complete opened histories beyond that window.

Publication rules:

- append inserts one settled row or a page range;
- prepend inserts range rows while preserving the visual anchor;
- a streaming tail updates only the affected stable item;
- replacement removes/replaces only matching ranges;
- navigation metadata does not rebuild the transcript source;
- disclosure rebuilds only the affected process group/turn;
- unchanged row identity plus render revision does not publish a reload.

`nativeTranscript()` must index turns and final assistant ownership once per
model revision. Streaming must not scan and concatenate the full loaded history
on every token.

## 7. Reliability and retention

- Checkpoint streaming text at about 500ms and on end/background.
- Delete an old attempt checkpoint when the attempt changes.
- Upsert messages by sequence; honor replacement ranges before inserting a late
  page.
- On a corrupt session, discard that session cache and rebuild from Host.
- On database open/migration failure, continue with network loading.
- Use a global byte quota, initially 512 MiB, and evict whole inactive sessions.
- Never evict the active session, a draft with attachments or an unconfirmed
  submission.
- Logout immediately hides cached content, then deletes rows and app-private
  attachment files.

## 8. Metrics

Collect content-free counters:

- cache rows/bytes;
- cache first-paint duration;
- authoritative snapshot duration;
- prefetch page count and dedup hits;
- projection p50/p95;
- dropped-frame counters;
- whole-session evictions.

Warm cached data should produce readable content without waiting for network.
Initial acceptance targets are first cached paint under 200ms and projection p95
under 16ms; these are measured during device E2E and are not claimed before
that test.

## 9. Tests and acceptance

Automation:

- scope isolation, migration, corrupt-row fallback and logout purge;
- snapshot merge over cached older rows and explicit gaps;
- page prepend dedup and replacement-aware rejection;
- duplicate in-flight request coalescing;
- late response persisted but not published after route switch;
- stream checkpoint restore and attempt invalidation;
- quota eviction excludes active/draft sessions;
- prefetch boundary, cursor-cycle and byte-yield behavior;
- projection does not scan all turns for a tail delta.

Device E2E:

- kill/reopen several times and verify cache-first restore and saved anchor;
- open with network slowed/off and confirm readable cache without false
  disconnected banner;
- fling upward repeatedly and confirm early page prefetch, no duplicate loads,
  no anchor jump and no full-history paint;
- reconnect and verify no duplicate or resurrected replaced messages;
- exercise large sessions with rich blocks, tables, images and diffs;
- switch login/logout and verify no cross-scope content;
- record first-paint, p95 projection, frame drops and memory.
