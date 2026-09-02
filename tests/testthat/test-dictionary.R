test_that("summary table counts correctly", {
  d <- wc_parse_lexicon_rows(list(
    list(category = "Intensifiers", terms = "very, extremely"),
    list(category = "Negations", terms = "not, never"),
    list(category = "Modal_Expressions", terms = "can*, might be*")
  ))
  s <- wc_dictionary_summary(d)
  intens <- s[s$Category == "Intensifiers", ]
  expect_equal(intens$ExactTerms, 2)
  modal <- s[s$Category == "Modal_Expressions", ]
  expect_equal(modal$WildcardPrefixes, 2)
  expect_equal(modal$MultiWordTerms, 1)
})

test_that("lexicon builder parses categories, wildcards and multi-word", {
  d <- wc_parse_lexicon_rows(list(
    list(category = "Intensifiers", terms = "very, extremely"),
    list(category = "Modal_Expressions", terms = "can*, might be*")
  ))
  expect_setequal(d$categories,
                  c("Intensifiers", "Modal_Expressions"))
  expect_setequal(d$exact_single$Intensifiers, c("very", "extremely"))
  expect_setequal(d$wildcard_single$Modal_Expressions, "can")
  expect_setequal(d$wildcard_multi$Modal_Expressions, "might be")
})

test_that("lexicon builder merges duplicate category rows", {
  d <- wc_parse_lexicon_rows(list(
    list(category = "A", terms = "dog"),
    list(category = "A", terms = "bird, dog")
  ))
  expect_identical(d$categories, "A")
  expect_setequal(d$exact_single$A, c("dog", "bird"))
  expect_length(d$exact_single$A, 2)
})

test_that("lexicon builder skips rows with empty terms", {
  d <- wc_parse_lexicon_rows(list(
    list(category = "A", terms = ""),
    list(category = "B", terms = "word")
  ))
  expect_identical(d$categories, "B")
  expect_length(d$exact_single$A, 0)
})

test_that("lexicon row with category but empty terms alone yields no categories", {
  d <- wc_parse_lexicon_rows(list(list(category = "A", terms = "")))
  expect_length(d$categories, 0)
  expect_length(d$exact_single, 0)
})

test_that("resolve: builder mode uses builder rows only", {
  d <- wc_resolve_dictionary(
    list(list(category = "A", terms = "dog"))
  )
  expect_identical(d$categories, "A")
  expect_setequal(d$exact_single$A, "dog")
  expect_identical(attr(d, "source"), "lexicon builder")
})

test_that("resolve: builder mode with no complete rows errors", {
  expect_error(
    wc_resolve_dictionary(list(list(category = "A", terms = "   "))),
    regexp = "no complete rows"
  )
  expect_error(
    wc_resolve_dictionary(NULL),
    regexp = "no complete rows"
  )
})

test_that("lexicon builder trims terms and drops empties", {
  d <- wc_parse_lexicon_rows(list(
    list(category = " A ", terms = " dog , , cat ")
  ))
  expect_identical(d$categories, "A")
  expect_setequal(d$exact_single$A, c("dog", "cat"))
  expect_length(d$exact_single$A, 2)
})

test_that("over-long and bare-star terms are filtered at parse time", {
  d <- wc_parse_lexicon_rows(list(
    list(category = "X",
         terms = paste("one two three four five six*,",
                       "one two three four five six, *, dog"))
  ))
  s <- wc_dictionary_summary(d)
  x <- s[s$Category == "X", ]
  expect_equal(x$ExactTerms, 1)
  expect_equal(x$WildcardPrefixes, 0)
  expect_equal(x$MultiWordTerms, 0)
  expect_setequal(d$exact_single$X, "dog")
  expect_length(d$wildcard_single$X, 0)
  expect_length(d$wildcard_multi$X, 0)
  expect_length(d$exact_multi$X, 0)
})

test_that("degenerate stems and punctuation-only terms are filtered", {
  d <- wc_parse_lexicon_rows(list(
    list(category = "X", terms = ".*, *, can**, !, don't*, dog")
  ))
  s <- wc_dictionary_summary(d)
  x <- s[s$Category == "X", ]
  expect_equal(x$ExactTerms, 1)
  expect_equal(x$WildcardPrefixes, 1)
  expect_equal(x$MultiWordTerms, 0)
  expect_setequal(d$exact_single$X, "dog")
  expect_setequal(d$wildcard_single$X, "don't")
  expect_length(d$wildcard_multi$X, 0)
  expect_length(d$exact_multi$X, 0)
})

test_that("unicode stems survive the filter", {
  d <- wc_parse_lexicon_rows(list(
    list(category = "X", terms = "Émotion*, très")
  ))
  # accents survive; terms are case-folded like documents
  expect_setequal(d$wildcard_single$X, "émotion")
  expect_setequal(d$exact_single$X, "très")
  s <- wc_dictionary_summary(d)
  expect_equal(s$WildcardPrefixes[s$Category == "X"], 1)
  expect_equal(s$ExactTerms[s$Category == "X"], 1)
})

test_that("internal whitespace runs normalise to n-gram join form", {
  d <- wc_parse_lexicon_rows(list(
    list(category = "X", terms = "a  b")
  ))
  # the double-space literal never reaches the buckets: the stored and
  # counted form is the single-space join n-grams are built from
  expect_setequal(d$exact_multi$X, "a b")
  expect_equal(wc_dictionary_summary(d)$MultiWordTerms, 1)
  cfg <- wc_prepare_config(d)
  res <- wc_count_document(c("an", "a", "b", "day"), cfg)
  expect_equal(unname(res$counts["X"]), 1)
})

test_that("boundary-length terms pass the filter untouched", {
  d <- wc_parse_lexicon_rows(list(
    list(category = "Exact_Five", terms = "one two three four five"),
    list(category = "Wild_Five", terms = "one two three four five*"),
    list(category = "Modal", terms = "can*")
  ))
  s <- wc_dictionary_summary(d)
  expect_equal(s$MultiWordTerms[s$Category == "Exact_Five"], 1)
  expect_equal(s$MultiWordTerms[s$Category == "Wild_Five"], 1)
  expect_equal(s$WildcardPrefixes[s$Category == "Wild_Five"], 1)
  expect_equal(s$WildcardPrefixes[s$Category == "Modal"], 1)
  expect_setequal(d$exact_multi$Exact_Five, "one two three four five")
  expect_setequal(d$wildcard_multi$Wild_Five, "one two three four five")
  expect_setequal(d$wildcard_single$Modal, "can")
})
