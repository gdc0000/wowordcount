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

# Vectorized type-key matching for one category: TRUE where the key is an
# exact term of the category or starts with one of its wildcard prefixes.
# Replaces the old per-token wc_wildcard_match loop (per-category
# membership semantics preserved), at C speed.
wc_match_mask <- function(keys, exact_keys, prefixes) {
  n <- length(keys)
  mask <- if (length(exact_keys) > 0L) !is.na(match(keys, exact_keys))
          else logical(n)
  if (length(prefixes) > 0L) {
    wm <- Reduce(`|`, lapply(prefixes, function(p) startsWith(keys, p)))
    mask <- mask | wm
  }
  mask
}

wc_prepare_config <- function(dict) {
  categories <- dict$categories
  es_lookup <- list()
  em_lookup <- list()
  es_by_cat <- wc_dict_skeleton(categories)
  em_by_cat <- wc_dict_skeleton(categories)
  wildcard_single <- list()
  wildcard_multi <- list()
  req_len_list <- list()

  add_to_named_list <- function(lst, key, val) {
    lst[[key]] <- if (is.null(lst[[key]])) val else c(lst[[key]], val)
    lst
  }

  for (cat in categories) {
    es_by_cat[[cat]] <- unique(as.character(dict$exact_single[[cat]]))
    em_by_cat[[cat]] <- unique(as.character(dict$exact_multi[[cat]]))
    for (term in es_by_cat[[cat]])
      es_lookup <- add_to_named_list(es_lookup, term, cat)
    for (term in em_by_cat[[cat]]) {
      em_lookup <- add_to_named_list(em_lookup, term, cat)
      k <- length(strsplit(term, " ", fixed = TRUE)[[1]])
      if (2 <= k && k <= wc_max_ngram_size)
        req_len_list[[length(req_len_list) + 1L]] <- k
    }
    for (prefix in dict$wildcard_single[[cat]])
      if (nzchar(prefix))
        wildcard_single[[cat]] <- c(wildcard_single[[cat]], prefix)
    for (prefix in dict$wildcard_multi[[cat]]) {
      if (nzchar(prefix))
        wildcard_multi[[cat]] <- c(wildcard_multi[[cat]], prefix)
      k <- length(strsplit(prefix, " ", fixed = TRUE)[[1]])
      if (k <= wc_max_ngram_size)
        req_len_list[[length(req_len_list) + 1L]] <-
          seq(max(k, 2L), wc_max_ngram_size)
    }
  }

  list(
    categories = categories,
    exact_single_lookup = es_lookup,
    exact_multi_lookup = em_lookup,
    exact_single_by_cat = es_by_cat,
    exact_multi_by_cat = em_by_cat,
    wildcard_single = wildcard_single,
    wildcard_multi = wildcard_multi,
    required_lengths = sort(unique(as.integer(unlist(req_len_list))))
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
    # type/frequency table via match + tabulate (C-level, no table())
    keys <- unique(tokens)
    freq <- tabulate(match(tokens, keys), nbins = length(keys))

    # LIWC-classic: exact and wildcard matches dedup per category, then
    # the token's full frequency counts once per matched category
    for (j in seq_along(categories)) {
      cat <- categories[[j]]
      mask <- wc_match_mask(keys, cfg$exact_single_by_cat[[cat]],
                            cfg$wildcard_single[[cat]])
      if (any(mask)) {
        counts[[cat]] <- sum(freq[mask])
        if (collect_detected)
          detected[[cat]] <- keys[mask]
      }
    }

    if (length(cfg$required_lengths) > 0L && n_tokens >= 2L) {
      ngrams <- wc_generate_ngrams(tokens, cfg$required_lengths)
      if (length(ngrams) > 0L) {
        ng_keys <- unique(ngrams)
        ng_freq <- tabulate(match(ngrams, ng_keys),
                            nbins = length(ng_keys))
        # LIWC-classic dedup per category, as for single tokens
        for (j in seq_along(categories)) {
          cat <- categories[[j]]
          mask <- wc_match_mask(ng_keys, cfg$exact_multi_by_cat[[cat]],
                                cfg$wildcard_multi[[cat]])
          if (any(mask)) {
            counts[[cat]] <- counts[[cat]] + sum(ng_freq[mask])
            if (collect_detected)
              detected[[cat]] <- c(detected[[cat]], ng_keys[mask])
          }
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
