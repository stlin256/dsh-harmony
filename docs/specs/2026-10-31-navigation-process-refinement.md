# Navigation, process disclosure and motion implementation spec

## Workspace drawer and manager

The workspace header keeps one trailing `全部` control. The redundant add action
is removed because session creation already has a dedicated entry.

`NativeWorkspacePicker` owns a controlled `root | create | archive` page value.
The parent owns that value so Android/Harmony Back can apply the same transition:

```text
create/archive -> workspace root -> drawer -> existing app Back behavior
```

The picker applies safe-area padding to its full-screen surface. Page changes use
the navigation motion token and direction.

## Settings presentation

The settings tree remains mounted after first use. Its wrapper animates opacity
and a small horizontal translation whenever `nativeSettings` changes, so cached
content appears immediately and exit does not disappear in one frame. The
wrapper only accepts hit testing while visible.

The root and child pages both use a left chevron. Forward child navigation enters
from the trailing edge; Back and root return enter from the leading edge. This
keeps the information hierarchy consistent.

## Chat Back safety

`NativeWorkspace` publishes whether a chat is selected. `Index.onBackPress`
first closes any higher overlay through the existing native back revision. If no
overlay remains and a chat is selected, Back shows one confirmation dialog. The
dialog is guarded against duplicate presentation. Confirming terminates the
ability; cancelling leaves the chat and its draft state untouched.

## Chat overflow and compatibility controls

The chat overflow menu is rendered as a top-layer anchored overlay inside the
native workspace instead of relying on an anchored popup with an implicit mask.
The first tap sets the open state and Back closes the same state. The full-screen
dismiss layer is transparent, while the action list uses an opaque DSH-neutral
surface, precise border and shadow. There is no modal scrim behind this menu.
Its vertical anchor is the lower edge of the 36vp header control plus a compact
gap, avoiding the former 64vp empty band. The ellipsis button paints a neutral
active surface while the list is open and animates that state with the press
token.

The compatibility sheet disables the platform-added close button. Its header has
two 40vp icon controls: Web history back and close/return to native. Both use the
same neutral surface, border and 44vp effective touch target as the rest of the
native shell.

## Drawer scrim

The mobile shell compositing order is main surface, full-screen scrim, drawer.
The scrim uses a real theme surface color and its opacity is derived directly
from drawer translation for the entire gesture, open animation and close
animation. The drawer surface is above the scrim and carries a restrained,
tight directional shadow. Both are painted from the same progress value so the
shadow cannot visibly enter before the surface or linger after it leaves.

Mobile drawer state is atomic: opening always resets translation to `0`, while
closing always leaves it at negative drawer width. Automatic navigation back to
the session list uses the same state transition as the header action, preventing
an open state from rendering only the drawer shadow after a previous close.
The drawer and its scrim explicitly leave hit testing while closed, so their
transparent layout regions cannot intercept controls in the conversation header.

## Notification persistence feedback

Save operations clear prior errors and use pending indicators on controls.
Successful writes do not assign or render success status text. Local-only
notification persistence followed by a failed server sync is treated as an
error. Toasts remain reserved for errors and destructive-operation outcomes.

## Process projection and disclosure

Each contiguous tool, reasoning and notice sequence in a turn is merged into one
stable `groupedProcess` row. That row owns a single `工作过程` disclosure. Its
direct children are stable operation rows with independent labels and one-line
previews. A group is closed only when its turn or step boundary is complete.
Interleaved user or assistant content starts a new group, preserving source
order.

Opening the group reveals its direct operation rows. Opening an operation reveals
the command, file output, images or reasoning body. The top-level operation
component never renders itself recursively; nested PTC calls are flattened into
summary rows inside the same detail surface. Stable disclosure keys prevent a
tap from replacing one row with another.

The expanded group uses a bounded native `List` with a `LazyForEach` source and a
small cache window. Off-screen operation components are not created when the
group opens. Disclosure state changes before content mounting; the content
transition owns only opacity and a short translation. The whole list is not
built inside `animateTo`, so a turn with many operations does not turn one tap
into a large synchronous component-creation and relayout transaction. Existing
stable operation keys and the 60%/36% height caps remain unchanged.

The group summary reads `message.flat` from the project-owned presentation row.
When the host `transcriptView` setting changes, the settings revision causes a
new presentation row and the group reconciles its disclosure: compact and
standard stay closed, detailed opens a running group, and verbose opens the
group after completion. A manual disclosure still wins until the relevant mode
changes.

Group and child disclosure changes are committed inside one micro-motion
transaction. The preview fades in place and no longer translates while the
detail subtree enters or leaves, preventing a one-frame flash through an
intermediate offset during list relayout.

Chat file resolution publishes a serializable `NativeFileViewRequest` through
AppStorage after the workspace stat/list call succeeds. `NativeWorkspace` renders
the reader or directory browser as a root Stack sibling and owns dismissal.
`NativeInlineText` keeps only the transient resolving indicator and never mounts
a content cover inside the transcript list. This separation applies the same
success-path contract to files and folders: a resolved path always produces a
visible surface, while an unresolved path keeps the short error message.

The workspace measures the transcript viewport in `onAreaChange`. It passes
60% of that height into `NativeProcessView` as the outer operation-list cap and
36% into child tool/reasoning details. Expanded content uses a `Scroll` with its
assigned maximum height constraint: short detail shrink-wraps and long detail
scrolls internally. The separate caps let users inspect a long process without
allowing a nested operation to consume the full transcript and make page-level
scrolling difficult.

## Image lightbox

`NativeImageView` keeps only the lightweight thumbnail. Its image surface is a
complete Button hit target and publishes a serializable request containing the
session id and attachment metadata through AppStorage. `NativeWorkspace` watches
that request and renders `NativeImageLightbox` as a root Stack sibling, outside
message lists and nested Scroll containers.

The lightbox loads the full image from the current account/session attachment
cache or the authenticated `attachment` operation, and releases its PixelMap
when dismissed. The image supports pinch zoom, double-tap reset and drag while
zoomed. An explicit close button and system Back dismiss the overlay before any
drawer, menu or chat navigation. Loading and failure states stay inside the
lightbox. The top toolbar reserves a compact intrinsic inset in addition to the
system safe inset, so its close control never hugs the status-bar boundary.

The lightbox records its viewport and calculates the contained image rectangle
from the attachment dimensions. A single tap outside that rectangle closes the
surface; taps inside remain available to the zoom gestures. Long press writes
the original bytes to a temporary app-cache file with the source image
extension and calls `showAssetsCreationDialog`. The system confirms the
user-visible photo-library copy, and the temporary file is then removed.

`read_image` tool results use the attachment list as their only expanded payload.
Raw arguments, path metadata and the text output are suppressed for this
category. `NativeImageStrip` lays out compact 84vp thumbnails in a leading-aligned
`Flex` with `FlexWrap.Wrap`; extra images continue on subsequent rows using the
available width. Each thumbnail is a complete 44vp-minimum hit target and
publishes the same serializable lightbox request as larger message images. The
strip itself does not own a `bindContentCover`, so wrapping and nested process
disclosures cannot trap the lightbox in a local presentation layer.

Zoom state includes scale plus translation. Pinch scale is relative to the scale
at pinch start, so a second pinch never restarts from one-times scale. The pinch
focus adjusts translation around the focal point. A one-finger pan records the
translation at drag start, applies the gesture's cumulative offset, and clamps
the result to the scaled image bounds. Pinch and pan recognizers run in parallel.
The lightbox suppresses the synthetic click that follows a pan or pinch, which
prevents a drag release from being interpreted as an outside tap. Deliberate
double-tap resets scale and translation together. An actual tap outside the
translated, scaled image still closes the lightbox.

Scrollable process bodies reserve a trailing content gutter for platform
scrollbars. The gutter belongs to the inside of the detail surface, so text,
images and action rows retain the card's visual left edge while ending before
the scrollbar thumb.

Tool results retain the normalized `NativeTextBlock` projection when call and
result records merge. `NativeRichContent` renders those blocks with the same
heading, quote, table and syntax-highlighted code primitives used by assistant
messages. Plain string output remains the fallback for older hosts or tool
payloads that do not contain Markdown structure.

Verbose mode may initially reveal direct operations, but it keeps the same data
shape and bounding policy. Compact and standard/detailed honor the existing
running/completed presentation policy.

The drawer workspace header uses a trailing intrinsic selector. The glyph and
label stay in one content-sized group, so default `全部` and long workspace
names share the same right edge without an inner trailing gap.
The browse glyph and label form one intrinsic trailing group; no fixed internal
label width can strand the glyph toward the center.

Workspace group changes run through one micro-motion transaction. New child
rows use an asymmetric transition whose insert starts above the final row and
moves down into place, while removal retracts toward the group header. The
visual origin therefore remains attached to the disclosure header.

Tool and reasoning rows keep a single-line preview in every chat presentation
mode, including compact. Expansion fades the preview to zero opacity with the
micro motion token and reveals the direct detail. Reasoning body renders inside
a low-contrast surface without a duplicate second-level reasoning heading.

All compact operation summaries pass through one whitespace normalizer before
binding. CR/LF, tabs and repeated spaces become one separator, so a multiline
reasoning or argument preview continues on the same visual line. The component
owns the final width-sensitive ellipsis; the model keeps enough text to fill any
phone width rather than stopping after the first source line.

When a grouped process has more than three distinct activity labels, the preview
appends `等N项`, where `N` is the number of direct operations in the group. The
group row and direct operation rows use a 4vp semantic gap around the separator
and preview. The preview owns the remaining width, remains `maxLines(1)`, and
ellipsizes only after receiving all available space.

Settled file mutations derive exact totals from the same `NativeDiffDocument`
used by the diff surface. `+N` and `-N` are separate trailing fragments with the
existing semantic colors, so the path preview may ellipsize before the totals.
Failed, interrupted, preparing and unmatched payloads show no totals. The
operation row reads the same applied diff contract as the expanded block, which
keeps the collapsed summary and body counts consistent.

## File references and workspace root

An absolute or cwd-relative link is always tried first. A bare basename that is
absent at that location triggers a bounded workspace search through the public
`workspaceFiles/list` RPC: breadth-first, at most four levels and 64 directories,
stopping at the first exact filename. The search uses the active Session as the
workspace scope and never substitutes a local device file. A matching child
opens in `NativeFilePreview`; exact directories continue to open in
`NativeFileBrowser`.

The gateway normalizes the workspace root path from `''` to `'.'` for
`workspaceFiles/list`, matching the upstream contract. Stable `workspace-file/*`
failure codes pass through so the App can distinguish a directory, missing file
and unsupported content without displaying server details. Valid results open
the root-level reader or browser surface rather than a Text-local content cover.

## Diff line numbers

`NativeDiffRow` owns two optional line-number projections. Context rows carry
both the previous-file and next-file line number, deleted rows carry only the
previous-file number, and added rows carry only the next-file number. Structured
`oldText`/`newText` edits derive these positions while diffing. Unified patches
read each `@@ -old,count +new,count @@` hunk start and advance independent old
and next counters. Path and elision rows carry no numbers.

`NativeDiffBlock` exposes a dedicated code control in its toolbar. Toggling it
changes a stable two-column monospace gutter while leaving row backgrounds,
copy behavior and diff colors intact. Unavailable sides render as blank cells
instead of a misleading zero. The control uses the DSH neutral active surface
and an accessibility label that reflects the current state.

## User-message image strip

User attachments use the same root-level lightbox request as every other image,
but the bubble renders them through `NativeImageStrip` with a smaller compact
size and no attachment-name caption. The strip is a leading-aligned wrapping
Flex, so images share rows and continue onto additional rows when the 82-percent
message bubble is full. Compact thumbnails keep at least a 44vp hit target and
retain the filename only as accessibility metadata. Process image strips keep
their existing larger compact size.

## Inline file opening

Each linked `Span` owns an `onClick` callback carrying its own `href`. This avoids
the former parent-Text behavior, which could act only when the entire Markdown
value contained exactly one link. A linked span publishes the same serializable
root file request used by file browsers. Resolution still prioritizes the exact
workspace path, then bounded basename lookup, then directory listing. This
surface does not mount a transcript-local `ContentCover`; otherwise a nested
transcript row can capture the visible loading layer while the root preview is
mounted underneath it.

## Connection settings and logout

The service metadata card explicitly aligns both its label and address to the
leading edge. The interface-mode sheet sets its reactive visibility to false in
its sheet `onDisappear` callback, matching outside-tap, close-control and action
selection dismissals so the next tap creates a fresh presentation.

Logout first presents a native confirmation dialog. Cancelling leaves the
connection untouched. Confirming clears the remote session where possible,
cookies, web storage and account-scoped transcript, metadata and attachment
caches. It then resets the in-memory client and surfaces to the login state.
The normalized public origin is deliberately retained in both preferences and
the login address field for the next connection attempt; credentials, access
keys and scoped caches are still cleared.

## DSH plugin version

`createApp` owns the gateway state envelope. The plugin passes the version read
from its own packaged `package.json`, and `/pocket/api/state` returns it as an
optional, length-bounded `pluginVersion` string. The native `GatewayState`
retains that field. `NativeSettings` refreshes it together with the DSH settings
tree and renders a compact read-only `插件版本` row above the transcript
settings. A missing field from an older plugin displays `未报告`; an ordinary
connection failure does not fabricate a version.

## Empty-workspace drawer entry

Every path that resolves to no selected conversation calls the same staged
`openDrawer(false)` transition used by the conversation menu, without issuing a
duplicate metadata refresh. This covers first authentication, an unavailable
notification route, empty session results and reconnect errors. Repeated reloads
are idempotent while the drawer is opening or already open.

The unselected landing surface also renders a compact panel control at the
leading safe edge on phones. It uses the same drawer transition with its normal
refresh. Closing the drawer therefore does not leave an empty workspace without
a visible navigation entry.

## Setting rows and scroll control

The whole setting row owns the toggle gesture. The visual `Toggle` ignores hit
testing so a tap cannot fire both the row and switch handlers. Updates remain
optimistic and roll back on persistence failure.

The settings root header contains only its title. Child settings pages own the
leading Back affordance; system Back remains available at the root.
The scroll-to-bottom control uses a 44vp circular Button with zero padding and a
full-surface clip. Its six-vp new-content dot stays inside the same circular
layer.

Appearance toggles are not removed from the view tree while saving. Their row
shows a compact progress indicator beside an always-present switch; the switch
binds directly to the optimistic local value and animates to that value. A
failed write restores the previous value. For native appearance preferences,
the successful bridge response is parsed as the authoritative state and used to
settle the local switch.

The drawer search icon changes the `searchOpen` state at tap time. The TextInput
is inserted with the micro row transition and removed with the inverse
transition. Opening translates upward from a four-vp offset; closing leaves in
the opposite direction while opacity follows the same timeline.

The pinned section header retains the pin glyph and adds a trailing chevron. It
rotates between down and trailing direction using the micro motion token, so the
collapsed state has both textual count and explicit shape feedback.

Drawer utility rows close the drawer and schedule the compatibility destination
for the next task. The web surface mounts after the press callback and native
drawer teardown have completed, avoiding the re-entrant transition reported on
device.

## Chat exit gesture

The first system Back gesture in a selected chat records an exit-arming
timestamp and shows a 1.5-second `再次滑动退出` toast. A second Back gesture
within two seconds calls `terminateSelf`; a later first gesture re-arms exit.
No modal confirmation is created.

## Validation

- Node model tests cover stable grouped-process identity, one operation row per
  child, absence of a separate `turn-control`, whitespace-flattened previews,
  exact diff totals and nested calls.
- Both HAP variants compile after shared ArkUI changes.
- Device E2E covers safe areas, Back order, transitions, first-tap menu access,
  compatibility controls, drawer scrim, large-process first-frame responsiveness,
  file-mutation totals, real diff line-number gutters, wrapped user-image
  thumbnails, independent inline-link opening, settings interaction recovery,
  confirmed logout, retained login address, empty-workspace drawer entry and
  repeated process disclosure.
