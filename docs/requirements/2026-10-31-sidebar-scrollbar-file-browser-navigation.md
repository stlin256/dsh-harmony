# Sidebar scrollbar and file browser navigation requirements

## User requirements

- In the mobile session drawer, move the conversation-list scrollbar closer to
  the drawer's right edge without moving or truncating row controls.
- While the file browser is open, the HarmonyOS system back gesture must operate
  inside the browser:
  - an open file preview closes first;
  - a nested directory returns to its parent directory;
  - the workspace root requires two back gestures within two seconds to close
    the browser;
  - the first root back gesture shows `再次滑动退出文件浏览`.
- Reopening the file browser after visiting a nested directory must preserve a
  navigable workspace-relative path. Returning to the parent must work after
  reopening.
- Directory rows use a dedicated folder SVG. Regular files keep their existing
  file/code glyph.
- Directory and file rows are grouped, with directories first, and each group
  is ordered case-insensitively by name.
- Directory press feedback uses the whole rounded row surface. No rectangular
  Button state overlay is shown.
- Opening image, code, Markdown or SVG files from the browser uses the server's
  canonical display directory plus the file name. Directory navigation remains
  workspace-relative, and row downloads use the same canonical file path.

## Acceptance criteria

- The mobile conversation scrollbar is visually separated from row overflow
  controls and sits near the drawer edge.
- System back in a nested directory never closes the browser.
- System back at the workspace root never closes the browser on the first
  gesture and closes it on the second gesture within the confirmation window.
- Closing and reopening the browser after nested navigation preserves the
  nested directory and allows a system-back return to its parent.
- Directory and file glyphs are distinguishable in both light and dark themes.
- Existing file preview, download and read-only behavior does not regress.

## Privacy and compatibility

- Navigation state stores workspace-relative paths only and remains
  process-local, scoped by session.
- No private deployment host, credential, transcript or absolute server path is
  added to source, tests or documentation.
- The app remains read-only for workspace files.
