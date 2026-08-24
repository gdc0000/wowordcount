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
    check.names = FALSE, na.strings = NULL, stringsAsFactors = FALSE
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
    WildcardPrefixes = vapply(
      dict$categories,
      function(c) length(dict$wildcard_single[[c]]) +
        length(dict$wildcard_multi[[c]]),
      integer(1)
    ),
    MultiWordTerms = vapply(
      dict$categories,
      function(c) length(dict$exact_multi[[c]]) +
        length(dict$wildcard_multi[[c]]),
      integer(1)
    ),
    stringsAsFactors = FALSE
  )
}
