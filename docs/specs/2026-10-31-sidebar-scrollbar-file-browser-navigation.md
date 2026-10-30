# Sidebar scrollbar and file browser navigation implementation spec

## Sidebar list geometry

The session list keeps its current content hit targets and semantic row
padding. Its scroll container extends 8vp toward the drawer edge so the native
scrollbar paints near that edge. Session rows retain their own right inset, so
the overflow button and list text do not move into the scrollbar track.

The list explicitly uses `BarState.Auto`; the change is geometry-only and does
not add a custom scrollbar, overlay or animated decoration.

## Browser path model

`NativeFileBrowser` stores two path values:

```text
navigationPath  workspace-relative request path ('' is workspace root)
displayPath     server-provided presentation path
```

Only `navigationPath` is used by parent/child navigation, file requests,
directory requests and `rememberBrowsePath`. `displayPath` must never be parsed
to derive a directory navigation request.

Before a path enters the browser history, `NativeHarnessClient` normalizes it
against the session cwd. A path equal to the cwd becomes root (`''`), and a
descendant of the cwd loses the cwd prefix. This also normalizes absolute chat
file references before their parent directory is remembered.

The browser also receives the selected Session's workspace root from the
workspace snapshot. This fallback is required because older Host exports may
omit `cwd` from the Session list. The snapshot root is used before the App
falls back to the client's Session cwd map.

`load(next)` normalizes `next` as a relative workspace path. It commits
`navigationPath` only after a successful list response. A failure leaves the
previous listing and navigation path intact.

Opening a child directory appends one normalized segment to `navigationPath`.
Going to the parent removes one segment; at root the action is disabled.
Breadcrumb paths are projections of `navigationPath`, not the display path.

The chat-link browser route also records the requested relative path rather
than replacing it with a server-displayed absolute path. File-preview routes
record their parent directory using the same relative-path rules.

## System Back

The existing `nativeBackRevision` remains the one system-back signal.
`NativeWorkspace.backToSessions` hands control to the mounted browser whenever
`fileViewOpen && kind === 'browser'`, rather than closing it directly.

`NativeFileBrowser` handles that signal in this order:

1. If a nested preview is open, close it.
2. If `navigationPath` is not root, load its parent.
3. If root, arm a two-second exit window and show
   `再次滑动退出文件浏览`.
4. If root is already armed, call `onClose`.

Every successful navigation and preview close clears the armed state. Direct
toolbar actions keep their existing behavior: chevron returns one level and the
close button closes the browser immediately.

## File operations

Directory entries carry names but no path. For a regular file, the browser
joins the successful listing's canonical `displayPath` with the entry name.
That canonical path is passed to both `NativeFilePreview` and
`NativeFileTransfer.download`. If a Host omits `displayPath`, the browser falls
back to the workspace-relative child path.

This separation lets `workspaceFiles/list` keep a relative navigation scope
while `workspaceFiles/stat`, `read`, `readBytes` and upload-free download reads
continue to use Host-provided canonical file locations.

## Icons

A locally packaged `folder-outline.svg` uses the shared 16-unit grid and is
tinted by `DSHIcon` through the existing color filter. Directory rows use
`folder-outline`; regular files keep `code-outline`; unknown entries keep
`question-outline`.

The list projects directories first and files second, each with a compact
section label. Both groups sort case-insensitively by name. The row's Button
disables its built-in state effect; a touch-down state paints the complete
10vp-radius Row and resolves with the shared press motion token.

## Test contract

- Gateway tests continue to verify that root is sent upstream as `.` and nested
  relative request paths are forwarded unchanged.
- App model/geometry review verifies that only navigation paths drive requests.
- Device E2E verifies nested Back, root double-Back, remembered nested
  navigation, directory glyph rendering and sidebar scrollbar placement.
- Device E2E verifies image, Markdown, SVG and code preview plus row download
  after a directory has been reached through relative navigation.
