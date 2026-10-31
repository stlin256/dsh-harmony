# Plugin Installation, Onboarding and Branded Launch Specification

Date: 2026-10-31

## Upstream Contract

Research baseline: DeepSeek Harness
`f3803c96974ad4a94195fb97e5c637e9c2a3afe3`.

The official plugin manager accepts registry package specs, Git specs, tarball
URLs and absolute local paths. It inspects the subject before installation and
requires a `dsh.bundle.patch` manifest declaration. Standard and Creator
presets expose the `plugin_manager` tool. The Plugins page provides the same
install path for users who are not asking an agent.

Therefore the supported installation surfaces are:

1. Give DSH the project installation prompt. An agent with `plugin_manager`
   installs the stable tarball target, enables it and verifies the reported
   version.
2. Open **Plugins → Add plugin**, paste the same stable tarball URL, install and
   enable it.
3. For development, build `node scripts/package-plugin.mjs` and install the
   generated absolute `.tgz` path.

The lightweight monorepo subdirectory is not advertised as a direct Git install
because its nested gateway imports a production dependency closure. Keeping the
plugin in this repository is preferable while its API and app release must move
together.

## Plugin Package Contract

- `plugins/dsh-harmony/package.json` declares both its browser client and:

  ```json
  "dsh": {
    "bundle": {
      "patch": "./cordis.patch.yml"
    }
  }
  ```

- The bundle patch inserts the single `dsh-harmony` host row.
- `scripts/package-plugin.mjs` copies the patch, host entry, browser entry,
  notify module, gateway sources, public assets and production dependency
  closure into a clean package.
- `scripts/verify-plugin-package.mjs` verifies the tarball manifest, patch,
  host import, browser registration, internal assets and package metadata.
- The release workflow publishes a stable asset name
  `dsh-harmony-plugin.tgz`, in addition to a versioned asset when useful.
- `docs/PLUGIN-INSTALL.md` is the canonical human and agent installation
  document. It contains no deployment-specific values.

The exact copy prompt is canonical in `BuildInfo.pluginInstallPrompt` so the app
and documentation can be checked against one another.

## Launch State Model

The native shell owns these user-visible phases:

| Phase | Responsibility |
| --- | --- |
| `booting` | Load preferences and perform minimum branded launch presentation. |
| `intro` | Welcome title and full-width guide/direct-entry actions. |
| `guide` | Three installation steps, repository action and copy action. |
| `login` | Address, native login (default) and optional Passkey controls. |
| `restoring` | Saved-session probe with no editable login form visible. |
| `error` | Recoverable startup error with copy, retry and edit actions. |
| `entering` | Short crossfade into a successfully restored workspace. |
| `hidden` | Normal app surface. |

The persisted `onboardingSeen` value is written only when the user chooses
direct entry or completes the guide and proceeds to login. Logout resets it and
sets the next launch to `intro`. The saved origin remains persisted.

## Cold Launch

1. Read stored origin, UI mode and login mode while showing `booting`.
2. If there is no origin, resolve to `intro`.
3. If onboarding has not been seen, resolve to `intro`.
4. Otherwise keep the launch surface visible and attempt saved-session
   restoration with `NativeHarnessClient.state()`.
5. A successful restore enters the workspace. A state requiring an access key
   resolves to `login`; network, TLS or unexpected failures resolve to
   `error`.
6. A successful interactive login resolves to `entering`, fades the branded
   surface and then exposes the workspace.

The form is never rendered during steps 1–4.

## Welcome and Guide Motion

- Initial logo: centered upper third, 84–96 vp depending on viewport.
- Actions enter after the title with the semantic `micro` motion token.
- Guide transition: logo moves toward the lower-right, scales up and fades to a
  restrained watermark. Welcome actions fade out; guide content and its
  vertical progress line enter from the corresponding direction.
- Returning from the guide reverses the spatial path.
- Reduced motion resolves all positions and opacities immediately.
- No looping animation decorates the guide.

The three steps use existing local vector glyphs inside a common step row:
connection/globe, plugin/download and ready/check. A short vertical line
connects them and grows once when the guide opens.

## Login and Error Surfaces

- The login view keeps the DSH compact card language, neutral surfaces and
  DeepSeek blue accent.
- Native login is selected by default. Passkey appears below it and is omitted
  from builds without Passkey capability.
- Passkey requires HTTPS; native login permits HTTP for LAN use.
- Login failure stays in the launch surface and supplies a small inline error
  panel. Copy writes only the visible error text.
- Startup restore failure supplies copy, retry and edit-address actions.
- Back from guide or login returns to the previous launch phase. System Back
  does not exit from a deep transient error without first returning to login.
- Notification deep links remain stored until the workspace is ready.

## Accessibility and Platform Behavior

- All icon-only actions have accessibility text.
- Logo artwork is decorative in the watermark state.
- Text respects system scaling; button rows wrap only when necessary.
- API 26 may use translucent materials when available. API 23 uses opaque
  theme surfaces and remains fully functional.
- The launch surface paints behind system bars while its content respects safe
  area insets.

## Verification

- Source/model tests verify phase ordering, prompt canonicalization and package
  contracts.
- Plugin packaging tests verify a clean external extraction and bundle metadata.
- Release builds cover `default` and `store`.
- Device evidence follows
  [2026-10-31-plugin-install-onboarding-launch-e2e.md](../testing/2026-10-31-plugin-install-onboarding-launch-e2e.md).
