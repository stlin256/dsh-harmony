# Latest DSH Stream Recovery and Native Composer Attachments

Date: 2026-10-31

Status: proposed; production implementation awaits approval.

## Supported upstream

DSH Harmony targets one current upstream contract:

`deepseek-ai/deepseek-harness@ce7073d51254c26cd63b22a60835b8f948deb447`

Older DSH capability probes and legacy composer fallbacks are outside this
work. A host that does not implement the pinned contract is unsupported rather
than silently degraded.

## Reported behavior

- A live assistant response can stop halfway through token streaming and remain
  incomplete until the app is cold-started.
- The model and reasoning-effort selector occupies most of the composer row and
  has a downward arrow that does not match the compact DSH composer.
- The plus button really opens the image picker.
- The paperclip button is labelled as attachment input but opens compatibility
  mode instead of a file picker.

## Requirements

- `STREAM-01` Detect a half-open or silently stalled live connection within a
  bounded interval while the cached transcript remains visible.
- `STREAM-02` Recover from the authoritative latest-DSH assistant opening
  snapshot without showing a blank conversation and without duplicating durable
  messages, tools, reasoning, or text.
- `STREAM-03` Treat durable sequence gaps, assistant revision/index gaps,
  attempt changes, malformed terminal frames, and missing committed settlement
  as repair signals rather than successful progress.
- `STREAM-04` Do not discard the visible partial response merely because a
  successful transport-level stream end arrived. Reconcile it with the
  committed durable event first.
- `STREAM-05` A connection repair never resends the user's prompt under a new
  request ID and never turns a transport uncertainty into a second turn.
- `STREAM-06` Streaming and snapshot reconciliation do not animate transcript
  rows as if they were newly entered items.
- `COMPOSER-01` The model/effort selector is intrinsically sized around its
  caption, has no persistent chevron, and its popup has no arrow.
- `COMPOSER-02` The image action uses a bundled, theme-aware DSH image glyph and
  opens only the system image picker.
- `COMPOSER-03` The file action uses a bundled, theme-aware document glyph and
  opens the native document picker. It must never invoke compatibility mode.
- `COMPOSER-04` Both images and files use the latest-DSH staged receipt upload
  contract; an attachment cannot be sent while uploading or failed.
- `COMPOSER-05` The composer shows compact image thumbnails and file chips with
  remove and retry affordances, preserves attachment order, and remains usable
  with keyboard, large text, narrow screens, light theme and dark theme.
- `COMPOSER-06` Attachment handling remains read-only with respect to the user's
  workspace. Uploading a prompt attachment does not grant file editing.

## Acceptance

- A long response interrupted at any point converges to the complete committed
  response after reconnect without a cold start.
- A deliberately silent socket triggers repair after the watchdog, while a
  genuinely quiet but healthy long-running task does not.
- The composer caption does not stretch to fill the row; image and file buttons
  open their own pickers and upload through DSH receipts.
- No private host, credential, cookie, transcript, or attachment content is
  added to source, tests, documentation, logs, or commits.
