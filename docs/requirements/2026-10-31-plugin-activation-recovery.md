# Plugin activation recovery

## User requirement

The native drawer's Plugins, Automation and More rows are temporary
product-gated entries. Tapping any of them must close the drawer and show only
`功能未开放`; these rows must not mount the compatibility web surface. Their
original routing code remains commented so native implementations can replace
the placeholders later.

The DSH Harmony client plugin itself must also recover from the previous
activation failure when a compatibility surface is opened by another supported
entry. The page must not remain on:

```text
Failed to load plugins
@dsh-harmony/plugin
web boot: 1 entry did not activate
```

The plugin must keep the current one-time session handoff behavior when it is
available, while a navigation mismatch cannot prevent every other Harness
client plugin from booting.

## Acceptance criteria

- Each of the three gated native rows shows `功能未开放` and does not open a
  compatibility destination.
- The former routing calls remain documented as commented extension points.
- `@dsh-harmony/plugin` returns from activation before invoking workspace UI
  navigation.
- Session selection occurs once after the current activation turn and is
  isolated from plugin activation failure.
- A failed selection leaves the normal Harness interface usable and does not
  repeatedly throw from the plugin timer.
- The handoff query parameter is removed only after selection succeeds.
- Invalid or absent session parameters remain a no-op.
- The generated browser bundle continues to use the public
  `@deepseek-ai/dsh-client-ui-workspace` module edge and the `uiWorkspace`
  runtime service.
- Tests cover successful deferred navigation, URL preservation, plugin
  cleanup, activation return, and navigation exception containment.
- The device E2E result is recorded separately and is not marked complete until
  the HarmonyOS device opens all three compatibility destinations.

## Privacy

Tests and documentation use synthetic session identifiers and example hosts.
No deployment host, token, cookie or transcript is recorded.
