# Navigation and process refinement device E2E

Status: pending device execution.

| ID | Scenario | Expected evidence | Status |
| --- | --- | --- | --- |
| NAV-01 | Open session drawer and inspect workspace header | Only `全部` appears at the trailing edge; no add glyph | Pending |
| NAV-02 | Open workspace manager and each child page | Header and rows remain below the status bar | Pending |
| NAV-03 | Press Back on create/archive, then manager root, then drawer | Child -> workspace root -> drawer -> chat/home, without jumping directly home | Pending |
| MOT-01 | Open and close settings from the drawer | Root surface fades/slides in and out; cached content does not flash blank | Pending |
| NAV-04 | Inspect settings root and enter/leave a child page | Root has no close glyph; child pages use one consistent left chevron and reverse direction on Back | Pending |
| NAV-05 | Press system Back in a selected native chat | Confirmation appears once; cancel preserves chat, exit terminates intentionally | Pending |
| NAV-06 | Open compatibility mode | Back and close are compact icons with no duplicate platform close button or overlap | Pending |
| MOT-02 | Open, drag and close the drawer | Full-screen mask and tight edge shadow animate with drawer position; neither leads the surface and no shadow-only frame remains | Pending |
| NAV-07 | Close the drawer, then return to the session list through both the header and an automatic/navigation path | Drawer content and scrim are visible together; no shadow-only frame | Pending |
| NAV-08 | Inspect the drawer workspace selector in the default workspace | The `全部` label reaches the same trailing edge as other drawer content without an inner gap | Pending |
| SET-01 | Change notification levels and other saved settings successfully | No success toast/status text; control reaches final state | Pending |
| CHAT-01 | Tap the chat overflow button once | Opaque solid menu appears immediately with no visible backdrop dim; each action is reachable | Pending |
| CHAT-02 | Open and close the chat overflow menu | The list starts directly below the ellipsis control; that control shows an active highlight for the full open state | Pending |
| PROC-01 | Inspect a completed turn with command, file and image actions | One `工作过程` row contains direct command, file and image operation rows when expanded | Pending |
| PROC-02 | Tap command/file/image operation rows repeatedly | Child actions expand once per tap; child detail stays collapsed; no crash or row substitution | Pending |
| FILE-01 | Tap a basename-only chat file reference whose file is in a nested workspace folder | Spinner appears; exact match opens in native preview; no device-local file substitution | Pending |
| FILE-02 | Open a workspace-root directory browser | Host receives `.` for the root; entries load rather than reporting an address error | Pending |
| FILE-03 | Open markdown, image, text and directory references | Each opens its native preview or browser; unsupported content shows one short error | Pending |
| FILE-04 | Tap a valid file or directory reference from a transcript row | A root-level reader/browser appears on the first tap with no silent success path | Pending |
| FILE-05 | Press system Back from a chat-opened file reader or browser | The root-level preview closes before chat navigation or exit confirmation | Pending |
| SET-02 | Tap label, switch, and empty row space for reduce transparency and card task names | Each tap toggles exactly once; switch animates; state persists after leaving and reopening settings | Pending |
| MOT-03 | Scroll away from chat bottom | Back-to-bottom control is visibly circular with a centered icon | Pending |
| PROC-03 | Collapse command, read-file and reasoning rows | Each has a compact one-line preview and no extra heading level | Pending |
| PROC-04 | Expand command/read-file/reasoning rows | Preview fades out, direct detail enters, and repeated toggles are stable | Pending |
| PROC-05 | Expand a `工作过程` group with several operations | A bounded inner scroll region may occupy up to 60% of the transcript viewport without expanding the full page | Pending |
| IMG-01 | Expand a tool result containing an image and tap its thumbnail | App-level lightbox opens with the authenticated image and a close control | Pending |
| IMG-02 | Pinch and double-tap inside the image lightbox, then press system Back | Content zooms, double tap resets, and Back closes the lightbox before chat navigation | Pending |
| IMG-09 | Pinch to enlarge an image, drag around the enlarged image, release, then pause | The image stays enlarged and translated; the release does not trigger an outside-tap close or reset zoom | Pending |
| IMG-10 | Repeat pinch gestures after an initial zoom and drag in all directions | Each pinch multiplies the current scale, translation follows the focus point, and panning stops at image bounds | Pending |
| IMG-05 | Open the image lightbox in both theme modes | Close control remains below the status-bar boundary with a consistent compact top inset | Pending |
| IMG-03 | Expand a `read_image` operation with one image | Only the small left-aligned thumbnail is shown; no raw arguments, path metadata or text output appears | Pending |
| IMG-04 | Expand a `read_image` operation with multiple images | Thumbnails wrap into multiple leading-aligned rows as needed and each opens the matching lightbox image | Pending |
| PROC-06 | Scroll expanded process content with the platform scrollbar visible | Text and action controls end before the scrollbar track; no control is covered or dragged by the thumb | Pending |
| PROC-07 | With `工作过程` expanded, open a long child operation and scroll both levels | The child stays below its separate 36% cap, scrolls independently, and the main conversation remains practical to page through | Pending |
| PROC-08 | Open a README/Markdown result inside an expanded process operation | Headings, quotes, tables and fenced code render with native styling and code highlighting instead of one raw text run | Pending |
| PROC-09 | Expand a `工作过程` group containing enough operations that the bounded list must scroll | The first frame appears without a visible stall; off-screen rows mount as the inner list scrolls | Pending |
| PROC-10 | Collapse command, file-read and reasoning rows whose preview source contains line breaks | Every preview stays on one line, joins the source fragments, fills the available width and ellipsizes at the boundary | Pending |
| DIFF-01 | Complete a file edit with additions and deletions, then inspect its collapsed operation row | The row shows exact `+N -N` totals beside the path and the colors remain readable in light and dark themes | Pending |
| DIFF-02 | Inspect failed, interrupted and preparing file-mutation rows | No applied `+N -N` totals are shown until a valid applied diff exists | Pending |
| PROC-11 | Collapse a process group with more than three distinct operation labels | The summary ends with `等N项`, where N equals the total direct operation count; it stays one line | Pending |
| NAV-09 | Open and close drawer search repeatedly | The search field enters and leaves with the same short directional motion; the drawer does not jump | Pending |
| MOT-04 | Collapse and expand the pinned section | Its trailing chevron rotates with the state and remains visible in the header | Pending |
| SET-03 | Toggle reduce motion and reduce transparency | Each switch visibly changes immediately, stays visible with pending feedback, and remains at the saved value after reopening settings | Pending |
| SET-04 | Change every DSH transcript mode and return to the active chat | Compact/standard, detailed-running and verbose modes produce distinct process disclosure behavior without reopening the chat | Pending |
| IMG-06 | Open the image lightbox and tap empty space around the contained image | The lightbox closes; taps on the image itself do not close it | Pending |
| IMG-07 | Long-press an image in the lightbox and confirm the system save prompt | The original image appears in the system photo library and one short success toast is shown | Pending |
| PROC-12 | Repeatedly expand and collapse `工作过程` and a child operation | Preview text remains stable with no one-frame flash or reordered text | Pending |
| NAV-10 | Inspect the drawer workspace selector with `全部` and with a long workspace title | The browse glyph remains attached to the trailing-aligned label at the content edge | Pending |
| DEST-01 | Tap `插件` in the drawer | The drawer closes and the Plugin compatibility surface opens without a crash | Pending |
| DEST-02 | Tap `自动化任务` in the drawer | The drawer closes and the Automation compatibility surface opens without a crash | Pending |
| DEST-03 | Tap `更多` in the drawer | The drawer closes and the More compatibility surface opens without a crash | Pending |
| MOT-05 | Collapse and expand a populated workspace group | Children animate toward and away from the header; expansion emerges downward without a bottom-up float | Pending |
| EXIT-01 | Press system Back once in a selected chat, then wait less than two seconds and press Back again | A `再次滑动退出` toast appears after the first gesture and the second gesture exits | Pending |
| EXIT-02 | Press system Back once in a selected chat and wait more than two seconds | The app remains open and a later Back gesture re-arms exit instead of terminating | Pending |
| DIFF-03 | Open an expanded file-change diff and tap the `#` code control | Real old/new line numbers appear in a stable gutter; tapping again removes them; add/remove colors do not change | Pending |
| IMG-08 | Send two or more images in one user message and inspect the bubble | No filename captions appear; compact thumbnails share rows, wrap as needed, and each opens the matching lightbox image | Pending |
| FILE-06 | Tap each of several valid file and folder links in one transcript message | Every tapped link resolves independently and opens its matching root-level preview/browser | Pending |
| SET-05 | Open `设置 > 服务与账户` | The `当前服务` label and service address align to the leading edge | Pending |
| SET-06 | Open interface mode, dismiss it, then open it again without leaving the service page | The sheet opens on every attempt and closes cleanly by outside tap, close control or selection | Pending |
| SET-07 | Open `设置 > DSH 设置` against plugin 0.3.5 | The page shows `插件版本 0.3.5` in a compact read-only row; an older Host without the field shows `未报告` | Passed; the online phone showed `插件版本 v0.3.5` and the deployed `/pocket/api/state` returned `pluginVersion: "0.3.5"` |
| AUTH-01 | Tap logout, dismiss the confirmation, then confirm logout | Cancel keeps the session; confirmation clears auth/caches and returns to login | Pending |
| AUTH-02 | Complete logout and inspect the login address field | The previous service address is prefilled and can be reused without retyping | Pending |
| NAV-11 | Authenticate on a phone with no selected conversation | The session drawer opens automatically after authentication and exposes the current sessions | Pending |
| NAV-12 | Close the drawer while no conversation is selected, then tap the landing menu control | The drawer closes and reopens with the standard transition; the landing surface is not a navigation dead end | Pending |
