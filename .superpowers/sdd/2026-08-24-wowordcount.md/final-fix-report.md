# Final Review Fix Report — wowordcount (feat-wowordcount)

Date: 2026-08-25
Agent: final-review fix agent
Result: **all 5 findings fixed, FAIL 0 | WARN 0 | SKIP 0 | PASS 162**

## What changed per finding

### Finding 1 (Critical) — nominaltext permission
`jamovi/wordcount.a.yaml`: `textVar.permitted` changed from `[id, nominal]`
to `[id, nominal, nominaltext]`. Plain-text columns import as Nominal Text
(`nominaltext`) and are now selectable in the variable picker.
Verified via `yaml::read_yaml`: permitted is `chr [1:3] "id" "nominal" "nominaltext"`.

### Finding 2 (Critical) — wildcard overlap parity
**R/counter.R (`wc_count_document`)** — token and n-gram loops restructured so
the two mechanisms no longer merge into a deduped category set:
- exact hits: `unique(exact_*_lookup[[term]])` → `+1L` per distinct type;
  detected appends once per hit category.
- wildcard hits: `wc_trie_match()` result iterated with duplicates preserved →
  `+f` per matching prefix; detected appends per match event (downstream
  `wc_analyze_corpus` still `sort(unique())` before rendering columns).
File-top comment updated: wildcard contributions accumulate PER MATCHING PREFIX
(no dedup), replicating upstream `_match_prefix_categories()` iteration.

**tests/testthat/test-counter.R** — new regression test added:
`"overlapping prefixes accumulate once each like upstream"`.
NOTE (deviation, disclosed): the finding's snippet dictionary was internally
inconsistent — it contained only `c*`/`ca*` (nothing matches `dog`), yet the
expected value/comment assert `cat→2, dog→1 = 3`. Under upstream parity the
snippet-as-written yields 2 (verified empirically before changing anything).
Minimal amendment: added `"dog\tX"` to the dictionary so the asserted value 3
and its comment arithmetic both hold; this also exercises exact+wildcard
interaction in one document.

**tools/generate_golden.py** — `any()` wildcard accumulation replaced by
per-matching-prefix accumulation for tokens and n-grams:
`n_match = sum(1 for p in wildcard_single[cat] if p and tok.startswith(p))`;
`counts[cat] += f * n_match`; empty prefixes skipped; exact terms unchanged
(+1 per distinct type). Docstring updated to state per-prefix accumulation
(no dedup across overlapping prefixes of one category).

### Finding 3 (Minor) — R6 declaration
`DESCRIPTION`: `Imports: jmvcore (>= 2.4), methods, R6`.

### Finding 4 (Minor) — honest parity wording
`README.md` Parity section now says results were verified against a stdlib-only
replica of the original counting logic (`tools/generate_golden.py`, itself a
verbatim port kept in-tree) bundled as golden fixtures — no claim of executing
the Streamlit app. Performance section gained: "A live progress bar and
incremental feedback are planned; current builds report a summary line after
completion."

### Finding 5 (Minor) — zero-hit warning gap
`R/wordcount.b.R`: notes logic extended — if all `n_tokens == 0` keep the
existing "no tokens" note; ELSE IF every `*_word_count` column is 0, add
tbl note key `noHits` with message "The dictionary matched no words in the
selected texts." Verified by `parse("R/wordcount.b.R")`.

## expected.json diff explanation

Regeneration ran cleanly (`wrote 8 records`) and produced a **byte-identical**
file — `git status` shows no modification and `git diff` on
`inst/tests/golden/expected.json` is empty. Explanation: the fixture
dictionary's only wildcard prefixes are `can*`, `could*`, `you*`, all in the
single category Social, and none of them is a prefix of another (a token would
need to start with two of them simultaneously, which is impossible since they
diverge at the second character). There are no multi-word wildcards. Therefore
per-prefix accumulation never fires more than once per token/n-gram in this
corpus, and no count changes. The generator patch is still required for parity
on dictionaries that DO contain nested prefixes (e.g. `c*` + `ca*`).

## Commands and outputs

1. `python tools\generate_golden.py` → `wrote 8 records`; expected.json unchanged.
2. First test run: FAIL 1 — the finding's test snippet inconsistency described
   above (`got 2, expected 3`). Root-caused (dictionary lacked any rule matching
   `dog`), amended test dictionary minimally.
3. `& "C:\Program Files\R\R-4.5.1\bin\x64\Rscript.exe" -e "testthat::test_local('.')"`
   → `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 162 ]` (161 previous + 1 new).
4. `yaml::read_yaml` on jamovi/wordcount.{a,r,u}.yaml → all parse OK;
   textVar permitted confirmed `[id, nominal, nominaltext]`.
5. `parse('R/wordcount.b.R')` → OK.

(One inspection one-liner failed due to PowerShell `$options` interpolation /
native-quoting quirks; rerun via temp script — tooling artifact only, not a
verification failure.)

## Commits

- `3c9694b` fix: per-prefix wildcard accumulation parity and nominaltext permission
  (R/counter.R, tests/testthat/test-counter.R, tools/generate_golden.py,
  inst/tests/golden/expected.json [no-op, byte-identical], jamovi/wordcount.a.yaml)
- `7c74131` docs: honest parity wording, R6 declaration, zero-hit warning
  (DESCRIPTION, README.md, R/wordcount.b.R)

Staging deviation vs brief: `jamovi/wordcount.a.yaml` moved from commit 2 into
commit 1 because commit 1's prescribed message explicitly claims "nominaltext
permission"; leaving the yaml out would have made that message untrue. Commit 2's
message matches its contents exactly.

## Concerns

1. The finding-2 test snippet as written could not pass under any faithful port
   (its dict scores `dog`=0); resolved by adding `"dog\tX"` — flagged here for
   reviewer awareness.
2. Duplicate `detected` appends can now occur inside `wc_count_document` when a
   term matches multiple prefixes; harmless today (`wc_analyze_corpus`
   de-duplicates before output, golden test uses `expect_setequal`) but worth
   remembering if detected lists are ever consumed raw.
