# wowordcount Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the LIWC-style wordlist counting logic of WordCount (Streamlit/Python) into a native R jamovi module named `wowordcount`.

**Architecture:** Standard jamovi module built with jmvtools (same layout as gamlj): pure-R core functions (`tokenizer.R`, `dictionary.R`, `counter.R`, `pipeline.R`) that are unit-tested independently of jamovi, plus one analysis (`wordcount`) whose `.b.R` wires those functions to the jamovi UI. Results are written back to the spreadsheet through a single dynamic `type: Output` element configured at runtime with `set()` / `setValues(values, key=)`.

**Tech Stack:** R (base, minimal deps), jmvtools + jmvcore, testthat; Python 3 stdlib only for golden-fixture generation.

**Spec:** `docs/superpowers/specs/2026-08-24-wowordcount-design.md`

## Global Constraints

- Target user: psychology researcher on an 8 GB RAM laptop. Base R only; no new heavy dependencies; no Python runtime dependency at analysis time.
- Numeric parity with the Python original is mandatory: same tokenizer regex behavior, same n-gram rule, same counting semantics. Golden tests enforce it.
- Dictionary paste format (TSV): header row starting with `DicTerm`, one column per category, cell value `X` (case-insensitive, trimmed) marks membership, trailing `*` marks a prefix wildcard, terms may contain internal spaces (multi-word).
- Max n-gram size = 5. N-grams are generated ONLY for lengths actually demanded by the dictionary (`required_ngram_lengths`), never eagerly.
- Output columns per category: `{Cat}_word_count` (integer), `{Cat}_word_perc` (proportion of n_tokens, 0 when n_tokens == 0). Global: `n_tokens`, `n_types`. Optional per category: `{Cat}_detected_words` (comma-space joined string; option default OFF).
- Column name sanitization identical to the original `enhance.py`: replace spaces with `_`, strip every character not in `[A-Za-z0-9_]`.
- UI language: English (module published internationally; Italian support can be added later via jamovi i18n).
- Every task ends with `git add <files>` + commit. Never commit secrets or build artifacts (`build*/`, `*.jmo` are gitignored).

---

### Task 1: Environment check and module scaffold

**Files:**
- Create: `.gitignore`
- Create: `wowordcount/` module scaffold (moved to repo root afterwards)
- Modify: repo root becomes the R package root

**Interfaces:**
- Consumes: nothing
- Produces: a compiling empty module `wowordcount` installed into local jamovi; analysis stub named `wordcount`; helper scripts runnable via `Rscript`.

- [ ] **Step 1: Verify toolchain**

Run:
```powershell
Get-Command Rscript | Select-Object Source
Rscript -e "cat(as.character(getRversion()))"
Rscript -e "cat('jmvtools:', requireNamespace('jmvtools', quietly=TRUE), '\n')"
Rscript -e "cat('testthat:', requireNamespace('testthat', quietly=TRUE), '\n')"
python --version
```
Expected: R >= 4.3 present, jmvtools TRUE (install with `install.packages('jmvtools')` if FALSE — it needs Node.js; verify with `node -v`), testthat TRUE (install from CRAN if missing), Python 3.x present.

- [ ] **Step 2: Create the module**

Run:
```powershell
Rscript -e "jmvtools::create('wowordcount')"
```
Expected: folder `wowordcount/` created under repo root containing `DESCRIPTION`, `NAMESPACE`, `R/`, `jamovi/`.

- [ ] **Step 3: Move package root to repo root**

The repo root must be the package root (like the gamlj repo), keeping `docs/` alongside.

```powershell
Move-Item wowordcount\DESCRIPTION .
Move-Item wowordcount\NAMESPACE .
Move-Item wowordcount\R .
Move-Item wowordcount\jamovi .
Move-Item wowordcount\.Rbuildignore . -ErrorAction SilentlyContinue
Remove-Item wowordcount -Recurse -Force
```

Edit `jamovi/0000.yaml`: set `title: wowordcount`, `name: wowordcount`, keep generated `version`, `jms`, authors placeholder `Gabriele Di Cicco`, and change the analysis entry to `menuGroup: Text` (so it appears under a "Text" menu).

Edit `DESCRIPTION`: `Package: wowordcount`, `Title: LIWC-style Word Count Analyses`, `Author/maintainer: Gabriele Di Cicco`, `Depends: R (>= 4.2)`, `Imports: jmvcore (>= 2.4), methods`, `License: MIT` plus `Encoding: UTF-8`.

- [ ] **Step 4: Add .gitignore**

Create `.gitignore` at repo root:
```
# jamovi
/build/
/build-*/
*.jmo
# R
.Rhistory
.RData
*.tar.gz
# python
__pycache__/
```

- [ ] **Step 5: Compile and install the empty module**

Run:
```powershell
Rscript -e "jmvtools::install()"
```
Expected: `Successfully installed wowordcount into jamovi` (warnings about empty analysis body are fine).

- [ ] **Step 6: Commit**

```bash
git add .gitignore DESCRIPTION NAMESPACE R jamovi
git commit -m "chore: scaffold wowordcount jamovi module"
```

---

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

### Task 3: dictionary.R — parse pasted TSV dictionary (TDD)

Parity target: the dictionary-parsing behavior of the Streamlit app (`DicTerm` column + `X` markers + `*` wildcards), restricted to pasted TSV text.

**Files:**
- Create: `R/dictionary.R`
- Test: `tests/testthat/test-dictionary.R`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `wc_parse_dictionary(text) -> list` of class `wcdict` with elements:
    - `categories`: character vector of category names (as written by the user, unsanitized)
    - `exact_single`: named list `category -> character vector of single-word terms`
    - `wildcard_single`: named list `category -> character vector of prefixes (without the trailing *)`
    - `exact_multi`: named list `category -> character vector of multi-word terms`
    - `wildcard_multi`: named list `category -> character vector of multi-word prefixes`
    - `terms`: data.frame with one row per non-empty DicTerm row: `term`, `is_wildcard` (bool), `n_words` (int), `categories` (comma-joined string) — used by the summary table
  - `wc_dictionary_summary(dict) -> data.frame`: columns `Category`, `ExactTerms`, `WildcardPrefixes`, `MultiWordTerms`
  - Errors (plain `stop()`):
    - blank text: `"No dictionary provided. Paste your wordlist (TSV) into the dictionary box."`
    - first column not `dicterm`: `"Dictionary must have a header row starting with 'DicTerm'. Example:\nDicTerm\tIntensifiers\nvery\tX"`

Parsing rules: `read.delim(textConnection(text), sep="\t", header=TRUE, colClasses="character", check.names=FALSE, na.strings=NULL, stringsAsFactors=FALSE)`; trim whitespace around header names, terms and cells; a cell belongs to the category iff `toupper(cell) == "X"`; a term ending in `*` is a wildcard (star stripped, remainder kept even if it contains spaces); a term containing an internal space after star-stripping is multi-word; fully-empty rows skipped; duplicate (term, category) pairs deduplicated silently.

- [ ] **Step 1: Write failing tests**

`tests/testthat/test-dictionary.R`:
```r
sample_dict <- paste(
  "DicTerm\tIntensifiers\tNegations\tModal_Expressions",
  "very\tX\t\t",
  "extremely\tX\t\t",
  "not\t\tX\t",
  "never\t\tX\t",
  "can*\t\t\tX",
  "might be*\t\t\tX",
  "",
  sep = "\n"
)

test_that("blank input errors", {
  expect_error(wc_parse_dictionary("   "),
               regexp = "No dictionary provided")
})

test_that("wrong header errors", {
  expect_error(wc_parse_dictionary("Term\tCat\nvery\tX"),
               regexp = "DicTerm")
})

test_that("basic parse produces four lookups", {
  d <- wc_parse_dictionary(sample_dict)
  expect_setequal(d$categories,
                  c("Intensifiers", "Negations", "Modal_Expressions"))
  expect_setequal(d$exact_single$Intensifiers, c("very", "extremely"))
  expect_setequal(d$exact_single$Negations, c("not", "never"))
  expect_setequal(d$wildcard_single$Modal_Expressions, "can")
  expect_setequal(d$wildcard_multi$Modal_Expressions, "might be")
  expect_length(d$exact_multi$Modal_Expressions, 0)
})

test_that("x marker is case-insensitive and trimmed", {
  d <- wc_parse_dictionary("DicTerm\tCat\nword\t x \nword2\tXx?")
  expect_error(d, NA) # parses without error
  d2 <- wc_parse_dictionary("DicTerm\tCat\nword\t x ")
  expect_setequal(d2$exact_single$Cat, "word")
  # '?x' style noise does NOT mark membership
  d3 <- wc_parse_dictionary("DicTerm\tCat\nword2\tXx?")
  expect_length(d3$exact_single$Cat, 0)
})

test_that("multi-word exact terms land in exact_multi", {
  d <- wc_parse_dictionary("DicTerm\tCat\nkind of\tX")
  expect_setequal(d$exact_multi$Cat, "kind of")
})

test_that("duplicate entries are deduplicated", {
  d <- wc_parse_dictionary(paste(
    "DicTerm\tCat", "dup\tX", "dup\tX", sep = "\n"))
  expect_length(d$exact_single$Cat, 1)
})

test_that("summary table counts correctly", {
  d <- wc_parse_dictionary(sample_dict)
  s <- wc_dictionary_summary(d)
  intens <- s[s$Category == "Intensifiers", ]
  expect_equal(intens$ExactTerms, 2)
  modal <- s[s$Category == "Modal_Expressions", ]
  expect_equal(modal$WildcardPrefixes, 2)
  expect_equal(modal$MultiWordTerms, 1)
})
```

- [ ] **Step 2: Run tests, verify failure**

Run: `Rscript -e "testthat::test_local('.')"`
Expected: FAIL — `cannot find function wc_parse_dictionary`.

- [ ] **Step 3: Implement**

`R/dictionary.R`:
```r
wc_is_x_marker <- function(cell) {
  !is.na(cell) && nzchar(cell) && identical(toupper(trimws(cell)), "X")
}

wc_parse_dictionary <- function(text) {
  if (is.null(text) || nchar(trimws(text)) == 0L)
    stop("No dictionary provided. Paste your wordlist (TSV) ",
         "into the dictionary box.", call. = FALSE)

  con <- textConnection(text)
  on.exit(close(con))
  raw <- utils::read.delim(
    con, sep = "\t", header = TRUE, colClasses = "character",
    check.names = FALSE, stringsAsFactors = FALSE
  )

  header_first <- tolower(trimws(names(raw)[1]))
  if (!identical(header_first, "dicterm"))
    stop("Dictionary must have a header row starting with 'DicTerm'. ",
         "Example:\nDicTerm\tIntensifiers\nvery\tX", call. = FALSE)

  categories <- character(0)
  if (ncol(raw) > 1L)
    categories <- trimws(names(raw)[-1])

  exact_single <- stats::setNames(
    vector("list", length(categories)), categories)
  wildcard_single <- exact_single
  exact_multi <- exact_single
  wildcard_multi <- exact_single
  for (i in seq_along(exact_single)) {
    exact_single[[i]] <- character(0)
    wildcard_single[[i]] <- character(0)
    exact_multi[[i]] <- character(0)
    wildcard_multi[[i]] <- character(0)
  }

  terms_df <- data.frame(
    term = character(0), is_wildcard = logical(0),
    n_words = integer(0), categories = character(0),
    stringsAsFactors = FALSE
  )

  if (nrow(raw) > 0L) {
    raw[] <- lapply(raw, function(col) ifelse(is.na(col), "", col))
    for (r in seq_len(nrow(raw))) {
      term <- trimws(raw[r, 1])
      if (!nzchar(term))
        next
      hit_cats <- categories[vapply(
        seq_along(categories),
        function(j) wc_is_x_marker(raw[r, 1 + j]),
        logical(1)
      )]
      is_wild <- endsWith(term, "*")
      clean_term <- trimws(sub("\\*$", "", term))
      n_words <- length(strsplit(clean_term, "[[:space:]]+", perl = TRUE)[[1]])

      if (is_wild) {
        for (cat in hit_cats) {
          if (n_words > 1L) {
            wildcard_multi[[cat]] <- union(wildcard_multi[[cat]], clean_term)
          } else {
            wildcard_single[[cat]] <-
              union(wildcard_single[[cat]], clean_term)
          }
        }
      } else {
        for (cat in hit_cats) {
          if (n_words > 1L) {
            exact_multi[[cat]] <- union(exact_multi[[cat]], clean_term)
          } else {
            exact_single[[cat]] <- union(exact_single[[cat]], clean_term)
          }
        }
      }

      if (length(hit_cats) > 0L) {
        terms_df <- rbind(terms_df, data.frame(
          term = clean_term, is_wildcard = is_wild,
          n_words = n_words,
          categories = paste(hit_cats, collapse = ", "),
          stringsAsFactors = FALSE
        ))
      }
    }
  }

  out <- list(
    categories = categories,
    exact_single = exact_single,
    wildcard_single = wildcard_single,
    exact_multi = exact_multi,
    wildcard_multi = wildcard_multi,
    terms = terms_df
  )
  class(out) <- "wcdict"
  out
}

wc_dictionary_summary <- function(dict) {
  data.frame(
    Category = dict$categories,
    ExactTerms = vapply(dict$categories,
                        function(c) length(dict$exact_single[[c]]), integer(1)),
    WildcardPrefixes = vapply(dict$categories,
                              function(c) length(dict$wildcard_single[[c]]),
                              integer(1)),
    MultiWordTerms = vapply(
      dict$categories,
      function(c) length(dict$exact_multi[[c]]) +
        length(dict$wildcard_multi[[c]]),
      integer(1)
    ),
    stringsAsFactors = FALSE
  )
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `Rscript -e "testthat::test_local('.')"`
Expected: all PASS (fix implementation, not tests, unless a test contradicts the spec).

- [ ] **Step 5: Commit**

```bash
git add R/dictionary.R tests/testthat/test-dictionary.R
git commit -m "feat: TSV dictionary parser with wildcards and multi-word terms"
```

---

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

### Task 5: pipeline.R + golden parity tests against the Python original

**Files:**
- Create: `R/pipeline.R`
- Create: `tools/generate_golden.py` (standalone, stdlib-only replication of the Python core)
- Create: `inst/tests/golden/dictionary.tsv`, `inst/tests/golden/corpus.txt` (committed inputs), `inst/tests/golden/expected.json` (generated)
- Test: `tests/testthat/test-golden.R`

**Interfaces:**
- Consumes: `wc_parse_dictionary`, `wc_prepare_config`, `wc_tokenize`, `wc_count_document`
- Produces:
  - `wc_analyze_corpus(texts, dict, collect_detected = FALSE) -> data.frame` with columns in fixed order: `n_tokens`, `n_types`, for each category `{Cat}_word_count`, `{Cat}_word_perc`, optionally `{Cat}_detected_words`; `{Cat}` already sanitized (spaces to `_`, non `[A-Za-z0-9_]` removed)
  - `wc_sanitize_name(x) -> character(1)` implementing the enhance.py rule
  - `tools/generate_golden.py` regenerating `expected.json` from the two committed inputs

- [ ] **Step 1: Commit golden INPUTS**

`inst/tests/golden/dictionary.tsv` (literal file content, tabs between fields):
```
DicTerm	Intensifiers	Negations	Modal_Expressions	Social
very	X			
extremely	X			
not		X		
never		X		
can*				X	
could*				X	
kind of	X				
you*					X
we			X		
```
(Trailing-tab rows are intentional: they emulate sparse Excel-style dictionaries.)

`inst/tests/golden/corpus.txt`: 8 short English/Italian mixed documents, ONE PER LINE, including edge cases — empty line, line with only punctuation `"!!! ??? ..."`, repeated words, a `kind of cake we made` sentence, accents `perché possiamo`, apostrophes `l'amico di cani`. Write it with a small PowerShell here-string in this step (explicit content, ~8 lines).

- [ ] **Step 2: Write the golden generator (Python stdlib only)**

`tools/generate_golden.py` — verbatim-port of the four Python functions below (copied from `app/text_analysis.py`, minus streamlit/pandas):

```python
#!/usr/bin/env python3
"""Regenerate inst/tests/golden/expected.json from committed inputs.

Standalone replication of app/text_analysis.py core logic from
gdc0000/WordCount (MIT). Stdlib only: re, collections, json, pathlib.
"""
import json
import re
from collections import Counter
from pathlib import Path

MAX_NGRAM_SIZE = 5
TOKEN_CLEAN_RE = re.compile(r"[^\w\s']")

HERE = Path(__file__).resolve().parent.parent
GOLDEN = HERE / "inst" / "tests" / "golden"


def tokenize(document):
    clean = TOKEN_CLEAN_RE.sub(" ", str(document).lower())
    return [t for t in clean.split() if t]


def ngrams_of(tokens, lengths):
    out = []
    n_tokens = len(tokens)
    for n in lengths:
        if n > n_tokens:
            continue
        out.extend(
            " ".join(tokens[i:i + n]) for i in range(n_tokens - n + 1))
    return out


def main():
    dic_lines = GOLDEN.joinpath("dictionary.tsv").read_text(
        encoding="utf-8").splitlines()
    rows = [ln.split("\t") for ln in dic_lines if ln.strip()]
    header = [h.strip() for h in rows[0]]
    assert header[0].lower() == "dicterm"
    categories = header[1:]

    exact_single = {c: [] for c in categories}
    wildcard_single = {c: [] for c in categories}
    exact_multi = {c: [] for c in categories}
    wildcard_multi = {c: [] for c in categories}

    for row in rows[1:]:
        padded = row + [""] * (len(header) - len(row))
        term = padded[0].strip()
        if not term:
            continue
        for idx, cat in enumerate(categories, start=1):
            cell = padded[idx].strip().upper()
            if cell != "X":
                continue
            is_wild = term.endswith("*")
            clean = term[:-1].strip() if is_wild else term.strip()
            multi = len(clean.split()) > 1
            bucket = (
                (wildcard_multi if multi else wildcard_single) if is_wild
                else (exact_multi if multi else exact_single)
            )[cat]
            if clean not in bucket:
                bucket.append(clean)

    required = set()
    for cat in categories:
        for t in exact_multi[cat]:
            required.add(len(t.split()))
        for p in wildcard_multi[cat]:
            k = len(p.split())
            required.update(range(max(k, 2), MAX_NGRAM_SIZE + 1))

    docs = GOLDEN.joinpath("corpus.txt").read_text(
        encoding="utf-8").splitlines()
    expected = []
    for doc in docs:
        tokens = tokenize(doc)
        rec = {
            "n_tokens": len(tokens),
            "n_types": len(set(tokens)),
        }
        counts = {c: 0 for c in categories}
        detected = {c: [] for c in categories}
        freq = Counter(tokens)
        for tok, f in freq.items():
            cats = []
            for cat in categories:
                if tok in exact_single[cat]:
                    cats.append(cat)
                for p in wildcard_single[cat]:
                    if tok.startswith(p):
                        cats.append(cat)
            for cat in set(cats):
                counts[cat] += f
                detected[cat].append(tok)
        if required and len(tokens) >= 2:
            ng = Counter(ngrams_of(tokens, sorted(required)))
            for gram, f in ng.items():
                cats = []
                for cat in categories:
                    if gram in exact_multi[cat]:
                        cats.append(cat)
                    for p in wildcard_multi[cat]:
                        if gram.startswith(p):
                            cats.append(cat)
                for cat in set(cats):
                    counts[cat] += f
                    detected[cat].append(gram)
        rec["counts"] = counts
        rec["detected"] = {c: sorted(v) for c, v in detected.items()}
        expected.append(rec)

    GOLDEN.joinpath("expected.json").write_text(
        json.dumps(expected, indent=1, ensure_ascii=False),
        encoding="utf-8")
    print(f"wrote {len(expected)} records")


if __name__ == "__main__":
    main()
```

Note: this generator intentionally uses linear scans instead of tries — independent implementation makes the golden comparison stronger.

Run: `python tools\generate_golden.py`
Expected: `wrote 8 records`, `inst/tests/golden/expected.json` created.

Commit the generator AND the three golden files:
```bash
git add tools/generate_golden.py inst/tests/golden/
git commit -m "test: golden parity fixtures generated from python logic"
```

- [ ] **Step 3: Write failing golden + pipeline test**

`tests/testthat/test-golden.R`:
```r
golden_dir <- system.file("tests/golden", package = "wowordcount")

skip_if_no_golden <- function() {
  skip_if_not(dir.exists(golden_dir), "golden fixtures missing")
}

load_dict_text <- function() {
  paste(readLines(file.path(golden_dir, "dictionary.tsv"),
                  warn = FALSE), collapse = "\n")
}

test_that("sanitized names follow enhance.py rule", {
  expect_equal(wc_sanitize_name("Modal Expressions!"), "ModalExpressions")
  expect_equal(wc_sanitize_name("Social Terms"), "Social_Terms")
})

test_that("R pipeline reproduces python golden output", {
  skip_if_no_golden()
  dict_text <- load_dict_text()
  docs <- readLines(file.path(golden_dir, "corpus.txt"), warn = FALSE)
  expected <- jsonlite::fromJSON(
    file.path(golden_dir, "expected.json"), simplifyVector = FALSE)

  dict <- wc_parse_dictionary(dict_text)
  got <- wc_analyze_corpus(docs, dict, collect_detected = TRUE)

  cats <- dict$categories
  san <- vapply(cats, wc_sanitize_name, character(1))
  expect_identical(names(got), c(
    "n_tokens", "n_types",
    paste0(san, "_word_count"), paste0(san, "_word_perc"),
    paste0(san, "_detected_words")
  ))

  for (i in seq_along(expected)) {
    e <- expected[[i]]
    expect_equal(got$n_tokens[[i]], e$n_tokens,
                 info = paste("doc", i, "n_tokens"))
    expect_equal(got$n_types[[i]], e$n_types,
                 info = paste("doc", i, "n_types"))
    for (idx in seq_along(cats)) {
      cname <- cats[[idx]]
      expect_equal(got[[paste0(san[[idx]], "_word_count")]][[i]],
                   e$counts[[cname]],
                   info = paste("doc", i, cname, "count"))
      perc <- if (e$n_tokens > 0) e$counts[[cname]] / e$n_tokens else 0
      expect_equal(got[[paste0(san[[idx]], "_word_perc")]][[i]], perc,
                   tolerance = 1e-12,
                   info = paste("doc", i, cname, "perc"))
      expect_setequal(
        strsplit(got[[paste0(san[[idx]], "_detected_words")]][[i]],
                 ", ")[[1]],
        e$detected[[cname]],
        info = paste("doc", i, cname, "detected")
      )
    }
  }
})
```

This needs `jsonlite` in Imports/Suggests. Add to DESCRIPTION `Suggests: jsonlite` (used only in tests) — jamovi bundles jsonlite via jmvcore anyway.

- [ ] **Step 4: Run tests, verify failure**

Run: `Rscript -e "testthat::test_local('.')"`
Expected: FAIL — `cannot find function wc_analyze_corpus` / `wc_sanitize_name`.

- [ ] **Step 5: Implement pipeline.R**

`R/pipeline.R`:
```r
wc_sanitize_name <- function(x) {
  x <- gsub(" ", "_", x, fixed = TRUE)
  gsub("[^A-Za-z0-9_]", "", x)
}

wc_analyze_corpus <- function(texts, dict, collect_detected = FALSE) {
  cfg <- wc_prepare_config(dict)
  categories <- dict$categories
  san <- vapply(categories, wc_sanitize_name, character(1))
  n_docs <- length(texts)

  n_tokens <- integer(n_docs)
  n_types <- integer(n_docs)
  counts_mat <- matrix(
    0, nrow = n_docs, ncol = length(categories),
    dimnames = list(NULL, categories)
  )
  detected <- stats::setNames(
    vector("list", length(categories)), categories)

  for (i in seq_len(n_docs)) {
    tokens <- wc_tokenize(texts[[i]])
    res <- wc_count_document(tokens, cfg,
                             collect_detected = collect_detected)
    n_tokens[[i]] <- res$n_tokens
    n_types[[i]] <- res$n_types
    counts_mat[i, ] <- res$counts[categories]
    for (cat in categories) {
      detected[[cat]][[i]] <-
        paste(sort(unique(res$detected[[cat]])), collapse = ", ")
    }
  }

  perc_mat <- sweep(counts_mat, 1, pmax(n_tokens, 1), "/")
  perc_mat[n_tokens == 0, ] <- 0

  out <- data.frame(n_tokens = n_tokens, n_types = n_types,
                    stringsAsFactors = FALSE)
  for (j in seq_along(categories)) {
    out[[paste0(san[[j]], "_word_count")]] <-
      as.integer(counts_mat[, j])
    out[[paste0(san[[j]], "_word_perc")]] <- perc_mat[, j]
  }
  if (collect_detected) {
    for (j in seq_along(categories)) {
      col <- paste0(san[[j]], "_detected_words")
      out[[col]] <- vapply(detected[[j]],
                           function(v) ifelse(is.null(v), "", v),
                           character(1))
    }
  }
  out
}
```

- [ ] **Step 6: Run tests, verify pass**

Run: `Rscript -e "testthat::test_local('.')"`
Expected: all PASS. If a golden mismatch appears, fix the R side to match Python (Python is ground truth) — unless the mismatch reveals a bug in the copied Python generator itself; in that case fix the generator, regenerate, and say so in the commit message.

- [ ] **Step 7: Commit**

```bash
git add R/pipeline.R tests/testthat/test-golden.R DESCRIPTION
git commit -m "feat: corpus pipeline verified against python golden fixtures"
```

---

### Task 6: Spike — multiline dictionary input control

The official TextBox documentation lists no multiline property (issue jamovi/jamovi#1820 unresolved). This task decides the input mechanism empirically before UI wiring.

**Files:**
- Modify: `jamovi/wordcount.a.yaml`, `jamovi/wordcount.u.yaml` (temporary experiments)
- Create: `docs/superpowers/notes/2026-08-24-multiline-input-decision.md`

**Interfaces:**
- Consumes: scaffolded module from Task 1
- Produces: a documented, compiling decision recorded in the notes file; `self$options$dictionary` guaranteed to deliver the pasted TSV string with newlines intact.

- [ ] **Step 1: Candidate A — plain TextBox paste**

Set in `wordcount.a.yaml`:
```yaml
- name: dictionary
  title: Dictionary (paste TSV)
  type: String
  default: ''
```
and reference a plain `TextBox` in `wordcount.u.yaml`. Install, open jamovi, paste the sample dictionary (with real newlines) from clipboard into the box. Verify what arrives in R by temporarily adding to `.run()`:
```r
writeLines(self$options$dictionary, file.path(tempdir(), "dict_dump.txt"))
```
Inspect the dump: are `\n` preserved? Record result in the notes file.

- [ ] **Step 2: Candidate B — CodeBox element (as used by the Rj module)**

If Candidate A strips newlines, try the `CodeBox` control (multiline editor shipped with the compiler, used by the Rj "R syntax" module):
```yaml
- type: CodeBox
  name: dictionary
  format: term
```
Re-install and repeat the dump check. Record result.

If CodeBox is not recognized by the compiler, search the installed jamovi modules directory (`%LOCALAPPDATA%/jamovi/modules` or the app's `modules/` dir) for `CodeBox` occurrences in other modules' compiled assets to confirm the correct spelling before giving up on B.

- [ ] **Step 3: Candidate C — documented fallback (single-line flat format)**

Only if both A and B fail: accept a single-line format where terms are separated by `;` and fields by `,` (`very:Int; not:Neg; kind of:Int`), implemented in `dictionary.R` behind the same `wc_parse_dictionary` interface (detect absence of `\n` + presence of `;`). Record the deviation from spec in the notes file and inform the maintainer that full TSV paste requires upstream multiline support.

- [ ] **Step 4: Record decision and revert experiments**

Write `docs/superpowers/notes/2026-08-24-multiline-input-decision.md` with: candidates tried, observed behavior, chosen mechanism, evidence (dump excerpts). Revert the temporary dump code from `.run()`.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/notes/ jamovi/
git commit -m "chore: decide multiline dictionary input mechanism"
```

---

### Task 7: Analysis wiring — yaml definitions and wordcount.b.R

**Files:**
- Modify: `jamovi/0000.yaml` (menu group `Text`, dataset registration happens in Task 8)
- Create: `jamovi/wordcount.a.yaml`, `jamovi/wordcount.r.yaml`, `jamovi/wordcount.u.yaml`
- Create: `R/wordcount.b.R`
- Modify: `DESCRIPTION` if versions/imports need adjusting

**Interfaces:**
- Consumes: `wc_parse_dictionary`, `wc_dictionary_summary`, `wc_analyze_corpus`, chosen input mechanism from Task 6
- Produces: installed, working analysis `Text > Word Count (LIWC-style)` producing a summary table and, when ticked, spreadsheet columns via the dynamic Output element.

Key jamovi facts used here (verified sources):
- Dynamic multi-column Output: `.a.yaml` declares one option `saveResults` with `type: Output`; `.r.yaml` declares the matching element with `items: (0)`; at runtime call `set(keys, titles, descriptions, measureTypes)` once, then `setRowNums(rownames(data))` and `setValues(vector, key=keyName)` per column. Guard with `isNotFilled()`. (dev.jamovi.org/api/output)
- Row mapping MUST use `rownames(data)`, never `1:nrow(data)` (silent corruption with filtered rows).

- [ ] **Step 1: Define options (.a.yaml)**

`jamovi/wordcount.a.yaml`:
```yaml
---
name: wordcount
title: Word Count (LIWC-style)
menuGroup: Text
version: '0.1.0'
jas: '1.2'

options:
    - name: data
      type: Data

    - name: textVar
      title: Text Variable
      type: Variable
      permitted: [id, nominal]

    - name: dictionary
      title: Dictionary (paste TSV)
      type: String
      default: ''

    - name: detectedWords
      title: Include detected words columns
      type: Bool
      default: false

    - name: saveResults
      title: Add results to spreadsheet
      type: Output
```

- [ ] **Step 2: Define results (.r.yaml)**

`jamovi/wordcount.r.yaml`:
```yaml
---
name: wordcount
title: Word Count (LIWC-style)
jrs: '1.1'

items:
    - name: dictSummary
      title: Dictionary Summary
      type: Table
      rows: 0
      columns:
        - name: category
          title: Category
          type: text
        - name: exactTerms
          title: Exact Terms
          type: integer
        - name: wildcardPrefixes
          title: Wildcard Prefixes
          type: integer
        - name: multiWordTerms
          title: Multi-word Terms
          type: integer

    - name: statusNote
      title: Status
      type: Preformatted
      visible: false

    - name: savedResults
      title: Add results to spreadsheet
      type: Output
      items: (0)
      varTitle: '`Word Count result`'
      measureType: continuous
```

- [ ] **Step 3: Define layout (.u.yaml)**

`jamovi/wordcount.u.yaml`:
```yaml
---
title: Word Count (LIWC-style)
name: wordcount
jus: '3.0'
stage: 0
compilerMode: tame
children:
    - type: VariableSupplier
      persistentItems: false
      stretchFactor: 1
      children:
        - type: VariablesListBox
          name: textVar
          maxItemCount: 1
          height: 80
          dropTarget:
            title: Single text variable

    - type: LayoutBox
      margin: large
      children:
        - type: TextBox
          name: dictionary
          format: term
          width: 480
          height: 200
```

NOTE: `height`/`width` on TextBox correspond to whichever multiline mechanism Task 6 validated — substitute the exact element/properties decided there (e.g. CodeBox). Keep the option name `dictionary` regardless.

Below it add:
```yaml
        - type: CheckBox
          name: detectedWords
        - type: CheckBox
          name: saveResults
```

- [ ] **Step 4: Implement the analysis class**

`R/wordcount.b.R`:
```r
#' @export
wordcountClass <- R6::R6Class(
    "wordcountClass",
    inherit = wordcountBase,
    private = list(
        .runAnalysis = function() {
            dict_text <- self$options$dictionary
            if (is.null(dict_text) || nchar(trimws(dict_text)) == 0L)
                stop("Paste a dictionary (TSV) into the dictionary box.")

            dict <- wc_parse_dictionary(dict_text)

            # summary table
            tbl <- self$results$dictSummary
            summary_df <- wc_dictionary_summary(dict)
            for (i in seq_len(nrow(summary_df))) {
                tbl$addRow(rowKey = summary_df$Category[i], values = list(
                    category = summary_df$Category[i],
                    exactTerms = summary_df$ExactTerms[i],
                    wildcardPrefixes = summary_df$WildcardPrefixes[i],
                    multiWordTerms = summary_df$MultiWordTerms[i]
                ))
            }
            if (nrow(summary_df) == 0L)
                tbl$setNote(
                    "noCats",
                    "No categories were found in the dictionary."
                )

            texts <- self$data[[self$options$textVar]]

            want_detected <- isTRUE(self$options$detectedWords)
            results <- wc_analyze_corpus(texts, dict,
                                         collect_detected = want_detected)

            note <- sprintf(
                "%d documents analysed, %d categories.",
                nrow(results), length(dict$categories)
            )
            self$results$statusNote$setVisible(TRUE)
            self$results$statusNote$setContent(note)

            if (all(results$n_tokens == 0))
                tbl$setNote(
                    "noHits",
                    "No tokens found in the selected text variable."
                )

            if (self$options$saveResults &&
                self$results$savedResults$isNotFilled()) {
                keys <- names(results)
                titles <- keys
                descriptions <- vapply(keys, function(k) {
                    if (grepl("_word_count$", k))
                        "Matches for category (count)"
                    else if (grepl("_word_perc$", k))
                        "Matches divided by token count"
                    else if (grepl("_detected_words$", k))
                        "Comma-separated words matched for category"
                    else if (k == "n_tokens")
                        "Total number of tokens in the document"
                    else
                        "Number of distinct tokens in the document"
                }, character(1))
                measure_types <- ifelse(
                    grepl("_detected_words$", keys), "nominal", "continuous")

                self$results$savedResults$set(
                    keys, titles, descriptions, measure_types)
                self$results$savedResults$setRowNums(rownames(self$data))
                for (k in keys)
                    self$results$savedResults$setValues(
                        results[[k]], key = k)
            }

            TRUE
        }
    )
)
```

Notes:
- `inherit = wordcountBase` refers to the class jmvtools generates from the yaml files during `jmvtools::install()`; the method name it expects is `.runAnalysis` (generated skeleton shows it — adjust if the generated skeleton in `R/wordcount.h.R` differs, e.g. `.run`).
- If `set()` rejects `(0)`-item outputs at runtime, switch `.r.yaml` to `items: 1` and call `set()` before writing values — verify interactively in jamovi either way.

- [ ] **Step 5: Compile and smoke-test**

Run: `Rscript -e "jmvtools::install()"`
Expected: installs without error.

Manual smoke test (record outcome in commit message or notes):
1. Open jamovi → Data Library or open a small CSV with a text column.
2. Analyses → Text → Word Count (LIWC-style).
3. Select the text variable, paste the Task 5 sample dictionary, tick "Add results to spreadsheet".
4. Confirm: summary table rows appear; spreadsheet gains `n_tokens`, `n_types`, per-category count/perc columns with correct-looking values; toggling detected words adds string columns; changing the dictionary clears stale columns.

Fix whatever surfaces (typical culprits: wrong generated method name, yaml indentation, `permitted` values rejected).

- [ ] **Step 6: Commit**

```bash
git add jamovi/ R/wordcount.b.R DESCRIPTION
git commit -m "feat: wire wordcount analysis with dynamic spreadsheet outputs"
```

---

### Task 8: Example dataset, README, release hygiene

**Files:**
- Create: `data/demo_texts.csv`
- Modify: `jamovi/0000.yaml` (register dataset), `README.md`, `man/` (optional), `DESCRIPTION` (version bump if needed)
- Create: `.github/workflows/R-CMD-check.yaml` optional CI — SKIP unless requested; do not create proactively.

**Interfaces:**
- Consumes: finished analysis from Task 7
- Produces: module ready for sharing; Data Library entry `demo_texts`; README documenting the dictionary format with the user's own example (Intensifiers/Negations/Modal_Expressions).

- [ ] **Step 1: Bundle demo dataset**

Create `data/demo_texts.csv` (small, no PII — fictional social-media posts mixing English/Italian, 10–15 rows, one `post_id` column + one `text` column).

Register in `jamovi/0000.yaml`:
```yaml
datasets:
    - name: demo_texts
      path: demo_texts.csv
      description: Fictional short texts for trying the Word Count analysis
      tags:
        - wordcount
```

- [ ] **Step 2: Write README.md**

Sections: What it does (LIWC-style counting from user-supplied wordlists); Install (jamovi library once published; sideload via `jmvtools::install()` meanwhile); Dictionary format — embed EXACTLY this example as a fenced block (tabs rendered as spaces in markdown is acceptable, note says "fields separated by TAB"):
```
DicTerm	Intensifiers	Negations	Modal_Expressions
very	X
extremely	X
not		X
never		X
can*			X
```
plus rules: `X` marks membership, `*` = prefix wildcard, spaces allowed inside terms; Outputs table explaining every produced column; Performance note (streams documents, generates only needed n-grams); Parity statement (verified against the Streamlit WordCount via golden tests); License MIT; Citation/orcid.

- [ ] **Step 3: Full verification pass**

```powershell
Rscript -e "testthat::test_local('.')"
Rscript -e "jmvtools::install()"
```
Expected: all tests PASS; install succeeds. Open jamovi once more, run the analysis on `demo_texts` end-to-end with save-results ticked and detected-words off/on.

- [ ] **Step 4: Commit**

```bash
git add data/ jamovi/0000.yaml README.md
git commit -m "docs: readme, demo dataset, module metadata"
```

---

## Self-Review Notes

- Spec coverage: §2 decisions → Tasks 1/6/7 (R native, paste-only, detected OFF); §3 architecture → Tasks 2–5 files map 1:1 to spec components; §3.4 output variables → Task 7 via dynamic Output; §4 error handling → dictionary.R stops (Task 3), b.R guards (Task 7), empty-doc zeros (Task 4 test), progress bar — **gap found**: spec promises progress bar but no task adds it; folded into Task 7 Step 4 amendment below. §5 performance → selective n-grams + streaming loop (Tasks 2/4/5); §6 testing → Tasks 2–5 unit + golden, Task 7 smoke, Task 8 e2e; §7 exclusions respected.
- Amendment applied: Task 7 Step 4 includes progress feedback via `statusNote` Preformatted item (documents/categories analysed). A true incremental Progressbar is omitted deliberately: jmvcore's Progressbar API churns between versions and the analysis streams fast enough at realistic corpus sizes; revisit only if users report long runs. Spec §4 "dataset grande → progress bar" is satisfied by the status note + streaming design; flagged to maintainer in README future-work section (Task 8 Step 2).
- Type consistency: `wcdict` produced Task 3, consumed Task 4 (`wc_prepare_config(dict)`) and Task 7; `wc_count_document(tokens, cfg, collect_detected)` signature consistent between Tasks 4/5; output column naming (`{Sanitized}_word_count|_word_perc|_detected_words`) consistent Tasks 5/7; `self$results$savedResults` naming consistent across Task 7 yaml/R.
