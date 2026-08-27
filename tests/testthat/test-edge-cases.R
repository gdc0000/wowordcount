make_dict <- function(...) {
  wc_parse_dictionary(paste(..., sep = "\n"))
}

test_that("all-NA text variable yields zero-token documents without error", {
  d <- make_dict("DicTerm\tP", "good\tX")
  res <- wc_analyze_corpus(c(NA, NA), d)
  expect_equal(res$n_tokens, c(0L, 0L))
  expect_equal(res$n_types, c(0L, 0L))
  expect_equal(res$P_word_count, c(0L, 0L))
  expect_equal(res$P_word_perc, c(0, 0))
})

test_that("NA documents mixed with real text are handled", {
  d <- make_dict("DicTerm\tP", "good\tX")
  res <- wc_analyze_corpus(c(NA, "a very good day"), d)
  expect_equal(res$n_tokens, c(0L, 4L))
  expect_equal(res$P_word_count, c(0L, 1L))
  expect_equal(res$P_word_perc, c(0, 0.25))
})

test_that("empty string documents yield zero tokens", {
  d <- make_dict("DicTerm\tP", "good\tX")
  res <- wc_analyze_corpus(c("", "good good"), d)
  expect_equal(res$n_tokens, c(0L, 2L))
  expect_equal(res$P_word_count, c(0L, 2L))
  expect_equal(res$P_word_perc, c(0, 1))
})

test_that("detected-words column is empty string for NA documents", {
  d <- make_dict("DicTerm\tP", "good\tX")
  res <- wc_analyze_corpus(c(NA, "good"), d, collect_detected = TRUE)
  expect_equal(res$P_detected_words, c("", "good"))
})

test_that("factor input behaves like character input", {
  d <- make_dict("DicTerm\tP", "good\tX")
  chars <- wc_analyze_corpus(c("good day", "good"), d)
  facts <- wc_analyze_corpus(factor(c("good day", "good")), d)
  expect_equal(facts, chars)
})
