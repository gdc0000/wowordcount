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
