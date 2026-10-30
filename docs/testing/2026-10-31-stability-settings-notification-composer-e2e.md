# Stability, Settings, Notification and Composer E2E

Date: 2026-10-31

Status: pending device run on version 0.3.4.

## Drawer Destinations

- [ ] Install the updated signed personal HAP with `install -r`.
- [ ] Clear hilog, open the drawer and tap Plugins.
- [ ] Confirm the app stays alive and the compatibility surface loads.
- [ ] Repeat for Automation tasks and More.
- [ ] Inspect hilog for `17100001`, `JS_ERROR`, `JSCRASH` or `APPFREEZE`.
- [ ] Use the compatibility Back button after navigating inside the page.

## Appearance and Motion

- [ ] Toggle Reduce Motion twice and verify the switch changes on each tap.
- [ ] Confirm navigation and drawer motion resolve according to the setting.
- [ ] Toggle Reduce Transparency twice and verify the switch changes on each
  tap.
- [ ] Leave and reopen the appearance page; both saved values remain visible.

## Notification

- [ ] Trigger Send Test Notification with notification permission enabled.
- [ ] Verify a prominent/banner test notification appears and uses sound or
  vibration according to system settings.
- [ ] Open the notification and verify the app enters the expected session.
- [ ] Inspect the notification center and confirm the prominent priority is
  applied on devices supporting the API 23 priority type.

## Composer

- [ ] Open a conversation in portrait and confirm the composer clears the
  navigation gesture bar.
- [ ] Confirm the increase is visually slight and the transcript does not shift
  upward as a whole.
- [ ] Repeat with keyboard open, large text, landscape and split-screen.

## Exit

- [ ] No new runtime crash or silent no-op remains.
- [ ] Both Release product variants compile from the same ArkUI source.
