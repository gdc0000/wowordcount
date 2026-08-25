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

wc_trie_new <- function() new.env(parent = emptyenv())

wc_trie_add <- function(trie, prefix, cats) {
  node <- trie
  chars <- strsplit(prefix, "", fixed = TRUE)[[1]]
  for (ch in chars) {
    nxt <- node[[ch]]
    if (is.null(nxt)) {
      nxt <- wc_trie_new()
      assign(ch, nxt, envir = node)
    }
    node <- nxt
  }
  existing <- node$.terminal_
  node$.terminal_ <- if (is.null(existing)) cats else c(existing, cats)
  invisible(NULL)
}

wc_trie_match <- function(trie, term) {
  if (isEmptyTrie(trie))
    return(character(0))
  node <- trie
  matched <- character(0)
  chars <- strsplit(term, "", fixed = TRUE)[[1]]
  for (ch in chars) {
    nxt <- node[[ch]]
    if (is.null(nxt))
      break
    node <- nxt
    if (!is.null(node$.terminal_))
      matched <- c(matched, node$.terminal_)
  }
  matched
}

isEmptyTrie <- function(trie) length(ls(trie)) == 0L

wc_prepare_config <- function(dict) {
  categories <- dict$categories
  es_lookup <- list()
  em_lookup <- list()
  s_trie <- wc_trie_new()
  m_trie <- wc_trie_new()
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
        wc_trie_add(s_trie, prefix, cat)
    for (term in dict$exact_multi[[cat]]) {
      em_lookup <- add_to_named_list(em_lookup, term, cat)
      k <- length(strsplit(term, " ", fixed = TRUE)[[1]])
      if (2 <= k && k <= wc_max_ngram_size)
        req_len <- c(req_len, k)
    }
    for (prefix in dict$wildcard_multi[[cat]]) {
      if (nzchar(prefix))
        wc_trie_add(m_trie, prefix, cat)
      k <- length(strsplit(prefix, " ", fixed = TRUE)[[1]])
      if (k <= wc_max_ngram_size)
        req_len <- c(req_len, seq(max(k, 2L), wc_max_ngram_size))
    }
  }

  list(
    categories = categories,
    exact_single_lookup = es_lookup,
    exact_multi_lookup = em_lookup,
    single_trie = s_trie,
    multi_trie = m_trie,
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
                           wc_trie_match(cfg$single_trie, token)))
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
                             wc_trie_match(cfg$multi_trie, ng)))
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
