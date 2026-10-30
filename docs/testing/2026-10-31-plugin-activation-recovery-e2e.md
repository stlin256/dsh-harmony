# Plugin activation recovery device E2E

Device: HarmonyOS phone, `2026-10-31`
App: `0.3.5` (`versionCode 16`)
Plugin package: `0.3.2`

| ID | Scenario | Expected | Result | Evidence |
| --- | --- | --- | --- | --- |
| PA-01 | Tap Plugins in the native drawer | Drawer closes, `功能未开放` appears and no web surface opens | Pass | Toast observed; native session remained visible |
| PA-02 | Tap Automation in the native drawer | Drawer closes, `功能未开放` appears and no web surface opens | Pass | UI tree contained `功能未开放`; no web surface |
| PA-03 | Tap More in the native drawer | Drawer closes, `功能未开放` appears and no web surface opens | Pass | UI tree contained `功能未开放`; no web surface |
| PA-04 | Repeat all three rows | Native workspace remains interactive | Pass | Native transcript and composer remained mounted |
| PA-05 | Materialize the packed browser plugin with a valid session | Plugin activation returns before deferred navigation | Pass | Packed host/browser verifier and Node contract tests |
| PA-06 | Serve the new plugin release from Harness | Plugin failure card is absent and Harness UI renders | Pass | Device opened a temporary compatibility surface before the product gate; Harness rendered after boot |

## Evidence rules

Record build version, test time and pass/fail only. Do not retain screenshots or
logs containing real session titles, private hosts, credentials or tokens.
