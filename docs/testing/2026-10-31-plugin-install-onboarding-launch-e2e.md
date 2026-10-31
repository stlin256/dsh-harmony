# Plugin Installation, Onboarding and Branded Launch E2E

Date: 2026-10-31

Status: pending device run.

| ID | Scenario | Expected Result | Status |
| --- | --- | --- | --- |
| ONB-E2E-01 | Install the signed personal HAP with no saved session and launch. | Branded launch appears first; the editable address form is not exposed during initialization; welcome logo, name and two actions appear. | Pending |
| ONB-E2E-02 | Tap the guide action. | Logo moves to the lower-right watermark; three concise steps enter in the correct direction; reduced motion resolves instantly. | Pending |
| ONB-E2E-03 | Use the guide copy action and paste into a text field. | The canonical installation prompt is copied without private hosts or credentials. | Pending |
| ONB-E2E-04 | Use the guide repository action. | The project repository opens in the system browser. | Pending |
| ONB-E2E-05 | Choose direct entry, enter native credentials and connect. | Login succeeds and the launch surface crossfades into the workspace. | Pending |
| ONB-E2E-06 | Relaunch with a valid saved native session. | Branded launch remains visible during restore and transitions directly to the workspace. | Pending |
| ONB-E2E-07 | Relaunch with an expired native session and saved origin. | No editable form appears during restore; login opens with the saved address prefilled. | Pending |
| ONB-E2E-08 | Submit an invalid key, then use copy and retry with the valid key. | Error remains inside the launch visual system, copy works and valid retry succeeds. | Pending |
| ONB-E2E-09 | Select Passkey, complete system authentication and enter the workspace. | Passkey controls remain below native login; HTTPS flow, authentication and workspace entry remain functional. | Pending |
| ONB-E2E-10 | Log out, terminate and reopen the app. | Welcome flow appears again and the previous service address is still prefilled upon direct entry. | Pending |
| ONB-E2E-11 | Repeat primary paths in light, dark, reduced-motion, API 23, large-text and landscape configurations. | No clipped action, unreadable text, unsafe overlap or motion that ignores reduce-motion. | Pending |
| ONB-E2E-12 | Install the stable tarball through DSH Plugins or `plugin_manager`. | The package is accepted as a bundle, activates, reports its version in app settings and survives a Harness restart. | Pending |
