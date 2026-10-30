# Markdown Highlight and Turn Footer Implementation Specification

Date: 2026-10-30

Requirements:
[MD-01, MD-02, MSG-01 and MSG-02](../requirements/2026-10-30-native-shell-performance.md)

Research:
[Markdown highlight and message footer](../research/2026-10-30-markdown-message-footer.md)

Upstream presentation baseline:
`deepseek-ai/deepseek-harness@ce7073d51254c26cd63b22a60835b8f948deb447`.

## 1. Code highlighting

The current fenced-code path is single-color monospace text. Add a pure ArkTS
highlighting service rather than embedding Shiki's Node/TextMate/DOM runtime.

Define:

```text
kind = plain | keyword | string | comment | number | constant |
       function | type | property | punctuation | added | removed

NativeCodeToken {
  text: string
  kind: CodeTokenKind
}
```

Invariant: concatenating all token `.text` values exactly equals the original
code. Trimming, newline normalization or color metadata must not change copied
content.

Supported aliases:

- JavaScript/TypeScript/ArkTS and JSX/TSX;
- JSON;
- shell, bash, sh and PowerShell;
- Python;
- Go, Rust, Java, Kotlin, Swift and C-family;
- HTML/XML, CSS/SCSS/LESS;
- YAML/TOML;
- SQL;
- Markdown;
- diff.

Unknown or malformed language metadata uses plain text. The tokenizer uses
explicit finite rules/states, not dynamic regular-expression construction or
remote grammar downloads.

## 2. Rendering and performance

Create `NativeCodeBlock.ets`, used by `NativeMessageView`, with:

- language label;
- horizontal scrolling only;
- stable monospace layout;
- theme-specific token colors;
- plain rendering before optional lazy highlighting completes.

Theme change remaps colors without reparsing the source. Parsed tokens may be
cached by source revision, language profile and tokenizer schema version.

Safety fallback keeps full content readable but disables highlighting when code
exceeds any of:

- 64 KiB;
- 1,500 lines;
- 12,000 tokens.

Off-screen and collapsed process code is not eagerly highlighted. A long
conversation cache restore paints plain code first.

## 3. Turn footer ownership

The assistant copy action belongs to the final visible assistant response of a
completed turn. Intermediate narration must not each draw a copy action.

Extend the transcript projection's UI-only fields:

```text
footerCopyText?: string
footerCopyMessageId?: string
footerOutcome?: completed | failed | stopped
```

When projecting `turn/end`, attach the final closing assistant prose to the
single `turn-footer`. Errors, stopped turns and turns without final prose may
show status but no copy action.

A `NativeTurnFooter` row contains:

```text
[status]                     [copy/check action]
```

The copy action is 28–32vp, the text is secondary 11–12fp, and both share one
baseline/row. No negative margin or absolute overlay is used. Copy success
changes the icon to a check for about one second without changing row height.

User message copy remains independent. Assistant `NativeMessageView` no longer
renders a duplicate copy button.

## 4. Color and accessibility

Use semantic light/dark token colors aligned with DSH:

- comment, keyword, string, number/constant, function, type/property,
  punctuation and added/removed each have explicit colors;
- normal text follows the current app/DSH theme;
- code background and borders use existing semantic surface tokens;
- contrast is checked in both themes;
- copy and status carry accessibility labels;
- horizontal code scrolling works with large text and does not trap vertical
  transcript scrolling.

## 5. Tests and acceptance

Automation:

- token concatenation equals input for CRLF, tabs and Unicode;
- representative fixtures for every supported language family;
- unclosed strings/comments and keyword-like text inside strings;
- unknown language and empty block plain fallback;
- size/line/token threshold fallback without truncation;
- final-only assistant footer ownership;
- no footer copy for failed/stopped/no-final-prose turns;
- completed status and copy occupy one projected footer row.

Device E2E:

- inspect token colors in light/dark themes;
- copy each language fixture and verify exact source;
- horizontally scroll long lines without affecting the outer list;
- scroll a 300–1,000-line block and verify bounded frame drops;
- verify long-code fallback remains complete and readable;
- verify final status/copy alignment, large text and accessibility labels.
