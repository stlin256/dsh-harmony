# Plugin activation recovery specification

## Upstream contract

DSH `0.2.2-alpha.2` loads client plugin bundles through
`window.__ModuleLoader__.load({ id, factory })`. The bundle factory returns a
Cordis plugin object with `inject` and `apply`. The module graph orders the
bundle after `@deepseek-ai/dsh-client-ui-workspace`; the runtime fiber waits for
the `uiWorkspace` service.

The application boot loader treats an `apply()` exception as a failed entry.
That failure replaces the whole application surface with the plugin failure
card. Workspace navigation is therefore a post-activation side effect, not
activation work.

## Runtime behavior

The three native drawer rows call one shared handler. That handler closes the
drawer and shows the local toast `功能未开放`. The previous post-drawer
compatibility callback stays as commented code and no web view is mounted.

`client.mjs` reads `dshHarmonySession` from the current URL. For a valid
identifier it registers one Cordis effect containing a zero-delay browser
timer. The effect returns a disposer that clears the timer if the plugin is
deactivated.

When the timer runs:

1. It calls `uiWorkspace.openSession(id)`.
2. If the call succeeds, it removes only `dshHarmonySession` and preserves the
   path, hash and every other query parameter.
3. If the call throws, the plugin logs a warning and leaves the query intact
   for a later reload. The timer does not retry in a loop.

No DOM traversal, private store access, transcript read or host metadata is
introduced.

## Generated browser entry

`scripts/build-plugin-client.mjs` continues to convert the self-contained
source into the Harness lazy factory contract. `@dsh-harmony/plugin` and the
legacy `@dsh-harmony/navigation` source receive the same scheduling behavior
to keep both entries consistent.

## Verification

Node tests execute the real generated browser bundles in a VM with a controlled
timer. They assert:

- `apply()` returns before `openSession`;
- the scheduled callback selects the expected session;
- URL replacement preserves unrelated state;
- an exception from `openSession` is contained after activation;
- plugin disposal cancels an outstanding handoff;
- invalid identifiers are ignored.

The ArkUI build must compile the gated drawer handler without an unused
branch, and device checks must confirm all three rows produce the same toast
while the native session remains mounted.

The package verifier continues to import the packed host entry, materialize the
browser factory and exercise the embedded gateway. Device evidence is tracked
in `docs/testing/2026-10-31-plugin-activation-recovery-e2e.md`.
