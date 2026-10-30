# Sidebar scrollbar and file browser navigation E2E

Status: pending device execution.

| ID | Scenario | Expected evidence | Status |
| --- | --- | --- | --- |
| DRAWER-SCROLL-01 | Open the mobile session drawer with enough sessions to scroll and drag the conversation list | The scrollbar sits near the drawer's right edge; row text and overflow controls remain fully visible and aligned | Pending |
| BROWSER-BACK-01 | Open a file from inside the file browser, then use the system back gesture | The file preview closes and the directory listing remains | Pending |
| BROWSER-BACK-02 | From a nested directory, use the system back gesture | The browser loads the parent directory and remains open | Pending |
| BROWSER-BACK-03 | At the workspace root, use the system back gesture once | The browser remains open and shows `再次滑动退出文件浏览` | Pending |
| BROWSER-BACK-04 | Repeat the root system back gesture within two seconds | The browser closes and the chat remains open | Pending |
| BROWSER-HISTORY-01 | Enter a nested directory, close the browser, then reopen `文件浏览` | The nested directory reopens and its parent is reachable by system back and toolbar back | Pending |
| BROWSER-HISTORY-02 | Let the two-second root exit window expire, then use system back once | The browser remains open and arms the exit confirmation again | Pending |
| BROWSER-ICON-01 | Compare a directory row and regular file row in light and dark mode | The directory uses a folder glyph and the file keeps the document/code glyph, both with correct theme tint | Pending |
| BROWSER-GROUP-01 | Open a directory containing both folders and files | A compact `文件夹` group appears first and `文件` appears below; each group is name-sorted | Pending |
| BROWSER-PRESS-01 | Press and hold a directory row in light and dark mode | The complete rounded row responds as one surface; no square Button overlay appears | Pending |
| BROWSER-FILE-01 | Open PNG, JPEG and SVG files from a browser directory | Each reader receives a canonical file path and renders through image or switchable SVG preview | Pending |
| BROWSER-REGRESSION-01 | Open Markdown, image, SVG and code files; download a file | Preview mode switching, row downloads and read-only behavior remain functional | Pending |
