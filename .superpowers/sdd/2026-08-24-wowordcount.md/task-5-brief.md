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