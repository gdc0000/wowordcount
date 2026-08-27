test_that("tokenizing handles NA, case, punctuation", {
  expect_equal(wc_tokenize(NA_character_), character(0))
  expect_equal(wc_tokenize("Hello, World!"), c("hello", "world"))
})

test_that("apostrophes and underscores survive", {
  expect_equal(wc_tokenize("L'amico_non_è"), "l'amico_non_è")
})

test_that("accented characters survive cleaning (Italian corpus)", {
  toks <- wc_tokenize("Perché città è-andata")
  expect_setequal(toks, c("perché", "città", "è", "andata"))
})

test_that("tokenize drops empties and splits on any whitespace", {
  expect_setequal(wc_tokenize("  a\t b\nc "), c("a", "b", "c"))
  expect_length(wc_tokenize(""), 0)
})

test_that("NBSP is treated as splitting whitespace (Python parity)", {
  expect_setequal(wc_tokenize("perch\u00E9\u00A0citt\u00E0"), c("perch\u00e9", "citt\u00e0"))
  expect_setequal(wc_tokenize("a\u00A0b"), c("a", "b"))
})

test_that("n-grams cover requested lengths only", {
  toks <- c("the", "quick", "brown", "fox")
  ng <- wc_generate_ngrams(toks, c(2, 4))
  expect_true("quick brown" %in% ng)
  expect_true("the quick brown fox" %in% ng)
  expect_false("the quick brown" %in% ng)
  expect_false("quick brown fox" %in% ng)
})

test_that("n-grams respect max length availability", {
  expect_length(wc_generate_ngrams(c("one"), 2), 0)
  expect_setequal(wc_generate_ngrams(c("a", "b"), 2), "a b")
})
