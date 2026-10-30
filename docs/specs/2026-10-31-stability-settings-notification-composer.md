# Stability, Settings Feedback, Notification Prominence and Composer Inset

Date: 2026-10-31

Status: implemented; Release build and device verification pending.

## Drawer Destination Crash

Device logs identified the failure as a `JS_ERROR` inside
`NativeCompatibilitySurface` while rendering its first frame:

```text
Init error. The WebviewController must be associated with a Web component
error code 17100001
```

The back button opacity read `controller.accessBackward()` during `build()`.
Before the `Web` node associates the controller, that native method throws.

Implementation:

- Do not call any `WebviewController` method while building a component.
- Maintain `canGoBack` as component state.
- Refresh that state after the controller has reached page end.
- Guard user-triggered backward access and resolve the control to disabled if
  the controller is unavailable.
- Keep the drawer-to-web handoff as an independent compatibility surface.

## Appearance Switch State

The custom builder received the old boolean as a captured argument. A direct
component-state update could therefore redraw the row with a stale switch value
until the page was reconstructed.

Implementation:

- `toggleRow` reads `localValue(key)` directly from component state.
- A tap reads the current value at press time and toggles that value.
- Optimistic writes and rollback run through the existing `updateState()`
  semantic motion path.
- Host-confirmed values replace the optimistic value when a response includes
  one.

## Test Notification

- The local test action uses level `prominent`.
- `prominent` selects the HarmonyOS social-communication slot, whose default
  level includes status-bar presentation, banner and sound.
- Prominent local notifications also use the API 23 priority type
  `URGENT_MESSAGE`, so supported devices can pin and highlight them in the
  notification center.
- Category filtering remains unchanged: test delivery does not bypass a user's
  production notification category choices.

## Composer Navigation Inset

- Apply the extra inset to the conversation composer container only.
- Bottom inset is `ceil(safeBottom * 1.2) + 8vp`.
- Do not add another global page inset and do not move the transcript or top
  chrome.
- Reduced motion has no effect because this is layout spacing, not animation.

## Verification Contract

- Static: all gateway tests, publication scan and whitespace validation pass.
- Build: both `default` and `store` Release products compile.
- Device: reproduce all three drawer destinations from a clean log, then verify
  appearance toggles, prominent test notification and composer clearance.
