# Plan Expansion Stability and Immediate File Preview Specification

Date: 2026-10-31

## Plan Expansion

Chat process groups continue to group contiguous tool, reasoning and notice
events into one turn-level disclosure. Each direct child receives a view-only
`renderKey` projected from:

```text
process group identity + event sequence + child ordinal
```

The event sequence and ordinal make the key unique even when an upstream source
reuses an event-derived `id`. The key remains stable while later events append
to the same group. It is presentation metadata and never changes protocol
identity or durable transcript records.

`NativeProcessView` keys its `LazyForEach` source by `renderKey`.
`NativeProcessStepView` uses the same key for disclosure state. `NativeListSource`
also appends a deterministic occurrence suffix if a caller supplies duplicate
keys, protecting other lists from the same ArkUI invariant.

The plan tool continues through `NativeToolCallView` with `hideHeader` and
`forceExpanded`; no extra disclosure level is introduced. Diff projection is
restricted to edit and write tools because arbitrary plan arguments are not a
patch source. `NativeDiff` also rejects null parsed roots and null array entries
so malformed optional metadata cannot terminate the app. Plan arguments and
output use the existing read-only text and rich-content renderers.

## Immediate Preview Shell

Clicking a local Markdown link follows this order:

1. Resolve only the lightweight relative target string.
2. Publish a `NativeFileViewRequest` with a unique `requestId`.
3. `NativeWorkspace` opens `NativeFilePreview` immediately.
4. Start background validation and file loading.

The background validator calls `statFile` after the shell has mounted. If the
exact file is valid, no navigation change is needed. If the exact path fails,
the validator may resolve a unique basename through the existing bounded
workspace search. If the target is a directory, listing succeeds and the same
request is replaced by a browser request.

Late results may publish only while the current AppStorage payload still has
the same `requestId`. Closing the overlay clears that payload, so a pending
stat, search or list response cannot reopen it. Opening another link assigns a
new request id and invalidates the older resolution.

## Preview Loading

`NativeFilePreview` mounts with its title, controls and loading indicator before
any network request completes.

Text-like files begin `workspaceFiles/read` immediately. Image and SVG previews
begin `workspaceFiles/readBytes` immediately. Both responses already include a
file version, so the old mandatory `statFile -> content` sequence is removed
from the content path. A metadata probe may run in parallel to refine the size
label, but it cannot delay content.

The gateway includes file-window metadata in
`X-DSH-File-Window`. HarmonyOS does not expose that custom header reliably from
`requestInStream`, especially on the first request after a cold start. Empty
fallback metadata must therefore not be treated as a user-visible preview
failure. When the header is absent and no expected version was supplied,
`NativeHarnessClient.readFileBytes` keeps the bytes already received, obtains
the file version and total size through `statFile`, and derives the file window
locally. Pending stat requests are deduplicated by session and path, so the
preview's parallel size probe shares this request.

The preview retains one bounded retry for real transient reads or a changed
file version. Only a second definitive failure reaches the visible error state.

Code mode for SVG still uses the existing text endpoint. The preview/download
mode switch continues to share the same mode control and read-only contract.

## Failure and Cancellation

- Invalid file content produces the existing in-surface error and retry action.
- A directory switches to the file browser once detection completes.
- An unavailable path keeps the immediate shell until loading fails, then shows
  a concise error; it is never represented as an endless spinner.
- A closed or superseded request never mutates the active overlay.

## Verification

- Transcript model tests assert that repeated child IDs receive unique stable
  render keys and that later streaming appends preserve earlier keys.
- Source-contract tests assert that the request is published before `statFile`
  and that preview content no longer awaits `statFile`.
- Device tests expand a completed plan repeatedly, open file and folder links,
  cold-start and open multiple images without tapping retry, close while
  resolving and verify no stale overlay reopens.
- Both Release product variants are built after the shared ArkUI changes.
