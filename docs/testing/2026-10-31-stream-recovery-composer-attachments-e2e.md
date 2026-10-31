# Latest DSH Stream Recovery and Composer Attachments E2E

Date: 2026-10-31

Status: pending device run.

## Stream recovery

| ID | Scenario | Expected | Status |
| --- | --- | --- | --- |
| STR-E2E-01 | Start a long text response, disable Wi-Fi for several seconds after visible partial text, then restore it. | Cached partial remains visible; reconnect converges to the complete committed response without cold start or duplicate text. | Pending |
| STR-E2E-02 | With the app foregrounded during active streaming, suppress valid frames in a controlled mock. | No repair is claimed before 15 seconds; one repair starts at the foreground deadline and the snapshot catches up. | Pending |
| STR-E2E-03 | Repeat interruption during reasoning and tool-call argument streaming. | The correct reasoning and tools converge without duplicated or reordered items. | Pending |
| STR-E2E-04 | Inject a durable event gap in a protocol mock. | Repair starts before the later event is accepted; no skipped user or assistant rows remain. | Pending |
| STR-E2E-05 | Inject an assistant revision/index gap and an attempt change. | The stale partial is retained until the authoritative snapshot; recovery shows one coherent attempt. | Pending |
| STR-E2E-06 | Deliver committed end before its durable event. | Partial remains visible until settlement, then swaps to the durable response without a duplicate frame. | Pending |
| STR-E2E-07 | Withhold the committed event beyond the 8-second settlement window. | Exactly one snapshot repair occurs and reconciles from the host. | Pending |
| STR-E2E-08 | Put the app in background during a response, then return after completion. | The latest committed response is present and only one live socket remains. | Pending |
| STR-E2E-09 | Lose the network after the prompt POST enters an uncertain state. | The prompt is not resent automatically and the existing explicit uncertain-action UI remains usable. | Pending |
| STR-E2E-10 | Background the app during active streaming and suppress frames. | Background repair uses the 45-second deadline; returning to foreground re-evaluates immediately and starts only one repair when overdue. | Pending |

## Composer layout

| ID | Scenario | Expected | Status |
| --- | --- | --- | --- |
| UI-E2E-01 | Open a session with a short model caption on a narrow portrait screen. | The selector hugs the caption and leaves a clear flexible gap before trailing actions. | Pending |
| UI-E2E-02 | Open a session with a long model caption and large system text. | Caption ellipsizes within its cap; image, file, queue/steer and send/stop actions remain visible. | Pending |
| UI-E2E-03 | Tap the model/effort selector. | The popup opens without an arrow and no persistent down chevron is visible. | Pending |
| UI-E2E-04 | Repeat UI-E2E-01 through UI-E2E-03 in light, dark and reduced-motion modes. | Layout is stable and both action glyphs have correct contrast without black edges. | Pending |
| UI-E2E-05 | Check TalkBack accessibility labels. | The actions announce image, file, model/effort, send and stop accurately. | Pending |

## Image and file input

| ID | Scenario | Expected | Status |
| --- | --- | --- | --- |
| ATT-E2E-01 | Tap the image action. | Only the system image picker opens. Compatibility mode does not open. | Pending |
| ATT-E2E-02 | Select multiple supported images. | Ordered thumbnails appear, upload receipts become ready, and the prompt shows them in source order. | Pending |
| ATT-E2E-03 | Tap the file action. | Only the native document picker opens. Compatibility mode does not open. | Pending |
| ATT-E2E-04 | Select PDF, text, archive and extensionless files. | Each staged file uploads through the current-DSH receipt route and appears as a compact removable chip. | Pending |
| ATT-E2E-05 | Attempt send while an upload is active. | Send remains disabled and no partial attachment submission occurs. | Pending |
| ATT-E2E-06 | Cause a retryable upload failure, retry, and remove a different draft. | Failed item retries to ready; removed item disappears and late completion cannot resurrect it. | Pending |
| ATT-E2E-07 | Cause a host refusal such as an unsupported image or size limit. | A concise non-retryable error is shown; the item remains removable and send stays disabled. | Pending |
| ATT-E2E-08 | Send mixed text, images and files, then reopen the session. | User message renders compact images/files in order and reopens with the same durable attachments. | Pending |
| ATT-E2E-09 | Cancel the picker and repeat each action. | No empty draft, stale upload state, or compatibility surface is created. | Pending |

## Validation and release

| ID | Check | Expected | Status |
| --- | --- | --- | --- |
| VAL-E2E-01 | Run gateway protocol, upload, prompt and privacy tests. | All pass and no private/transcript data appears in logs or fixtures. | Pending |
| VAL-E2E-02 | Run ArkTS model tests for stream correctness. | All deterministic gap/recovery cases pass. | Pending |
| VAL-E2E-03 | Build Release for the `default` product. | Build succeeds. | Pending |
| VAL-E2E-04 | Build Release for the `store` product. | Build succeeds. | Pending |
| VAL-E2E-05 | Install the personal Release build on the HarmonyOS device and repeat critical rows. | Stream, image and file flows pass with fresh evidence. | Pending |
