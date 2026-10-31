# Latest DSH Stream Recovery and Native Composer Attachments

Date: 2026-10-31

Status: implementation in progress; device validation pending.

## Scope and baseline

This specification follows the current upstream contract at
[`deepseek-ai/deepseek-harness@ce7073d`](https://github.com/deepseek-ai/deepseek-harness/tree/ce7073d51254c26cd63b22a60835b8f948deb447).
The new DSH-only requirement is deliberate: do not add another compatibility
mode, protocol inferer, or fallback composer for older versions.

The app and its bundled gateway/plugin must consume the same corrected
assistant-stream contract. Fixing only the ArkUI client would hide the frame
loss inside the gateway and leave reconnect behavior untestable.

## Evidence from the current implementation

- `NativeHarnessClient.follow()` arms a 20-second timer only for socket opening.
  After open, it has no application-level heartbeat or no-frame watchdog.
- `NativeWorkspace` reconnects after close, error, an error frame, or a frame
  handler exception. A half-open socket has none of those events.
- `normalizeFollow()` currently drops the opening `assistantStream.revision`,
  `startedAfterSeq`, `turn`, and `step`; it also rewrites every `start` index to
  zero and drops the terminal `index`, `outcome`, and committed sequence.
- `NativeSessionModel` ignores any durable event less than or equal to its
  cursor but accepts a jump to a later cursor without proving contiguity.
- A successful assistant `end` currently clears the partial text, reasoning,
  and tools immediately, before the durable settlement is verified.
- The composer model button uses `layoutWeight(1)` for both the button and its
  caption, so a short caption fills all free width.
- The image button displays a plus glyph; the adjacent paperclip button calls
  `onCompatibility` instead of opening a file picker.
- The prompt gateway accepts only text plus inline base64 images. Current DSH
  uploads exact bytes through `POST /api/session/uploadFileBinary` and sends a
  staged `receiptId` in prompt content.

## Assistant stream data contract

The normalized frame remains flat enough for the existing ArkTS model, but must
preserve the following upstream information.

### Snapshot

The snapshot carries:

- durable `cursor`, records, replacements, and history boundary;
- `assistantStream.revision`;
- optional active `attemptId`, `startedAfterSeq`, `turn`, `step`, `nextIndex`;
- the compact detached stream converted into current `text`, `reasoning`, and
  `toolUpdates`.

The snapshot is the sole authoritative replacement for the active partial
attempt. A reconnect must retain the last cached/partial presentation until the
snapshot is accepted, then replace the partial fields in one model mutation.

### Start

`start` carries `attemptId`, `revision`, `startedAfterSeq`, `turn`, and `step`.
The attempt starts with dense `nextIndex = 0`. Do not synthesize a zero index
while discarding the other fields.

### Chunk

`chunk` carries `attemptId`, `revision`, dense `index`, `time`, and the converted
text, reasoning or tool update. Accept it only for the active attempt and only
at the expected index.

### End

`end` carries `attemptId`, `revision`, terminal `index`, and:

- `{ kind: 'committed', eventType, seq }`; or
- `{ kind: 'abandoned' }`.

The terminal index must equal the model's `nextIndex`. An abandoned attempt can
clear its partial fields immediately. A committed attempt enters a short
settlement state until the identified durable event is applied or a snapshot
confirms the same durable watermark.

### Heartbeat

The gateway adds a small application-level heartbeat frame that is distinct
from transcript content:

```text
type: heartbeat
generation: opaque per-socket identifier
cursor: last durable sequence observed
attemptId: active attempt identity, or empty
nextIndex: expected dense stream index
revision: active assistant revision, or zero
```

Heartbeat cadence is adaptive:

- foreground chat: a heartbeat every 5 seconds and repair after 15 seconds
  without a valid frame;
- backgrounded app: a heartbeat every 15 seconds and repair after 45 seconds
  without a valid frame.

The gateway pings both peers and does not claim liveness when the upstream peer
has stopped answering. A foreground upstream peer that is unresponsive for 20
seconds closes both sides with a retryable protocol failure; the background
deadline remains 45 seconds.

The app records the last valid frame received, including a heartbeat. Reaching
the active deadline starts one repair. Duplicate watchdog triggers must not open
parallel sockets. Returning to the foreground re-evaluates the deadline
immediately instead of waiting for the next timer tick.

## Stream invariants and repair

- Every accepted durable event for a live generation must equal
  `cursor + 1`. A smaller sequence is a duplicate and may be ignored only when
  its raw event is identical or already present in the journal. A larger
  sequence is a gap and starts repair.
- Assistant attempts require the same `attemptId`. A `start` is accepted as a
  new baseline under the upstream revision rules; chunks and end markers must
  have the next revision and dense index expected by that baseline.
- A stale socket generation, stale selected-session callback, or stale model
  generation never mutates the current UI.
- A gap, attempt change, invalid terminal marker, missing settlement beyond the
  bounded window, or heartbeat timeout starts exactly one repair.
- Repair stops the old socket, keeps cached durable rows and the visible partial,
  opens the latest-DSH follow stream, and accepts the opening snapshot as the
  atomic activity baseline.
- Three consecutive failed repairs use the existing capped exponential backoff.
  A successful opening snapshot resets retry counters and the visible error
  state.
- The connection banner uses concise operational copy such as
  `连接中断，正在重连`; it does not explain protocol internals.
- A commit end waits for its durable settlement for 8 seconds. If the expected
  event does not arrive, request a snapshot repair.
- The prompt request ID is created once at user send time. Reconnect, snapshot
  recovery, app backgrounding, and socket errors never resend it automatically.
- When outcome is uncertain, retain the draft/attachments and expose the
  existing explicit user retry path.

Snapshot reconciliation preserves unrelated older cached history under the
existing replacement rules. Assistant text/reasoning/tool state is replaced
only from the snapshot's recorded `revision`, never merged heuristically with a
different attempt ID.

## Latest-DSH upload and prompt contract

### Upload route

Add one fixed native gateway route:

```text
POST /pocket/api/native/upload?sessionId=<id>&name=<name>[&mediaType=<image-mime>]
Content-Type: application/octet-stream
Origin: <configured app origin>
Cookie: <existing authenticated gateway cookie>
```

The gateway forwards the exact bytes and query to the authenticated current-DSH
route `/api/session/uploadFileBinary`. It does not base64-convert the body and
does not log file bytes, names, MIME type, or response receipts. Authentication,
origin, session ownership, redirect policy, and deployment size limits are
enforced by the gateway and current DSH host.

The app validates a successful HTTP response body as:

```text
{ ok: true, value: { receiptId, file: { attachmentId, name, bytes } } }
```

for a file, or:

```text
{ ok: true, value: { receiptId, image: { attachmentId, mediaType, bytes,
  width, height, ... } } }
```

for an image. HTTP 200 with `ok: false` is a business failure. A staged
`attachmentId` is never sent as though it were a receipt.

The ArkTS implementation uses Network Kit `extraData` with the exact
`ArrayBuffer`. The implementation must compile-test this raw-body path on the
supported SDK before shipping. It must not switch to base64 as a silent
fallback; a platform limitation requires a separately reviewed gateway request
body contract.

The app sends an explicit `Content-Length` equal to the selected byte array's
length and consumes the upload response through `requestInStream` with an
explicit `dataReceive`/`dataEnd` completion path. A missing response end must
settle as a retryable attachment error instead of leaving a spinner active
forever. The gateway validates the incoming length, forwards that exact length
to current DSH, and keeps the request body byte-exact.

### Composer state

Each draft attachment has stable identity, kind (`image` or `file`), optional
media type, display name, byte count, source URI/preview, and one status:

```text
uploading -> ready
uploading -> error -> uploading (explicit retry)
uploading/error -> removed
```

Files upload immediately after selection. Images upload through the image form
of the same receipt route. Ready drafts keep only the local data needed for a
thumbnail; uploaded bytes are not retained a second time in ArkTS memory.

Local picker/read work and network upload are separate states. `attaching`
covers only reading and publishing the selected drafts. Once the drafts are
visible, the image and file actions unlock even if one attachment continues
uploading. Each draft owns its upload lifecycle and independently transitions
to ready or a retryable error. A late completion updates the owning Session's
draft list even when another Session is currently visible.

Send is disabled while any attachment is uploading or failed. Removing an
uploading item cancels its operation when supported and prevents a late result
from mutating another draft. A server refusal that cannot change by retrying is
shown as a non-retryable error and remains removable.

On send, prompt content uses the current DSH order and semantics:

```text
[
  { type: 'file', receiptId }, ...
  { type: 'text', text }
]
```

The same prompt request ID is used for the one user submission. Attachments and
text are cleared only after the host accepts the request. If acceptance is
uncertain, both remain visible for explicit user action.

## Composer layout and controls

- Remove `layoutWeight(1)` from the model/effort button and its caption.
- The selector's intrinsic width is the caption width plus compact horizontal
  padding. It may shrink with ellipsis under a bounded maximum when the row is
  narrow, but it does not expand into unused space.
- Remove the persistent chevron. `bindPopup` uses `enableArrow: false`.
- Keep a flexible spacer between the intrinsic selector and the trailing action
  buttons so action alignment remains stable.
- Replace the plus glyph with an image-specific outline glyph. Its accessible
  label is `添加图片`.
- Replace the paperclip with a document/file outline glyph. Its accessible
  label is `添加文件`.
- Image input uses the system photo picker and accepts supported DSH image
  media types. File input uses `DocumentViewPicker`.
- Both pickers may return multiple items. Uploads retain source order.
- Both glyphs are bundled app assets with a single color path suitable for
  `Image.fillColor`. They must render correctly in light and dark themes.
- Image drafts render as small, wrapping thumbnails without file-name labels.
  File drafts render as compact document chips. Neither expands the transcript
  width or introduces explanatory paragraphs.
- The draft tray overlays the transcript immediately above the composer,
  aligned to the leading edge. Only each compact chip paints a themed surface;
  the tray itself remains transparent and does not reserve a full-width dark
  row when it contains one item.
- Press states use existing semantic motion tokens. Streaming reconciliation
  and completed uploads do not play transcript entrance animations.

The separate image and file actions are a DSH Harmony mobile extension. They
preserve the current DSH attachment semantics while making the two input types
discoverable on touch devices.

## Diagnostics and privacy

Diagnostics may record frame kind, generation equality, cursor numbers, attempt
identity hashes, index gaps, frame age, and repair reason. They must not record
prompt text, assistant text, reasoning, tool arguments, attachment names, file
bytes, receipt IDs, cookies, host addresses, or full upstream frames.

## Automated tests

- Protocol normalization retains every snapshot/start/end field and rejects
  missing or invalid required fields.
- Model tests cover contiguous durable sequence, duplicate events, durable
  gaps, stream gaps, attempt replacement, stale generations, committed-before
  end, end-before-committed, abandoned end, and settlement timeout.
- Reconnect tests prove a snapshot atomically replaces the active attempt while
  preserving unrelated cached history.
- Upload tests cover MIME-less files, image media types, explicit byte length,
  streamed response completion, business failures, pending/error/ready
  transitions, removal, retry, stable ordering, and path or origin rejection.
- Gateway tests prove the exact `Content-Length` reaches current DSH. A missing
  or invalid length is rejected before an upstream request is attempted.
- Prompt tests prove only ready receipts are serialized and an uncertain
  request is not automatically replayed.
- ArkUI source checks prove the selector has no full-width layout weight or
  chevron, and the file action no longer calls `onCompatibility`.

## Build and device gate

Shared ArkUI changes require Release builds for both `default` and `store`.
Implementation is complete only after the device E2E table has actual evidence;
compilation alone does not close stream recovery.
