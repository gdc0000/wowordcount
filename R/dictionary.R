wc_is_x_marker <- function(cell) {
  !is.na(cell) && nzchar(cell) && identical(toupper(trimws(cell)), "X")
}

wc_is_flat_dictionary <- function(text) {
  !grepl("\n", text, fixed = TRUE) && grepl(";", text, fixed = TRUE)
}

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

  terms_df <- data.frame(
    term = character(0), is_wildcard = logical(0),
    n_words = integer(0), categories = character(0),
    stringsAsFactors = FALSE
  )

  for (row in rows) {
    term <- row$term
    hit_cats <- row$cats
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

    terms_df <- rbind(terms_df, data.frame(
      term = clean_term, is_wildcard = is_wild,
      n_words = n_words,
      categories = paste(hit_cats, collapse = ", "),
      stringsAsFactors = FALSE
    ))
  }

  list(
    exact_single = exact_single,
    wildcard_single = wildcard_single,
    exact_multi = exact_multi,
    wildcard_multi = wildcard_multi,
    terms = terms_df
  )
}

wc_as_wcdict <- function(categories, routed) {
  out <- c(list(categories = categories), routed)
  class(out) <- "wcdict"
  out
}

wc_parse_dictionary <- function(text) {
  if (is.null(text) || nchar(trimws(text)) == 0L)
    stop("No dictionary provided. Paste your wordlist (TSV) ",
         "into the dictionary box.", call. = FALSE)

  if (wc_is_flat_dictionary(text)) {
    parsed <- wc_parse_flat_rows(text)
  } else {
    parsed <- wc_parse_tsv_rows(text)
  }

  wc_as_wcdict(parsed$categories,
               wc_route_term_rows(parsed$rows, parsed$categories))
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

wc_parse_tsv_rows <- function(text) {
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

  rows <- list()
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
      if (length(hit_cats) == 0L)
        next
      rows[[length(rows) + 1L]] <- list(term = term, cats = hit_cats)
    }
  }
  list(rows = rows, categories = categories)
}

wc_parse_flat_rows <- function(text) {
  segments <- trimws(strsplit(text, ";", fixed = TRUE)[[1]])
  segments <- segments[nzchar(segments)]
  if (length(segments) == 0L)
    stop("Flat dictionary is empty. Expected format: ",
         "term:Category1,Category2; another term:Category1",
         call. = FALSE)

  rows <- list()
  for (seg in segments) {
    pos <- regexpr(":", seg, fixed = TRUE)
    if (pos == -1L)
      stop("Segment '", seg, "' is missing ':'. Expected format: ",
           "term:Category1,Category2; another term:Category1",
           call. = FALSE)
    term <- trimws(substr(seg, 1L, pos - 1L))
    cat_part <- trimws(substr(seg, pos + 1L, nchar(seg)))
    seg_cats <- trimws(strsplit(cat_part, ",", fixed = TRUE)[[1]])
    seg_cats <- seg_cats[nzchar(seg_cats)]
    if (!nzchar(term) || length(seg_cats) == 0L)
      stop("Segment '", seg, "' needs a term and at least one ",
           "category. Expected format: ",
           "term:Category1,Category2; another term:Category1",
           call. = FALSE)
    rows[[length(rows) + 1L]] <- list(term = term, cats = seg_cats)
  }
  list(rows = rows, categories = unique(unlist(lapply(rows, `[[`, "cats"),
                                             use.names = FALSE)))
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
