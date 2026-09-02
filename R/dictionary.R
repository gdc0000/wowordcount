wc_dict_skeleton <- function(categories) {
  buckets <- stats::setNames(
    vector("list", length(categories)), categories)
  for (i in seq_along(buckets))
    buckets[[i]] <- character(0)
  buckets
}

wc_route_term_rows <- function(rows, categories) {
  exact_single <- wc_dict_skeleton(categories)
  wildcard_single <- exact_single
  exact_multi <- exact_single
  wildcard_multi <- exact_single

  # accumulate raw terms per bucket, unique once at the end: avoids the
  # O(n^2) cost of union() per term x category on large lexicons
  for (row in rows) {
    term <- row$term
    hit_cats <- row$cats
    is_wild <- endsWith(term, "*")
    clean_term <- trimws(gsub("[[:space:]]+", " ",
                              sub("\\*$", "", term)))
    n_words <- length(strsplit(clean_term, "[[:space:]]+", perl = TRUE)[[1]])

    # drop terms that can never match (counted in the dictionary summary
    # but never matched downstream): empty stem or prefix longer than the
    # ngram window; residual "*" after stripping one trailing marker
    # ("can**", "* *"); no word character or apostrophe (".", "!", ...),
    # with (*UCP) so Unicode terms still pass. Internal whitespace runs
    # are normalised above to the single-space joins n-grams use.
    if (!nzchar(clean_term) || n_words > wc_max_ngram_size ||
        grepl("*", clean_term, fixed = TRUE) ||
        !grepl("(*UCP)[\\w']", clean_term, perl = TRUE))
      next

    if (is_wild) {
      if (n_words > 1L) {
        for (cat in hit_cats)
          wildcard_multi[[cat]] <- c(wildcard_multi[[cat]], clean_term)
      } else {
        for (cat in hit_cats)
          wildcard_single[[cat]] <- c(wildcard_single[[cat]], clean_term)
      }
    } else {
      if (n_words > 1L) {
        for (cat in hit_cats)
          exact_multi[[cat]] <- c(exact_multi[[cat]], clean_term)
      } else {
        for (cat in hit_cats)
          exact_single[[cat]] <- c(exact_single[[cat]], clean_term)
      }
    }
  }

  buckets <- list(exact_single, wildcard_single, exact_multi, wildcard_multi)
  buckets <- lapply(buckets, function(bucket)
    lapply(bucket, function(v) if (is.null(v)) character(0) else unique(v)))
  exact_single <- buckets[[1]]
  wildcard_single <- buckets[[2]]
  exact_multi <- buckets[[3]]
  wildcard_multi <- buckets[[4]]

  list(
    exact_single = exact_single,
    wildcard_single = wildcard_single,
    exact_multi = exact_multi,
    wildcard_multi = wildcard_multi
  )
}

wc_as_wcdict <- function(categories, routed) {
  out <- c(list(categories = categories), routed)
  class(out) <- "wcdict"
  out
}

wc_parse_lexicon_rows <- function(entries) {
  rows <- list()
  categories <- character(0)

  if (!is.null(entries)) {
    for (entry in entries) {
      category <- character(0)
      if (!is.null(entry$category) && length(entry$category) > 0L)
        category <- trimws(as.character(entry$category))
      terms_raw <- ""
      if (!is.null(entry$terms) && length(entry$terms) > 0L)
        terms_raw <- as.character(entry$terms)[1]
      terms <- trimws(strsplit(terms_raw, ",", fixed = TRUE)[[1]])
      terms <- terms[nzchar(terms)]

      if (length(category) == 0L || !nzchar(category) ||
          length(terms) == 0L)
        next

      categories <- union(categories, category)
      for (term in terms)
        rows[[length(rows) + 1L]] <- list(term = term, cats = category)
    }
  }

  wc_as_wcdict(categories,
               wc_route_term_rows(rows, categories))
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
