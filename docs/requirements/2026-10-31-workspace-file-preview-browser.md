# Workspace file preview and read-only browser

## User requirements

- PNG, JPEG, WebP, GIF, BMP, HEIC, ICO and other image formats supported by
  HarmonyOS ImageKit must open as images in the workspace reader. A decode or
  size-limit failure must remain a file-reader error; it must not be mislabeled
  as unsupported workspace content.
- SVG opens in rendered preview mode by default and can switch to a highlighted
  source-code mode with line numbers.
- Markdown opens in rendered preview mode by default and can switch to a
  highlighted source-code mode with line numbers.
- The SVG and Markdown mode switch is a compact rectangular sliding control.
  The preview half uses an eye glyph and the source half uses the existing code
  glyph. The active half has a solid DSH neutral/blue highlight and the moving
  block uses the shared micro-motion token. Reduced motion resolves instantly.
- Every supported image and code file is viewable. Supported image formats are
  decoded through the platform image decoder. Code and text use a selectable
  source reader with a fixed-width line-number gutter and syntax highlighting
  for known languages.
- Every file preview has a download control in its top toolbar. Download writes
  the original workspace bytes to a location chosen through the HarmonyOS
  document save picker.
- The chat overflow menu always contains `文件浏览`. It opens the current
  session workspace root unless another directory was successfully opened
  during this app process, in which case it opens the last directory for that
  session.
- Every regular file row in the workspace browser has its own download control.
  Activating that control saves the file and does not also open the row.
- Workspace files are strictly read-only. The App and gateway may call only the
  upstream workspace file stat, list, text-read and byte-read capabilities.
  There must be no create, upload, rename, edit, delete or other write route for
  workspace files.
- Directory history is process-local UI state, scoped by session. It must not be
  persisted as a server setting or used across different workspaces.

## Acceptance criteria

- A valid PNG and a valid SVG both render inside the native file reader.
- SVG starts in preview mode; tapping the code half reveals source and real line
  numbers; tapping the eye half restores the rendered SVG.
- Markdown starts in preview mode; code mode preserves line numbers across
  additional text pages, and preview restores headings, links, tables, quotes
  and fenced code blocks.
- Unknown binary files expose download and a short unsupported-preview message;
  they do not display decoded XML or replacement text as if it were the file.
- The top download control saves exactly the original bytes and never writes
  into the remote workspace.
- A file row download target is at least 44vp square, does not open the file,
  and remains aligned without crowding the filename.
- The chat overflow list opens the last visited directory for the active
  session after a successful directory navigation; otherwise it opens root.
- Root browsing continues to send `.` to `workspaceFiles/list`.
- Back closes the file reader or browser before closing the chat.

## Privacy and compatibility

- No deployment origin, credential, cookie, signature, transcript or private
  path is added to source, tests or documentation.
- API 23 keeps full reader/browser functionality with opaque theme surfaces.
- File downloads use the system picker and do not require broad storage access.
