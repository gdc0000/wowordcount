# Multiline dictionary input — decision note

Data: 2026-08-24
Status: resolved by static analysis (Ruling R10); runtime confirmation pending first GUI smoke

## Context

The spec requires pasting a multiline TSV dictionary into the analysis UI.
jamovi's official TextBox documentation lists no multiline property; issue
jamovi/jamovi#1820 (multiline in TextBox) is unresolved. The plan's Task 6
defined three empirical candidates requiring the jamovi desktop app, which is
not installed on this machine.

## Static findings

- The bundled `jamovi-compiler` (jmvtools node_modules) does NOT validate the
  UI element vocabulary at compile time — unknown element types surface as
  runtime rendering issues inside the jamovi client, not build errors.
- `TextArea` and `CodeBox` appear nowhere in the compiler tree (only in
  unrelated vendored HTML-parsing dependencies), so neither is part of the
  compiler's shipped vocabulary.
- Plain `TextBox` bound to a `String` option is the only documented text
  control.

## Decision

Wire the analysis with a plain `TextBox` (`format: term`) for the
`dictionary` String option.

Runtime gate (first GUI smoke after jamovi install): paste a real multiline
TSV and dump `self$options$dictionary` to a temp file.

- If newlines survive → done.
- If stripped → implement brief Candidate C: single-line flat format
  (`term:Cat; term:Cat`) detected automatically in `wc_parse_dictionary`
  when the text contains no `\n` but contains `;`, keeping the same
  interface. Documented deviation from spec §2 until upstream ships a true
  multiline control.

## Cost if wrong

Possible rework of one yaml element + parser fallback branch; both bounded
and pre-designed.
