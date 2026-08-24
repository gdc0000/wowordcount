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

test_that("simple exact counting counts distinct types", {
  d <- make_dict("DicTerm\tNeg", "not\tX", "never\tX")
  cfg <- wc_prepare_config(d)
  res <- wc_count_document(c("not", "now", "not", "never"), cfg)
  expect_equal(res$n_tokens, 4)
  expect_equal(res$n_types, 3)
  expect_equal(unname(res$counts["Neg"]), 2)
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
  expect_equal(unname(res$counts["C"]), 1)
})

test_that("multi-word wildcard prefix matches", {
  d <- make_dict("DicTerm\tM", "might be*\tX")
  cfg <- wc_prepare_config(d)
  res <- wc_count_document(
    c("it", "might", "be", "rain", "might", "bee"), cfg)
  expect_equal(unname(res$counts["M"]), 5)
})

test_that("term shared across categories counted in both", {
  d <- make_dict("DicTerm\tA\tB", "yes\tX\tX")
  cfg <- wc_prepare_config(d)
  res <- wc_count_document(c("yes", "yes"), cfg)
  expect_equal(unname(res$counts["A"]), 1)
  expect_equal(unname(res$counts["B"]), 1)
})

test_that("exact and wildcard contributions combine like upstream", {
  d <- make_dict("DicTerm\tX", "dog\tX", "do*\tX")
  cfg <- wc_prepare_config(d)
  res <- wc_count_document(c("dog", "dog", "dot"), cfg)
  # exact: "dog" counted once as a distinct type (+1);
  # wildcard: dog (f=2) + dot (f=1) = 3; total 4
  expect_equal(unname(res$counts["X"]), 4)
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

test_that("terms longer than max ngram size contribute no lengths", {
  d <- make_dict("DicTerm\tX", "one two three four five six\tX", "might be*\tX")
  cfg <- wc_prepare_config(d)
  expect_setequal(cfg$required_lengths, c(2L, 3L, 4L, 5L))
})

test_that("bare star prefix is ignored like upstream python", {
  d <- make_dict("DicTerm\tX", "*\tX", "dog\tX")
  cfg <- wc_prepare_config(d)
  res <- wc_count_document(c("cat", "dog"), cfg)
  expect_equal(unname(res$counts["X"]), 1)
})
