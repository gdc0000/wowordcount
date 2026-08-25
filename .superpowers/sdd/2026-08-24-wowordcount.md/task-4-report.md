# Task 4 Report — counter.R (config preparation, tries, per-document counting)

**Status: DONE_WITH_CONCERNS**
**Commit:** `122009e` — "feat: trie-based counting engine with selective n-grams" (branch `feat-wowordcount`)
**Files:** `R/counter.R` (new), `tests/testthat/test-counter.R` (new)

## Test summary

```
[ FAIL 1 | WARN 0 | SKIP 0 | PASS 44 ]
```

- Expectation-level: 44 pass / 1 fail.
- Block-level: counter 9/10 pass (1 fail), dictionary 16/16 OK, tokenizer 14/14 OK.
- RED verified first: with only the test file present, all 10 counter blocks failed with
  `could not find function "wc_prepare_config"` — exactly the failure the brief predicts.

## What was implemented

- `R/counter.R` verbatim from brief Step 3: `wc_trie_new`, `wc_trie_add`, `wc_trie_match`,
  `isEmptyTrie`, `wc_prepare_config`, `wc_count_document`.
- Tests verbatim from brief Step 1 plus the two controller-mandated amendment blocks
  ("terms longer than max ngram size contribute no lengths", "bare star prefix is ignored").

### Amendments applied (both verified against upstream source)

- **A1**: exact-multi adds length `k` only when `2 <= k && k <= wc_max_ngram_size`;
  wildcard-multi adds `seq(max(k,2), wc_max_ngram_size)` only when `k <= wc_max_ngram_size`.
  Matches upstream `_prepare_analysis_config`: `if 2 <= term_length <= MAX_NGRAM_SIZE` and
  `if prefix_length <= MAX_NGRAM_SIZE: required_ngram_lengths.update(range(max(2, prefix_length), MAX_NGRAM_SIZE + 1))`.
- **A2**: both trie adds guarded by `if (nzchar(prefix))`. Matches upstream `if prefix:` /
  `if not prefix: continue`.

## CONCERN 1 (test failure): brief test "multi-word wildcard prefix matches" contradicts the parity target itself

Test asserts `counts["M"] == 1` for tokens `c("it","might","be","rain","might","bee")`
with dictionary `"might be*"`. Under upstream semantics this is **5**, not 1:

I executed the actual upstream functions (copied verbatim from `gdc0000/WordCount`
`app/text_analysis.py`, main) on that exact input:

```
Scenario B (brief expects M == 1): (6, 5, {'M': 5})
```

Why 5: upstream generates n-grams for lengths 2..5 and wildcard-matches every window whose
string starts with `"might be"` (raw string prefix): `"might be"`, `"might bee"`
("bee" literally starts with "be"), `"might be rain"`, `"might be rain might"`,
`"might be rain might bee"` — each frequency 1, summed by
`category_counts[category] += occurrences`. There is **no** consistent reading of
`_analyze_document` (frequency or distinct) that yields 1; both yield 5. The test's expected
value appears to be a hand-simulation error (likely counting only the exact 2-word window).

Per my constraints I did not edit the verbatim test nor deviate from the verbatim Step 3 code
(beyond sanctioned amendments). Options for ruling:
1. Change expectation to `5` (true parity), or
2. Change fixture tokens to avoid decoy windows, e.g. expect 5 on current input,
   or drop trailing `"might","bee"` and assert accordingly.

## CONCERN 2 (latent, will bite later golden tests): upstream counts EXACT terms by distinct type, not frequency

Upstream `_analyze_document` iterates `for token in token_counter:` / `for ngram in ngram_counter:`
(keys of the Counter) and does `+= 1` for exact hits; only wildcards do
`+= occurrences`. Running upstream on the brief's own inputs:

| Brief test | Brief expects | Upstream Python | My impl (full-frequency) |
|---|---|---|---|
| B: `might be*` multi-wildcard | 1 | **5** | 5 |
| A: `not now not never`, exact single Neg | 3 | **2** | 3 |
| C: `some kind of cake kind of`, exact multi `"kind of"` ×2 | 2 | **1** | 1 |

The brief's global prose ("a token/ngram contributes its FULL frequency") and tests A/C
encode frequency-based exact counting, which conflicts with the real Python. I kept
full-frequency because the binding constraint explicitly defines parity as "(token/ngram full
frequency to each matched category)" and the verbatim Step 3 code implements it; it also passes
the most brief tests (fails only B). But before Task 5 golden tests compare against the real app,
a ruling is needed: either (a) frequency semantics everywhere (current impl; golden tests vs real
app will diverge on repeated exact terms), or (b) true upstream parity (exact = distinct types;
would flip tests A and C).

Minor related notes for later tasks: upstream `word_perc = count / n_tokens` (proportion, not %),
and detected words are sets (deduped) — both already match our design.

## Verification checklist

- [x] RED watched before implementation (correct failure reason)
- [x] GREEN: 44/45 expectations pass; single failure root-caused to contradictory test
      expectation, evidenced against authoritative source
- [x] Amendments A1/A2 applied and cross-checked in upstream code
- [x] Existing suites unaffected (dictionary, tokenizer all green)
- [x] Committed per Step 5 (`122009e`); no secrets/artifacts committed

---

# Fix round (2026-08-24) — adopt upstream asymmetric counting semantics

**Status: DONE**
**Commit:** see fix commit below (branch `feat-wowordcount`)
**Files:** `R/counter.R`, `tests/testthat/test-counter.R`

## Rulings applied

- **R6 (resolves CONCERN 2):** upstream semantics are binding — EXACT terms count distinct
  types (+1 each); WILDCARD prefixes count full frequency (+f). Both mechanisms combine when a
  type is listed both ways.
- **R7 (resolves CONCERN 1):** the 5-count reading for `might be*` on
  `c("it","might","be","rain","might","bee")` is correct.

## Code change (`R/counter.R`)

`wc_count_document` now computes exact and wildcard contributions separately instead of adding
`f` to every hit:

- Single tokens: `unique(exact_single_lookup[[token]])` → `counts[cat] + 1L`;
  `unique(wc_trie_match(single_trie, token))` → `counts[cat] + f`.
- N-grams: same split via `exact_multi_lookup` / `multi_trie`.
- A type hitting a category through both mechanisms adds BOTH +1 and +f (upstream behavior).
- `detected` collection unchanged in spirit: one entry per contributing type per category
  (union of exact+wildcard categories), so no duplicate detection entries.
- File top comment now documents the asymmetry and cites `app/text_analysis.py`.

## Test changes (`tests/testthat/test-counter.R`)

1. "simple exact counting with frequencies" → renamed "simple exact counting counts distinct
   types"; `not/now/not/never` expects Neg == 2 (n_tokens 4, n_types 3 unchanged).
2. "multi-word exact match via ngrams": `"kind of"` ×2 → C == 1 (distinct type).
3. "term shared across categories counted in both": `yes yes` → A == 1, B == 1.
4. "multi-word wildcard prefix matches": expected M == 5 (per R7).
5. Wildcard-frequency tests unchanged (can/cant/cannot/dog → 3; canned ×2 → 2).
6. New block "exact and wildcard contributions combine like upstream": dict
   `dog\tX`, `do*\tX`; doc `c("dog","dog","dot")` → X == 4. Hand-checked: exact dog = +1
   (distinct type), wildcard = dog(2) + dot(1) = 3, combined 4 — matches upstream rule where
   `for token in token_counter:` adds 1 for the exact entry and the wildcard branch adds
   occurrences.

## Command and output

```
& "C:\Program Files\R\R-4.5.1\bin\x64\Rscript.exe" -e "testthat::test_local('.')"

✔ |         16 | counter
✔ |         16 | dictionary
✔ |         14 | tokenizer

[ FAIL 0 | WARN 0 | SKIP 0 | PASS 46 ]
```

Pre-fix baseline re-confirmed: FAIL 1 (`multi-word wildcard prefix matches`, actual 5 vs
expected 1) — i.e., only the stale expectation failed before this round; tokenizer/dictionary
were already green and remain green.
