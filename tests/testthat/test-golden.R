golden_dir <- system.file("tests/golden", package = "wowordcount")

skip_if_no_golden <- function() {
  skip_if_not(dir.exists(golden_dir), "golden fixtures missing")
}

load_dict_text <- function() {
  paste(readLines(file.path(golden_dir, "dictionary.tsv"),
                  warn = FALSE), collapse = "\n")
}

test_that("sanitized names follow enhance.py rule", {
  expect_equal(wc_sanitize_name("Modal Expressions!"), "Modal_Expressions")
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
  # Fixed order per interface spec: for each category, count then perc;
  # detected block last.
  expect_identical(names(got), c(
    "n_tokens", "n_types",
    as.vector(t(outer(san, c("_word_count", "_word_perc"), paste0))),
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
      # as.character(): normalize jsonlite empty arrays (list()) so
      # setequal compares like-typed vectors; this testthat build does
      # not accept info = in expect_setequal.
      expect_setequal(
        strsplit(got[[paste0(san[[idx]], "_detected_words")]][[i]],
                 ", ")[[1]],
        as.character(e$detected[[cname]])
      )
    }
  }
})
