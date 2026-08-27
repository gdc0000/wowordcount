# Per-document counting engine for wowordcount.
#
# Counting follows CLASSIC LIWC frequency semantics:
# - Every token/n-gram OCCURRENCE counts with its full document frequency
#   (+f) toward each category it matches.
# - A token/n-gram matching a category through BOTH an exact dictionary
#   term and one or more wildcard prefixes counts ONCE per category
#   (per-category dedup); overlapping prefixes of the same category do
#   not multiply the count either.
# - Multi-word terms are matched against n-grams generated only for the
#   lengths demanded by the dictionary (maximum 5).
#
# This differs from app/text_analysis.py of the legacy Streamlit WordCount
# app, which added +1 per distinct type for exact hits and accumulated
# wildcard hits once per matching prefix; results are NOT comparable.

wc_wildcard_match <- function(prefixes_by_cat, term) {
  hit <- character(0)
  for (cat in names(prefixes_by_cat)) {
    pre <- prefixes_by_cat[[cat]]
    if (length(pre) > 0L && any(startsWith(rep(term, length(pre)), pre)))
      hit <- c(hit, cat)
  }
  hit
}

wc_prepare_config <- function(dict) {
  categories <- dict$categories
  es_lookup <- list()
  em_lookup <- list()
  wildcard_single <- list()
  wildcard_multi <- list()
  req_len <- integer(0)

  add_to_named_list <- function(lst, key, val) {
    lst[[key]] <- if (is.null(lst[[key]])) val else c(lst[[key]], val)
    lst
  }

  for (cat in categories) {
    for (term in dict$exact_single[[cat]])
      es_lookup <- add_to_named_list(es_lookup, term, cat)
    for (prefix in dict$wildcard_single[[cat]])
      if (nzchar(prefix))
        wildcard_single[[cat]] <- c(wildcard_single[[cat]], prefix)
    for (term in dict$exact_multi[[cat]]) {
      em_lookup <- add_to_named_list(em_lookup, term, cat)
      k <- length(strsplit(term, " ", fixed = TRUE)[[1]])
      if (2 <= k && k <= wc_max_ngram_size)
        req_len <- c(req_len, k)
    }
    for (prefix in dict$wildcard_multi[[cat]]) {
      if (nzchar(prefix))
        wildcard_multi[[cat]] <- c(wildcard_multi[[cat]], prefix)
      k <- length(strsplit(prefix, " ", fixed = TRUE)[[1]])
      if (k <= wc_max_ngram_size)
        req_len <- c(req_len, seq(max(k, 2L), wc_max_ngram_size))
    }
  }

  list(
    categories = categories,
    exact_single_lookup = es_lookup,
    exact_multi_lookup = em_lookup,
    wildcard_single = wildcard_single,
    wildcard_multi = wildcard_multi,
    required_lengths = sort(unique(as.integer(req_len)))
  )
}

wc_count_document <- function(tokens, cfg, collect_detected = FALSE) {
  categories <- cfg$categories
  counts <- stats::setNames(rep(0, length(categories)), categories)
  detected <- stats::setNames(
    vector("list", length(categories)), categories)

  n_tokens <- length(tokens)
  n_types <- length(unique(tokens))

  if (n_tokens > 0L) {
    freq <- table(tokens)

    for (token in names(freq)) {
      f <- as.integer(freq[[token]])
      # LIWC-classic: exact and wildcard matches dedup per category,
      # then the token's full frequency counts once per matched category
      cats_hit <- unique(c(cfg$exact_single_lookup[[token]],
                           wc_wildcard_match(cfg$wildcard_single, token)))
      for (cat in cats_hit) {
        counts[cat] <- counts[cat] + f
        if (collect_detected)
          detected[[cat]] <- c(detected[[cat]], token)
      }
    }

    if (length(cfg$required_lengths) > 0L && n_tokens >= 2L) {
      ngrams <- wc_generate_ngrams(tokens, cfg$required_lengths)
      ng_freq <- table(ngrams)
      for (ng in names(ng_freq)) {
        f <- as.integer(ng_freq[[ng]])
        # LIWC-classic dedup per category, as for single tokens
        cats_hit <- unique(c(cfg$exact_multi_lookup[[ng]],
                             wc_wildcard_match(cfg$wildcard_multi, ng)))
        for (cat in cats_hit) {
          counts[cat] <- counts[cat] + f
          if (collect_detected)
            detected[[cat]] <- c(detected[[cat]], ng)
        }
      }
    }
  }

  list(
    n_tokens = n_tokens,
    n_types = n_types,
    counts = counts,
    detected = detected
  )
}
