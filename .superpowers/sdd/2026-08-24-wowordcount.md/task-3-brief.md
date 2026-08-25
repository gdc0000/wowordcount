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