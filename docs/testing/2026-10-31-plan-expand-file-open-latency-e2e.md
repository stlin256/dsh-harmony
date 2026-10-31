# Plan Expansion Stability and Immediate File Preview E2E

Date: 2026-10-31

Status: pending device run.

Device: HarmonyOS device supplied for this project.

| ID | Scenario | Expected Result | Status |
| --- | --- | --- | --- |
| PFE-01 | Open a completed chat process, then expand `更新了计划` repeatedly. | The plan detail appears each time; the workspace remains mounted and the app does not terminate or return to the launcher. | Pending |
| PFE-02 | Expand and collapse neighboring process operations after a plan row. | Each row controls only its own detail; no row changes identity or opens a different operation. | Pending |
| PFE-03 | Let a live response append more operations after one child is expanded. | The open row remains open and its preview/detail content does not jump to another row. | Pending |
| PFE-04 | Tap a valid file link in rendered chat. | Preview header, controls and loading state appear immediately; content replaces loading when ready. | Pending |
| PFE-05 | Tap a valid folder link in rendered chat. | Preview placeholder appears immediately, then the file browser opens at that folder. | Pending |
| PFE-06 | Tap a valid basename-only file link. | Preview appears immediately, then resolves and loads the exact file. | Pending |
| PFE-07 | Tap a missing file path. | Preview appears immediately, then shows a concise unavailable-file error with retry; no endless spinner or blank screen. | Pending |
| PFE-08 | Close the preview while `statFile`, basename search or file content is still pending. | The closed preview stays closed; no late response reopens an overlay. | Pending |
| PFE-09 | Tap two file links in quick succession. | The second request owns the overlay; a late response from the first does not replace it. | Pending |
| PFE-10 | Repeat PFE-01 through PFE-09 in light mode, dark mode and reduced-motion mode. | Content remains legible, feedback is bounded and no non-essential animation runs under reduced motion. | Pending |
| PFE-11 | Cold-start the app, open an image directly and do not tap retry. | The first attempt reaches the image bitmap on its own; no “无法预览此图片” error is shown. | Pending |
| PFE-12 | After a cold start, open multiple images consecutively from chat and the file browser. | Every first attempt loads; metadata fallback is shared and no request failure is shown to the user. | Pending |
