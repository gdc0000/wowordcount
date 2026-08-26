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

test_that("flat single-line format parses", {
  d <- wc_parse_dictionary("very:Int; not:Neg,Neg; can*:Modal; kind of:Int")
  expect_setequal(d$categories, c("Int", "Neg", "Modal"))
  expect_setequal(d$exact_single$Int, "very")
  expect_setequal(d$exact_multi$Int, "kind of")
  expect_setequal(d$wildcard_single$Modal, "can")
  expect_length(d$exact_single$Neg, 1)
  s <- wc_dictionary_summary(d)
  expect_equal(s[s$Category == "Int", ]$ExactTerms, 1)
})

test_that("flat format errors on missing colon", {
  expect_error(wc_parse_dictionary("very; not:Neg"), "term:Category")
})

test_that("tsv with empty category column keeps that category", {
  d <- wc_parse_dictionary("DicTerm\tA\tB\nword\tX\t")
  expect_setequal(d$categories, c("A", "B"))
  expect_length(d$exact_single$B, 0)
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
  expect_length(d$terms$term, 0)
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
  expect_length(d$terms$term, 2)
})
