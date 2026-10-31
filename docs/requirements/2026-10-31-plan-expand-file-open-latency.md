# Plan Expansion Stability and Immediate File Preview

Date: 2026-10-31

Status: implementation requested.

## User Requirements

- `PLAN-01` Expanding an operation labeled `更新了计划` inside the chat process
  disclosure must show the plan detail without crashing or unexpectedly leaving
  the workspace.
- `PLAN-02` Streaming updates and repeated upstream event identifiers must not
  change which operation a disclosure row controls.
- `FILE-01` Tapping a workspace file or folder link in rendered chat content
  must present the native preview surface on the next UI frame. The surface may
  show a loading state while authentication, path resolution and file loading
  continue.
- `FILE-02` Path probing must not block the visible transition. File content,
  folder detection and basename fallback resolution happen after the preview
  shell is mounted.
- `FILE-03` A valid file remains in `NativeFilePreview`; a valid directory
  transitions to `NativeFileBrowser`; an invalid path reports an error without
  leaving a permanently blank overlay.
- `FILE-04` A late resolution response cannot reopen a preview after the user
  has closed it or after another link has become the active request.
- `FILE-05` The first direct image preview after a cold app start must render
  without showing an error or requiring the user to tap retry.

## Constraints

- Workspace access remains read-only.
- Preserve the existing same-request guard and short error language.
- Do not add private hosts, credentials, transcript content or device data to
  source, tests, documentation or commits.
- Respect reduced motion. Loading and resolution feedback must not add looping
  decorative motion.
- Shared ArkUI changes must build for both `default` and `store` Release
  variants.

## Acceptance Criteria

- Repeatedly opening and closing a completed `更新了计划` row does not emit
  duplicate `LazyForEach` keys, lose the workspace or terminate the app.
- Process child disclosure state remains stable while the same turn streams or
  receives an unchanged replay.
- A chat file link displays the preview header and loading surface immediately;
  network validation does not delay that first frame.
- File display begins without a separate blocking `statFile` round trip.
- A missing streamed `X-DSH-File-Window` response header is recovered from
  file metadata without discarding bytes already received.
- Concurrent preview metadata and transport fallback share the same stat
  request.
- A first image load either reaches the bitmap state or a definitive file error;
  it must not show the retry error solely because metadata arrives late.
- File, folder, fallback basename and unavailable-path outcomes remain correct.
- Closing the preview while resolution is pending prevents a stale response
  from reopening it.
- Model tests cover unique process render identities and the preview-first
  request ordering. Device evidence is recorded separately.
