# Stability, Settings Feedback, Notification Prominence and Composer Inset

Date: 2026-10-31

Status: implemented; ArkTS Release build and device verification pending.

## User Requirements

- `STABILITY-01` Tapping Plugins, Automation tasks or More in the workspace
  drawer must not terminate the app.
- `SETTINGS-01` Reduce Motion and Reduce Transparency must change their visible
  switch state immediately after each tap, without leaving and reopening the
  page.
- `NOTIFICATION-01` The test action must publish an attention-grabbing
  notification using the prominent delivery path.
- `COMPOSER-01` Move only the message composer slightly upward from the system
  navigation gesture area. The bottom inset should be approximately 1.2 times
  the navigation inset, not a large page-wide shift.

## Non-Goals

- Do not change workspace file access beyond its existing read-only contract.
- Do not introduce private service addresses, notification payload content or
  credentials into source, tests or documentation.

## Acceptance

- The known device crash log no longer reproduces for any of the three drawer
  destinations.
- Each appearance switch updates in place and survives reopening Settings.
- The test notification is delivered through the prominent level.
- The composer clears the navigation gesture area without moving the
  transcript, header or drawer as a whole.
