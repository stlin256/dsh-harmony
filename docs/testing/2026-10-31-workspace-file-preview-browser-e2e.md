# Workspace file preview and read-only browser E2E

Status: pending device execution.

| ID | Scenario | Expected evidence | Status |
| --- | --- | --- | --- |
| PREVIEW-01 | Open a PNG larger than one 2 MiB window from a chat file reference | The complete image renders; no repeated reconnect or unsupported-workspace message appears | Pending — sub-2 MiB workspace-browser PNG verified |
| PREVIEW-02 | Open JPEG, WebP, GIF, BMP, HEIC and ICO files supported by the device | Each opens as an image with the same reader toolbar and top download control | Pending |
| PREVIEW-03 | Open SVG from chat and workspace browser | Rendered preview appears by default; source XML is not shown | Pass — workspace-browser preview verified on device |
| PREVIEW-04 | Toggle the SVG mode control from preview to code and back | Highlight block slides; code view shows highlighted source and real line numbers; preview restores the image | Pending — preview half verified |
| PREVIEW-04A | In the workspace browser, open PNG and JPG files when the platform omits the custom byte-window header | Stat and streamed size still complete the window; the image renders without a transport error | Pass — PNG verified; JPG fixture absent |
| PREVIEW-04B | Open an image whose size is exactly one 2 MiB window and an empty file through the same transport | The exact-boundary image reaches EOF without an extra empty-window failure; the empty file remains a non-image file with download available | Pending |
| PREVIEW-05 | Open Markdown from chat and workspace browser | Rendered headings, links, quotes, tables and fenced code appear by default | Pending |
| PREVIEW-06 | Toggle Markdown preview/code and load more source | Code mode remains active, line numbers continue from the response offset, and preview restores after paging | Pending |
| PREVIEW-07 | Open code files in several mapped languages | Source is readable, horizontally scrollable, highlighted where supported, and has aligned line numbers | Pending |
| PREVIEW-08 | Long-press/select code text | Native selection and copy work without triggering mode changes | Pending |
| PREVIEW-09 | Open an unsupported binary | The reader shows a short unsupported-preview error and keeps download available | Pending |
| DOWNLOAD-01 | Tap preview top download and save a PNG | The saved local file is byte-identical to the workspace file | Pending |
| DOWNLOAD-02 | Tap preview download for a text/code file and cancel the picker | Reader remains mounted; no error toast or remote mutation occurs | Pending |
| BROWSER-01 | Open chat overflow menu | `文件浏览` appears as a solid first action with a browse glyph | Pending |
| BROWSER-02 | Use `文件浏览` before visiting any directory | Workspace root opens and the gateway receives `.` | Pending |
| BROWSER-03 | Visit a nested directory, close the browser, then choose `文件浏览` again | The last successfully visited directory opens | Pending |
| BROWSER-04 | Switch to a session with no browser history | `文件浏览` opens that session's workspace root, not another session's directory | Pending |
| BROWSER-05 | Tap a regular file row download control | The file is saved and the nested reader does not open | Pending |
| BROWSER-06 | Tap the remaining row area | The normal preview opens | Pending |
| NAV-01 | Press system Back with a browser-opened file preview, then again in the browser | The preview closes first, then the browser closes, without leaving chat | Pending |
| A11Y-01 | Enable reduced motion, then toggle SVG/Markdown mode | Highlight and content resolve directly to the final state without movement | Pending |
| THEME-01 | Repeat SVG/Markdown mode, browser rows and download controls in light and dark modes | Glyphs, selected highlight, code colors and borders remain legible with no black SVG artifacts | Pending |
