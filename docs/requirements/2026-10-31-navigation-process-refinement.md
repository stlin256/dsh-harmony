# Navigation, process disclosure and motion refinement

## User requirements

- In the session drawer workspace header, remove the extra add button and let the
  `全部` selector align to the trailing edge.
- Workspace management and its child pages must respect the top system safe area.
  System Back must unwind child pages, then the workspace manager, then return to
  the drawer instead of ending on the home surface.
- Settings entry and exit must animate. Root and child navigation must use the
  same directional back affordance rather than mixing close and chevron icons.
- Leaving a native chat with system Back must require an explicit confirmation.
- The compatibility-mode toolbar must replace its text buttons and duplicated
  sheet close control with compact, consistent icon controls.
- The drawer scrim must animate continuously and read as a directional shadow,
  without a flat gray flash or an abrupt opacity jump while closing.
- Successful notification preference and settings saves must not show status
  copy. Failures remain visible.
- The in-chat overflow button must open its action menu on the first tap.
- Keep one `工作过程` container for each contiguous process block. Its expanded
  state shows direct operation rows such as `执行了命令…`, `已读取文件` and
  `思考过程`. Tapping an operation reveals its bounded detail; repeated tapping
  must not crash.
- Chat file references must open the native file preview even when the model
  emitted only a basename that lives in a nested workspace directory. Workspace
  root browsing must use the upstream `.` path rather than an empty string.
- The scroll-to-bottom control must be a true circle.
- The entire reduce-transparency and card task-name setting rows must be tappable,
  not only the small switch thumb.
- Command, file-read and reasoning rows must keep one-line previews while
  collapsed. Expanding the row fades the preview away and reveals the direct
  detail with the same disclosure motion.
- The chat overflow action list must be an opaque, solid surface and must not
  dim or mask the conversation behind it.
- The mobile drawer must present a real full-screen scrim together with a
  restrained edge shadow. Neither the shadow nor scrim may visibly lead the
  drawer during open or trail it during close.
- The settings root must not show a close action in the header. Its leading
  Back affordance and system Back remain the only exit actions.
- Tool activity must retain an upper `工作过程` container for each contiguous
  process block. Expanded containers show direct operation rows such as
  `执行了命令…` and `思考过程`; nested detail is disclosed from those rows.
- Expanding an operation must not crash. Its expanded child surface is an
  independently scrollable region whose maximum height is 36% of the visible
  transcript viewport, while the parent `工作过程` list may use up to 60%.
- Thumbnail images inside an expanded tool result must remain tappable and open
  a root-level full-screen lightbox. The lightbox must preserve the authenticated
  attachment scope, support pinch zoom and reset, show loading/error states, and
  close through an explicit control or system Back.
- `read_image` results must omit the raw read arguments and file metadata. Their
  attachments render as a compact, left-aligned thumbnail list that wraps across
  multiple rows as space requires. Each thumbnail opens the same root-level
  lightbox.
- Scrollable expanded process detail must inset its content from the scrollbar
  track so controls and text never overlap the thumb or drag handle.
- The expanded `工作过程` list may occupy up to 60% of the visible transcript
  viewport. An individual child operation expansion keeps a smaller independent
  bound so the conversation itself remains easy to page through.
- Markdown returned by an expanded file-read operation must use the native DSH
  reading hierarchy for headings, quotes, tables and highlighted code instead of
  appearing as one undifferentiated text block.
- Successful chat file and directory references must always present their native
  reader or browser. A valid link must not silently succeed inside a nested Text
  content cover while producing no visible response.
- The chat overflow list must sit directly below its ellipsis trigger without a
  visible vertical gap, and the ellipsis control keeps an active highlight while
  that list is open.
- The image-lightbox close control must remain clear of the status-bar edge.
- In the drawer workspace header, the selected workspace label, including the
  default `全部`, aligns to the trailing content edge.
- Expanding `工作过程` must stay responsive when a turn contains many operations.
  Opening the group must not synchronously build every off-screen operation row
  inside one animated state transaction.
- Every single-line operation preview is whitespace-flattened, including text
  that contains line breaks. It fills the available trailing width and uses the
  platform ellipsis when the row is too narrow.
- A settled file-modification row shows its applied line totals as
  `+added -removed`, following the upstream DSH tool-row behavior. Failed,
  interrupted, preparing and non-diff rows show no invented totals.
- A collapsed process preview names the actual operation count after the
  representative labels, for example `执行了命令、已读取文件等11项`. The label,
  separator and preview use a tighter single-line rhythm so the count remains
  visible without wrapping.
- The drawer search field enters and leaves with a short, directional opacity
  and vertical motion transition.
- The pinned section header keeps a visible disclosure chevron whose direction
  reflects expanded/collapsed state.
- Appearance toggles must update their switch position immediately, keep the
  switch visible while persistence is pending, and retain the authoritative
  persisted value after the write settles.
- Changes in the DSH settings page must affect the current native transcript
  after saving. In particular, `transcriptView` must alter process disclosure
  presentation rather than only updating stored data.
- Tapping the empty area around an image in the lightbox must dismiss the
  lightbox. Long-pressing the image must save the original attachment to the
  system photo library through the platform save flow.
- Collapsing `工作过程` and its child operations must not flash or briefly
  reorder the preview text.
- In the drawer workspace selector, the browse glyph must move with the label
  when `全部` or a workspace name is aligned to the trailing edge.
- Tapping `插件`, `自动化任务` or `更多` in the drawer must open the matching
  compatibility surface without terminating the app.
- Expanding a workspace group in the drawer must reveal its children downward
  from the group header. Collapsing must reverse that spatial direction and
  animate instead of replacing the list in one frame.
- When a chat is active, the first system Back gesture shows a short
  `再次滑动退出` toast. A second Back gesture within two seconds exits the app.
- An expanded file-change diff exposes a code/line-number control. Toggling it
  must show real old and new file line numbers in a stable gutter; it must not
  only change the wrapped coloring area.
- Images attached to a user message render as compact, filename-free thumbnails
  inside the message bubble. Multiple images share rows, wrap to additional
  rows and each thumbnail opens its matching lightbox image.
- File references in a transcript open from the individual inline link that was
  tapped, including messages that contain several links. Valid files and folders
  must not depend on a content cover nested inside the transcript.
- In `设置 > 服务与账户`, the `当前服务` heading is leading-aligned rather than
  centered.
- The interface-mode sheet must be reopenable after dismissal. Its visibility
  and the bound sheet state must remain synchronized.
- Logout requires an explicit confirmation. After logout, the previous public
  service address remains prefilled for the next login while authentication and
  cached session data are cleared.
- On a phone, first authentication with no selected conversation opens the
  session drawer automatically. If the drawer is dismissed while no
  conversation is selected, the landing surface keeps a compact menu control
  that can reopen it.

## Acceptance criteria

- Workspace manager and nested pages do not overlap the status bar.
- Back stack order is workspace child page, workspace root, session drawer.
- Settings root enters and exits with an overlay transition; child navigation
  has matching forward and reverse direction.
- Chat exit shows a confirmation dialog with cancel and exit actions.
- Compatibility mode exposes one back icon, one close icon and no duplicate
  platform close button.
- Drawer scrim opacity follows drawer progress during both open and close. A
  full-screen mask and a separate tight directional surface shadow remain
  visible without either component leading or trailing the drawer.
- Save success is communicated by the final control state and busy indicator.
  No success-only toast or status row is added.
- The chat overflow action menu is actionable on first tap and dismisses from
  Back, its scrim or an action.
- Projected process rows contain no separate `turn-control` record. Each
  contiguous operation block has one stable grouped process identity, and each
  child operation has a stable identity, activity label and one-line detail.
- A basename-only file reference resolves against the active workspace with a
  bounded search when the cwd-relative path is absent. Exact paths keep priority,
  and root listing sends `.` to the Host.
- The back-to-bottom hit target is 44vp square with a 22vp circular clip.
- Tapping any enabled portion of a setting row toggles it once and shows the
  pending state until persistence completes.
- Collapsed command, read-file and reasoning rows each render a single-line
  preview. Expanded rows show direct details only; the preview fades without a
  layout jump.
- The overflow list has an opaque DSH-neutral fill and no visible modal scrim.
- Drawer scrim and surface shadow animate on the same progress timeline as the
  drawer translation, with the drawer on top of the scrim.
- Settings root has no close action; system Back remains available. Child
  settings pages have one leading Back action.
- A contiguous turn process block has one `工作过程` disclosure. It contains
  stable direct operation rows and no component recursion.
- The process-row area may scroll up to 60% of the measured chat viewport; child
  operation details use a separate 36% cap. Reduced motion resolves disclosure
  state immediately.
- Expanding a tool with image attachments renders tappable thumbnails. A tap
  opens the attachment in an app-level lightbox without relying on a content
  cover nested inside a list or Scroll.
- A `read_image` operation shows only its image attachments, with no JSON
  arguments or output metadata. Small thumbnails start at the leading edge and
  wrap automatically; every attachment remains individually tappable and keeps
  its accessible image name.
- Expanded operation content leaves a clear right gutter for an auto scrollbar;
  no text, image or action control sits underneath the scrollbar track.
- The process container uses a 60% viewport cap. Child operation details use a
  separate lower cap and remain independently scrollable.
- Expanded Markdown content preserves block order and applies readable native
  heading, quote, table and syntax-highlighted code treatments.
- File and directory previews opened from chat are root-level app surfaces. The
  same Back stack that handles the image lightbox closes them first.
- The overflow menu is visually attached to its trigger, and the ellipsis button
  shows a persistent active surface while the menu is open.
- The lightbox toolbar retains safe top spacing even when the app-content inset
  is zero.
- After pinch zoom, a drag moves the enlarged image inside the viewport so local
  detail can be inspected. Release and taps elsewhere must not reset the zoom
  unless the user deliberately double-taps or closes the lightbox.
- `设置 > DSH 设置` reports the installed `@dsh-harmony/plugin` version returned
  by the connected Host.
- The drawer workspace selector label has no trailing blank area after `全部`.
- Expanding a large `工作过程` group exposes only viewport-near operation rows
  while scrolling; the first frame does not instantiate the entire list.
- Command, file, reasoning and process previews preserve one visual line after
  newline flattening and show an ellipsis only when the available width is full.
- File-modification rows expose exact applied additions and deletions beside the
  path summary, using distinct add/remove semantic colors.
- Process summary counts use the total direct operations, not only unique
  activity labels. Titles and previews remain one line with a compact gap.
- Opening or closing drawer search animates the field as one unit. Opening moves
  up into place; dismissal reverses the direction.
- The pinned group always exposes a chevron; active groups point down and
  collapsed groups point toward the trailing edge.
- Reduce-motion and reduce-transparency controls show the new value during the
  save operation and roll back only on failure. Successful persistence replaces
  the optimistic value with the value returned by the native store.
- DSH transcript mode reaches the process view immediately through the host
  settings revision. Compact and standard keep disclosure closed, detailed
  opens the running group, and verbose opens completed process rows.

- A normal tap outside the rendered image closes the lightbox; a tap inside the
  image does not. Long press opens the system-confirmed gallery save flow and
  reports success or failure with one short toast.
- Pinch and drag share one interruptible gesture surface. Zoom-relative movement
  is clamped to the scaled image bounds, and a completed pan does not synthesize
  an outside-tap close or a reset to one-times scale.
- The DSH settings page shows the connected plugin version in a compact
  read-only metadata row. If an older Host omitted the field, the row states
  that the version is unavailable.
- Repeated expand/collapse keeps operation preview text stable with no
  one-frame flash while the detail surface enters or leaves.
- The drawer's workspace icon and label remain one trailing-aligned group.
- All three drawer utility destinations mount their compatibility surface on
  the next task after the drawer's press handler returns.
- Workspace child rows enter from above their final position and retract toward
  the header on collapse, using the shared micro-motion token.
- The first chat Back gesture only arms exit for two seconds. A second back
  gesture terminates the ability; no modal confirmation is presented.
- Diff row projection carries old-file and new-file line numbers through both
  structured edits and unified patches. Missing sides use an empty gutter cell.
- User-message image thumbnails are visually smaller than ordinary message
  images, omit attachment names from the bubble, preserve a complete tap target
  and retain the accessible filename for the lightbox.
- Inline Markdown spans own their click action, so every file link resolves
  independently. File-loading progress does not use a transcript-local content
  cover; a resolved request is presented by the root workspace surface.
- The service heading and address share a leading-aligned column. The mode sheet
  resets its bound visibility when it disappears, so a later tap opens it again.
- Logout remains cancellable. Confirming clears server/auth state, cookies and
  scoped caches, then returns to login with the saved normalized origin still in
  the address field.
- Empty and archive-return paths use the same staged drawer transition as the
  conversation header. The empty landing surface never becomes a dead end with
  no visible way to restore the drawer.

## Privacy and compatibility

- No deployment address, credential, signature or transcript fixture is added.
- API 23 remains functional without API 26 materials.
- Reduced motion resolves navigation to the final state immediately.
