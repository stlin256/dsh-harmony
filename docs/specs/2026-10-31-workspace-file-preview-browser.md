# Workspace file preview and read-only browser implementation spec

## Document model

`NativeDocumentModel` classifies a workspace path before any content request.
Classification is based on a normalized, lowercase extension and does not use
the response body as a type oracle.

```text
image     -> platform-decoded preview only
svg       -> preview | code
markdown  -> preview | code
code      -> code
text      -> code
unknown   -> download-only error surface
```

The image set includes the platform-supported raster/container extensions used
by the reader: PNG, JPEG, WEBP, GIF, BMP, ICO, DNG, HEIC and HEIF. SVG is handled
as a switchable document. The code mapping covers JavaScript, TypeScript,
ArkTS, JSON, shell, PowerShell, Python, Go, Rust, Java, Kotlin, Swift, C/C++,
C#, HTML/XML, CSS-family, YAML, TOML, SQL, Markdown, diff/patch and Ruby. An
extensionless text-like file falls back to the text reader.

The model also provides pure helpers for source line numbering and a small
block projection used by Markdown preview. These helpers contain no ArkUI
dependencies so the gateway model suite can test their contracts.

## Reader data flow

The reader first calls `workspaceFiles/stat`. Image and SVG preview requests
read complete byte windows from `readBytes`, advancing by the returned window
length and stopping at `eof`. Every window must retain the initial file version.
A configured preview ceiling prevents unbounded bitmap memory use; an image
above the ceiling remains downloadable.

The byte endpoint carries window metadata in `X-DSH-File-Window`, but HarmonyOS
does not expose that custom response header consistently through
`requestInStream` across devices. The App therefore accepts the header as a
`string` or one-value `string[]`. If the platform omits the header, the App
derives offset, version and EOF from the preceding `stat` result and the
observed streamed byte count. EOF is
`offset + received >= stat.bytes`; this also handles an empty file and a file
whose final window ends exactly on the 2 MiB boundary. Header metadata remains
authoritative when present and is still validated against protocol version and
requested offset.

The fallback never treats image bytes as text and never starts decode until the
observed byte count equals `stat.bytes`. A missing version, short aggregate
read, changed version or oversized preview remains a compact preview error with
download available.

PixelMap decoding uses `image.createImageSource(ArrayBuffer)` and a bounded
`createPixelMap` size. ImageSource explicitly supports SVG in API 23's platform
contract. PixelMaps and ImageSources are released when the path changes or the
reader disappears.

Text, Markdown and SVG code requests use the existing paginated
`workspaceFiles/read` endpoint. Additional pages append in source order. Code
line numbers start at the response offset, so pagination never restarts the
gutter at one.

There is no text-to-image fallback. A failed image decode reports a compact
image error and leaves download available. A failed text read is considered a
binary/unsupported preview rather than evidence that the file is an image.

## Mode switch and views

`NativeDocumentModeSwitch` is a 76vp by 32vp rounded rectangle. A 34vp inner
highlight translates between its two halves with the `micro` motion token.
Preview uses a locally packaged `eye-outline.svg`; code reuses
`code-outline.svg`. Both glyphs are tinted through `DSHIcon`, preserving theme
adaptation. Active and inactive colors remain distinguishable in light and dark
modes.

SVG and Markdown begin with `mode = preview`. A mode change is local UI state
and survives additional-page loads. Images and ordinary code files do not show
the switch because they have only one meaningful mode.

`NativeCodeViewer` renders a two-column source surface. The gutter column and
the horizontally scrollable code column share a fixed 22vp line rhythm. Each
source line is highlighted with the existing `nativeHighlightCode` language
mapping. A long line scrolls horizontally instead of wrapping, while the outer
reader scrolls vertically. The code body remains selectable.

Markdown preview is a block projection over the complete loaded text. It keeps
ordered blocks for headings, quotes, fenced code, tables and paragraphs.
Inline links use the existing authenticated link surface. Fenced code uses the
same syntax highlighting as chat. Pagination appends before re-projecting, so
block order is stable.

## Download

`NativeFileTransfer` owns both full-byte preview loading and user-directed
downloads. Its download path:

```text
DocumentViewPicker.save
-> open selected local URI
-> loop readBytes (up to 2 MiB per window)
-> verify version, offset and eof
-> write each returned window directly
```

Bytes are not accumulated for downloads. Cancelling the picker exits without a
toast. A failed read or local write shows one short error. Temporary app-cache
files are neither required nor created by workspace downloads.

The preview toolbar and each regular file row share this service. The row
download button stops click propagation so the row does not also open the file.

## Browser history and utility menu

`NativeHarnessClient` keeps an in-memory `sessionId -> last successful directory`
map. `NativeFileBrowser.load` records a directory only after a successful list
response. Opening a file from a transcript records the file's parent directory.
The map is cleared with the rest of the in-memory client state at logout.

`nativeUtilityMenu` always projects `files` first with the `browse-outline`
glyph. Existing capability-gated export actions follow it. The workspace menu
handler closes the overflow surface and opens:

```text
kind: browser
sessionId: active session
path: client.lastBrowsePath(active session) or ''
```

Empty history maps to workspace root, which the gateway translates to `.` for
the upstream list call.

## Read-only boundary

Workspace file support is limited to:

```text
workspaceFiles/stat
workspaceFiles/list
workspaceFiles/read
workspaceFiles/readBytes
```

The App has no workspace-file write API. The gateway exposes no workspace-file
write endpoint and rejects unsupported paths through the fixed native route
allowlist. Download destinations are local user-selected URIs and are outside
the workspace mutation boundary.
