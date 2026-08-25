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
### Task 4: counter.R — config preparation, tries, per-document counting (TDD)

Parity target: `_prepare_analysis_config`, `_build_prefix_trie`, `_match_prefix_categories`, `_analyze_document` from `app/text_analysis.py`.

**Files:**
- Create: `R/counter.R`
- Test: `tests/testthat/test-counter.R`

**Interfaces:**
- Consumes: `wcdict` object from Task 3 (`wc_parse_dictionary`)
- Produces:
  - `wc_prepare_config(dict) -> list('cfg')` with elements:
    - `categories`: character vector
    - `exact_single_lookup`: named list `term -> character vector of categories`
    - `exact_multi_lookup`: named list `ngram -> categories`
    - `single_trie`, `multi_trie`: nested `environment` tries mapping prefix chars to nodes; terminal nodes carry attribute/list slot `cats`
    - `required_lengths`: sorted unique integer vector of n-gram lengths needed by multi-word terms/prefixes (each multi-word term of k words needs length k; each multi-word prefix of k words needs lengths max(k,2):5)
  - `wc_count_document(tokens, cfg, collect_detected = FALSE) -> list`:
    - `n_tokens` int, `n_types` int
    - `counts`: numeric named vector over `cfg$categories`
    - `detected`: named list of character vectors (only meaningful when `collect_detected = TRUE`)

Counting semantics (must match Python exactly): a token/ngram contributes its FULL frequency to each matched category; a term can belong to multiple categories; wildcard matches are prefix matches; multi-word matching happens on space-joined n-gram windows.

- [ ] **Step 1: Write failing tests**

`tests/testthat/test-counter.R`:
```r
make_dict <- function(...) {
  wc_parse_dictionary(paste(..., sep = "\n"))
}

test_that("required lengths derived from dictionary", {
  d <- make_dict(
    "DicTerm\tA\tB",
    "kind of\tX\t",     # exact 2-gram
    "not\tX\t",
    "can*\t\tX",        # single prefix: no ngram need
    "might be*\t\tX"    # 2-word prefix -> lengths 2..5
  )
  cfg <- wc_prepare_config(d)
  expect_setequal(cfg$required_lengths, c(2L, 3L, 4L, 5L))
})

test_that("simple exact counting with frequencies", {
  d <- make_dict("DicTerm\tNeg", "not\tX", "never\tX")
  cfg <- wc_prepare_config(d)
  res <- wc_count_document(c("not", "now", "not", "never"), cfg)
  expect_equal(res$n_tokens, 4)
  expect_equal(res$n_types, 3)
  expect_equal(unname(res$counts["Neg"]), 3)
})

test_that("wildcard prefix counts full frequency", {
  d <- make_dict("DicTerm\tM", "can*\tX")
  cfg <- wc_prepare_config(d)
  res <- wc_count_document(c("can", "cant", "cannot", "dog"), cfg)
  expect_equal(unname(res$counts["M"]), 3)
  res2 <- wc_count_document(c("canned", "canned"), cfg)
  expect_equal(unname(res2$counts["M"]), 2)
})

test_that("multi-word exact match via ngrams", {
  d <- make_dict("DicTerm\tC", "kind of\tX")
  cfg <- wc_prepare_config(d)
  res <- wc_count_document(
    c("some", "kind", "of", "cake", "kind", "of"), cfg)
  expect_equal(unname(res$counts["C"]), 2)
})

test_that("multi-word wildcard prefix matches", {
  d <- make_dict("DicTerm\tM", "might be*\tX")
  cfg <- wc_prepare_config(d)
  res <- wc_count_document(
    c("it", "might", "be", "rain", "might", "bee"), cfg)
  expect_equal(unname(res$counts["M"]), 1)
})

test_that("term shared across categories counted in both", {
  d <- make_dict("DicTerm\tA\tB", "yes\tX\tX")
  cfg <- wc_prepare_config(d)
  res <- wc_count_document(c("yes", "yes"), cfg)
  expect_equal(unname(res$counts["A"]), 2)
  expect_equal(unname(res$counts["B"]), 2)
})

test_that("empty document yields zeros", {
  d <- make_dict("DicTerm\tA", "word\tX")
  cfg <- wc_prepare_config(d)
  res <- wc_count_document(character(0), cfg)
  expect_equal(res$n_tokens, 0)
  expect_equal(unname(res$counts["A"]), 0)
})

test_that("detected words collected on demand", {
  d <- make_dict("DicTerm\tM", "can*\tX", "dog\tX")
  cfg <- wc_prepare_config(d)
  res <- wc_count_document(c("can", "dog", "dog"), cfg,
                           collect_detected = TRUE)
  expect_setequal(res$detected$M, c("can", "dog"))
})
```

- [ ] **Step 2: Run tests, verify failure**

Run: `Rscript -e "testthat::test_local('.')"`
Expected: FAIL — `cannot find function wc_prepare_config`.

- [ ] **Step 3: Implement**

`R/counter.R`:
```r
wc_trie_new <- function() new.env(parent = emptyenv())

wc_trie_add <- function(trie, prefix, cats) {
  node <- trie
  chars <- strsplit(prefix, "", fixed = TRUE)[[1]]
  for (ch in chars) {
    nxt <- node[[ch]]
    if (is.null(nxt)) {
      nxt <- wc_trie_new()
      assign(ch, nxt, envir = node)
    }
    node <- nxt
  }
  existing <- node$.terminal_
  node$.terminal_ <- if (is.null(existing)) cats else c(existing, cats)
  invisible(NULL)
}

wc_trie_match <- function(trie, term) {
  if (isEmptyTrie(trie))
    return(character(0))
  node <- trie
  matched <- character(0)
  chars <- strsplit(term, "", fixed = TRUE)[[1]]
  for (ch in chars) {
    nxt <- node[[ch]]
    if (is.null(nxt))
      break
    node <- nxt
    if (!is.null(node$.terminal_))
      matched <- c(matched, node$.terminal_)
  }
  matched
}

isEmptyTrie <- function(trie) length(ls(trie)) == 0L

wc_prepare_config <- function(dict) {
  categories <- dict$categories
  es_lookup <- list()
  em_lookup <- list()
  s_trie <- wc_trie_new()
  m_trie <- wc_trie_new()
  req_len <- integer(0)

  add_to_named_list <- function(lst, key, val) {
    lst[[key]] <- if (is.null(lst[[key]])) val else c(lst[[key]], val)
    lst
  }

  for (cat in categories) {
    for (term in dict$exact_single[[cat]])
      es_lookup <- add_to_named_list(es_lookup, term, cat)
    for (prefix in dict$wildcard_single[[cat]])
      wc_trie_add(s_trie, prefix, cat)
    for (term in dict$exact_multi[[cat]]) {
      em_lookup <- add_to_named_list(em_lookup, term, cat)
      req_len <- c(req_len, length(strsplit(term, " ", fixed = TRUE)[[1]]))
    }
    for (prefix in dict$wildcard_multi[[cat]]) {
      wc_trie_add(m_trie, prefix, cat)
      k <- length(strsplit(prefix, " ", fixed = TRUE)[[1]])
      req_len <- c(req_len, seq(max(k, 2L), wc_max_ngram_size))
    }
  }

  list(
    categories = categories,
    exact_single_lookup = es_lookup,
    exact_multi_lookup = em_lookup,
    single_trie = s_trie,
    multi_trie = m_trie,
    required_lengths = sort(unique(as.integer(req_len)))
  )
}

wc_count_document <- function(tokens, cfg, collect_detected = FALSE) {
  categories <- cfg$categories
  counts <- stats::setNames(rep(0, length(categories)), categories)
  detected <- stats::setNames(
    vector("list", length(categories)), categories)

  n_tokens <- length(tokens)
  n_types <- length(unique(tokens))

  if (n_tokens > 0L) {
    freq <- table(tokens)

    for (token in names(freq)) {
      f <- as.integer(freq[[token]])
      hits <- character(0)
      if (!is.null(cfg$exact_single_lookup[[token]]))
        hits <- c(hits, cfg$exact_single_lookup[[token]])
      hits <- c(hits, wc_trie_match(cfg$single_trie, token))
      hits <- unique(hits)
      for (cat in hits) {
        counts[cat] <- counts[cat] + f
        if (collect_detected)
          detected[[cat]] <- c(detected[[cat]], token)
      }
    }

    if (length(cfg$required_lengths) > 0L && n_tokens >= 2L) {
      ngrams <- wc_generate_ngrams(tokens, cfg$required_lengths)
      ng_freq <- table(ngrams)
      for (ng in names(ng_freq)) {
        f <- as.integer(ng_freq[[ng]])
        hits <- character(0)
        if (!is.null(cfg$exact_multi_lookup[[ng]]))
          hits <- c(hits, cfg$exact_multi_lookup[[ng]])
        hits <- c(hits, wc_trie_match(cfg$multi_trie, ng))
        hits <- unique(hits)
        for (cat in hits) {
          counts[cat] <- counts[cat] + f
          if (collect_detected)
            detected[[cat]] <- c(detected[[cat]], ng)
        }
      }
    }
  }

  list(
    n_tokens = n_tokens,
    n_types = n_types,
    counts = counts,
    detected = detected
  )
}
```

Note: `wc_generate_ngrams` lives in `R/tokenizer.R` (Task 2); R loads files alphabetically within a package (`counter.R` before `tokenizer.R`), which is safe here because calls happen at runtime, not load time. Do not add cross-file top-level calls anywhere in `R/`.

- [ ] **Step 4: Run tests, verify pass**

Run: `Rscript -e "testthat::test_local('.')"`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add R/counter.R tests/testthat/test-counter.R
git commit -m "feat: trie-based counting engine with selective n-grams"
```

---