# Store showcase screenshots implementation

## Product isolation

`EntryAbility` accepts two launch-only string parameters:

- `storeShowcase=true`
- `showcaseScreen=conversation|process|sidebar|browser|settings`
- `showcaseTheme=light|dark|system`

Only the explicit `storeShowcase=true` launch selects `StoreShowcaseClient`.
The client is an in-memory `NativeHarnessClient` implementation and never opens
a network connection. It supplies synthetic sessions, workspaces, host settings,
model metadata and a completed conversation to the existing `NativeWorkspace`
and `NativeSettings` components.

The fixture stays in the installed binary so screenshots remain reproducible.
Normal launches do not read fixture data, write it to the transcript cache or
use it for widget state.

## Content contract

The fixture uses only generic product copy:

- workspace: `DSH Harmony 移动端`, `Passkey Gateway`
- session: `发布准备与商店检查`
- response: release checklist and next steps
- file example: a short DSH Harmony README
- model: `DeepSeek-V4-Pro`, reasoning effort `max`

No origin, account, token, cookie, real path or real session title is present.

## Capture output

`scripts/capture-store-screenshots.ps1` installs the store HAP, launches the
selected fixture states and captures raw device images through
`devecocli ui screenshot`.

The script is the one-command refresh path. By default it builds the `store`
Release product, installs it, captures all scenes, composes both orientations,
validates dimensions and file size, and writes `manifest.json`. A contributor
that already has a current HAP can pass `-SkipBuild`; a capture-only pass can
also pass `-SkipInstall`.

```powershell
.\scripts\capture-store-screenshots.ps1 -Device '<device-id>'
```

Pass `-RestorePersonal` to rebuild and reinstall the personal Push Kit variant
after capture. Without it, the device remains on the captured store build.

`scripts/compose-store-screenshots.py` places each real-device portrait capture
in a branded rounded device frame. The phone is enlarged to dominate the right
half of landscape art and the lower visual block of portrait art. Titles,
feature chips and the device are packed into a centered composition rather
than spread across distant corners.

Each listing scene is emitted at 1920×1080 and 1080×1920:

1. Conversation, light
2. Expanded process, light
3. Sidebar, light
4. File browser, light
5. Settings, light
6. Conversation, dark
7. Expanded process, dark
8. Sidebar, dark
9. File browser, dark
10. Settings, dark

The same helper additionally emits `paired-appearance`, `desktop-cards` and
`open-source` in both orientations. The paired appearance art uses the actual
light and dark device captures. The card art follows the bundled
`OverviewCard`/`QuickCard` colors, radius and information hierarchy. The
open-source art names the real repository and makes no star or license claim.

The process is read-only with respect to the remote service. Device completion
requires a connected, unlocked device whose HDC state is neither `Offline` nor
`Unauthorized`.
