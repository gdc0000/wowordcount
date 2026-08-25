GLOBAL CONSTRAINTS
=========

- Target user: psychology researcher on an 8 GB RAM laptop. Base R only; no new heavy dependencies; no Python runtime dependency at analysis time.
- Numeric parity with the Python original is mandatory: same tokenizer regex behavior, same n-gram rule, same counting semantics. Golden tests enforce it.
- Dictionary paste format (TSV): header row starting with `DicTerm`, one column per category, cell value `X` (case-insensitive, trimmed) marks membership, trailing `*` marks a prefix wildcard, terms may contain internal spaces (multi-word).
- Max n-gram size = 5. N-grams are generated ONLY for lengths actually demanded by the dictionary (`required_ngram_lengths`), never eagerly.
- Output columns per category: `{Cat}_word_count` (integer), `{Cat}_word_perc` (proportion of n_tokens, 0 when n_tokens == 0). Global: `n_tokens`, `n_types`. Optional per category: `{Cat}_detected_words` (comma-space joined string; option default OFF).
- Column name sanitization identical to the original `enhance.py`: replace spaces with `_`, strip every character not in `[A-Za-z0-9_]`.
- UI language: English (module published internationally; Italian support can be added later via jamovi i18n).
- Every task ends with `git add <files>` + commit. Never commit secrets or build artifacts (`build*/`, `*.jmo` are gitignored).


TASK TEXT
=========
### Task 2: tokenizer.R — cleaning, tokens, n-grams (TDD)

Parity target: `_tokenize_document` and `_generate_ngrams` from `app/text_analysis.py` in the WordCount repo.

**Files:**
- Create: `R/tokenizer.R`
- Test: `tests/testthat.R`, `tests/testthat/test-tokenizer.R`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `wc_clean_document(doc) -> character(1)`: NA→"", lowercased, chars not matching `[\w\s']` replaced by space (PCRE, UCP mode so accented letters survive, mirroring Python's Unicode `\w`)
  - `wc_tokenize(doc) -> character()`: cleaned doc split on whitespace runs, zero-length tokens dropped
  - `wc_generate_ngrams(tokens, lengths) -> character()`: space-joined windows for each requested length, order irrelevant (consumers treat them as multiset); returns empty vector when `length(tokens) < max(lengths)`

- [ ] **Step 1: Write failing tests**

`tests/testthat.R`:
```r
library(testthat)
library(wowordcount)

test_check("wowordcount")
```

`tests/testthat/test-tokenizer.R`:
```r
test_that("cleaning handles NA, case, punctuation", {
  expect_equal(wc_clean_document(NA_character_), "")
  expect_equal(wc_clean_document("Hello, World!"), "hello  world ")
})

test_that("apostrophes and underscores survive", {
  expect_equal(wc_clean_document("L'amico_non_è"), "l'amico_non_è")
})

test_that("accented characters survive cleaning (Italian corpus)", {
  toks <- wc_tokenize("Perché città è-andata")
  expect_setequal(toks, c("perché", "città", "è", "andata"))
})

test_that("tokenize drops empties and splits on any whitespace", {
  expect_setequal(wc_tokenize("  a\t b\nc "), c("a", "b", "c"))
  expect_length(wc_tokenize(""), 0)
})

test_that("n-grams cover requested lengths only", {
  toks <- c("the", "quick", "brown", "fox")
  ng <- wc_generate_ngrams(toks, c(2, 4))
  expect_true("quick brown" %in% ng)
  expect_true("the quick brown fox" %in% ng)
  expect_false("brown fox" %in% ng)
  expect_false("the quick" %in% ng[ng == "quick brown"])
})

test_that("n-grams respect max length availability", {
  expect_length(wc_generate_ngrams(c("one"), 2), 0)
  expect_setequal(wc_generate_ngrams(c("a", "b"), 2), "a b")
})
```

- [ ] **Step 2: Run tests, verify failure**

Run: `Rscript -e "testthat::test_local('.')"`
Expected: FAIL — `cannot find function wc_clean_document`.

- [ ] **Step 3: Implement**

`R/tokenizer.R`:
```r
# Cleaning/tokenization parity port of app/text_analysis.py (WordCount).
# Python \w matches Unicode word chars; (*UCP) switches PCRE to Unicode mode
# so accented letters behave identically. Apostrophe preserved like the original.

wc_max_ngram_size <- 5L

wc_clean_document <- function(doc) {
  if (is.na(doc))
    return("")
  doc <- tolower(as.character(doc))
  gsub("(*UCP)[^\\w\\s']", " ", doc, perl = TRUE)
}

wc_tokenize <- function(doc) {
  parts <- strsplit(wc_clean_document(doc), "[[:space:]]+", perl = TRUE)[[1]]
  parts[nzchar(parts)]
}

wc_generate_ngrams <- function(tokens, lengths) {
  lengths <- unique(as.integer(lengths))
  lengths <- lengths[lengths >= 2L]
  n_tokens <- length(tokens)
  out <- character(0)
  for (n in lengths) {
    if (n > n_tokens || n < 2L)
      next
    starts <- 1L:(n_tokens - n + 1L)
    windows <- vapply(
      starts,
      function(s) paste(tokens[s:(s + n - 1L)], collapse = " "),
      character(1)
    )
    out <- c(out, windows)
  }
  out
}
```

Also create `R/wowordcount-package.R` placeholder so the package has at least one non-generated source of truth for roxygen-free builds:
```r
# wowordcount internals; no public API beyond the jamovi analysis.
```

Add `Collate` is not needed (alphabetical load order suffices: counter < dictionary < pipeline < tokenizer — see note in Task 4; we avoid inter-file top-level dependencies).

- [ ] **Step 4: Run tests, verify pass**

Run: `Rscript -e "testthat::test_local('.')"`
Expected: all PASS. If the accented test fails because of locale, force UTF-8 handling inside `wc_clean_document` with `enc2utf8()` before `tolower` and re-run.

- [ ] **Step 5: Commit**

```bash
git add R/tokenizer.R R/wowordcount-package.R tests/
git commit -m "feat: tokenizer with unicode-safe cleaning and selective n-grams"
```

---