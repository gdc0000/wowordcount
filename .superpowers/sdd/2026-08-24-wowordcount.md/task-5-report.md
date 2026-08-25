# Task 5 Report — pipeline.R + golden parity tests against the Python original

Status: **DONE_WITH_CONCERNS** (all tests pass; concerns are documented brief deviations, none blocking)

Commits:
- `2250792` — `test: golden parity fixtures generated from python logic` (generator + 3 golden files)
- `c9aead9` — `feat: corpus pipeline verified against python golden fixtures` (pipeline.R, test-golden.R, DESCRIPTION)

Test result: **FAIL 0 | WARN 0 | SKIP 0 | PASS 161** (`Rscript -e "testthat::test_local('.')"`; counter 16, dictionary 16, golden 115, tokenizer 14). TDD sequence honored: Step-4 red run failed exactly on `could not find function "wc_sanitize_name"` / `"wc_analyze_corpus"` (FAIL 2 | PASS 46), then Step-6 went green after implementing `pipeline.R`.

---

## R8 amendment (controller ruling) — applied BEFORE generating fixtures

The brief's Step-2 generator snippet added FULL FREQUENCY for exact-term hits, contradicting upstream semantics (binding R6; implemented in `R/counter.R`: exact = +1 per distinct type present, wildcard prefix = full frequency +f). Patched `tools/generate_golden.py` counting loops accordingly:

- Tokens: loop exact categories per distinct token adding **+1**, then a separate loop over wildcard prefixes per (token, f) adding **f** (once per category even if several prefixes match — mirrors counter.R's `unique(wc_trie_match(...))`).
- N-grams: identical split for `exact_multi` (+1 per distinct gram type) vs `wildcard_multi` (+f).
- Everything else kept verbatim (parsing, buckets, `required`, tokenizer, ngrams_of, output shape).
- One consequential detail: because exact/wildcard appends are now two separate loops, `detected` could double-record an item hit by both rules in one category. Emission changed to `sorted(set(v))` so detected lists stay de-duplicated, mirroring `wc_count_document`'s `unique(c(ex, wl))`. Without this the JSON would disagree with the R side's `sort(unique(...))`.

Fixture spot-checks proving R8 semantics landed: doc1 `very×3` → Intensifiers **1** (type, not frequency); doc7 `can can can canzoni cani` → Social **5** (=3+1+1, wildcard adds full frequency); doc8 `not×2` → Negations counts `not` once.

## Deviations found and fixed during execution (each traced to its side)

1. **Brief Step-3 test typo — sanitize expectation** (test-side bug): the snippet expected `wc_sanitize_name("Modal Expressions!") == "ModalExpressions"`, which is internally inconsistent with its own second case (`"Social Terms"` → `"Social_Terms"`) — no pure function can satisfy both. Ground truth checked in upstream `app/enhance.py` (gdc0000/WordCount): `columns.str.replace(" ", "_").str.replace("[^A-Za-z0-9_]", "", regex=True)` → spaces become underscores, then strip. Correct value is `"Modal_Expressions"`. Fixed the expectation; `wc_sanitize_name`/`pipeline.R` were already correct and remain verbatim.
2. **Brief Step-3 column-order assertion** (test-side bug): the expected-names vector grouped ALL `_word_count` columns before ALL `_word_perc` columns, contradicting both the brief's own interface spec ("for each category `{Cat}_word_count`, `{Cat}_word_perc`"), the controller binding constraint (same phrasing), and the brief's own verbatim `pipeline.R` (per-category interleaved). Fixed the assertion to build the specified order (`n_tokens, n_types, {count,perc} per category, {detected}` block last); `pipeline.R` untouched.
3. **`expect_setequal(..., info=)`**: installed testthat rejects `info` for `expect_setequal` ("unused argument"). Dropped the argument and wrapped the jsonlite side in `as.character()` to normalize empty arrays (`[]` arrives as `list()` under `simplifyVector=FALSE`) so set-equality compares like-typed vectors across all docs including empty ones.
4. **corpus.txt encoding through the shell**: the mandated PowerShell here-string write mangled `é`/`è` into U+FFFD (shell argument transcoding). Rewrote via PowerShell `[System.IO.File]::WriteAllText` with explicit `[char]0x00E9`/`[char]0x00E8` code points and `UTF8Encoding($false)` — still a PowerShell write, still UTF-8 without BOM. Verified byte-exact against intended strings (`line5 ok / line6 ok == True`), 8 lines exactly, no BOM.
5. **dictionary.tsv extraction method**: written byte-for-byte from the brief's fenced block (programmatic extraction) rather than retyped, preserving the intentional trailing-tab rows exactly. Note: this also preserves the extra *interior* tabs on rows `can*`, `could*`, `you*`, `we` — see Concerns.

## What was built

- `tools/generate_golden.py` — stdlib-only replication of the Python core with the R8 counting split; regenerates `expected.json` from committed inputs (`wrote 8 records`).
- `inst/tests/golden/dictionary.tsv`, `corpus.txt` (committed inputs), `expected.json` (generated).
  Corpus covers: empty line, punctuation-only line, repeated terms (very×3, can×3, not×2), `kind of cake we made`, accents (`perché possiamo`), apostrophes (`l'amico di cani`, `we'll`), mixed EN/IT.
- `R/pipeline.R` — verbatim per brief Step 5: `wc_sanitize_name`, `wc_analyze_corpus(texts, dict, collect_detected = FALSE)` producing `n_tokens, n_types, {San}_word_count, {San}_word_perc[, {San}_detected_words]`; perc = count/max(n_tokens,1) with 0 when n_tokens==0.
- `tests/testthat/test-golden.R` — brief's test with fixes 1–3 above.
- `DESCRIPTION` — added `Suggests: jsonlite` (tests only).

## Parity evidence

The R path (trie-based `wc_prepare_config`/`wc_count_document`) reproduces the linear-scan Python generator exactly on all 8 documents × {n_tokens, n_types, 4 category counts, 4 percs, 4 detected sets} — including empty/punctuation docs (0 tokens → perc 0, empty detected), unicode tokens (`perché`, `è`, `cantare`→`can*`), apostrophe retention (`l'amico`, `we'll` not split), and bigram exact match (`kind of`).

## Concerns (non-blocking)

1. **Golden dictionary content quirk (kept verbatim)**: in the brief's literal TSV, rows `can*`/`could*` carry one extra interior tab, placing their X in the **Social** column; `you*`'s X falls beyond the 5-column header and is silently ignored by both parsers; `we` lands in **Modal_Expressions**. Both sides parse identically (verified empirically in R and Python), so parity testing is unaffected and every semantic class is still exercised (exact single/multi, wildcard=frequency, type-vs-frequency) — just under shifted labels (Modal column holds `we`; Modal wildcards and Social `you*` are untested by this fixture). Flagging in case the controller wants a fixture patch in a follow-up.
2. Three test-snippet deviations documented above (sanitize expectation, column order, `info=`/`as.character`) — each justified against upstream source or the brief's own interface text; no production-code deviation.
