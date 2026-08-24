# Per-document counting engine: parity port of _prepare_analysis_config,
# _build_prefix_trie, _match_prefix_categories, _analyze_document
# from app/text_analysis.py (WordCount).
#
# Counting is asymmetric, mirroring app/text_analysis.py:
# - EXACT dictionary terms add +1 per distinct token/n-gram TYPE present,
#   regardless of how often the type occurs in the document.
# - WILDCARD prefix terms add the full document FREQUENCY (+f) of each
#   matching token/n-gram type.
# A term listed both exactly and reachable through a wildcard prefix
# therefore contributes BOTH +1 (exact) and +f (wildcard).

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
      ex <- cfg$exact_single_lookup[[token]]
      if (is.null(ex))
        ex <- character(0)
      ex <- unique(ex)
      wl <- unique(wc_trie_match(cfg$single_trie, token))
      for (cat in ex)
        counts[cat] <- counts[cat] + 1L
      for (cat in wl)
        counts[cat] <- counts[cat] + f
      if (collect_detected) {
        for (cat in unique(c(ex, wl)))
          detected[[cat]] <- c(detected[[cat]], token)
      }
    }

    if (length(cfg$required_lengths) > 0L && n_tokens >= 2L) {
      ngrams <- wc_generate_ngrams(tokens, cfg$required_lengths)
      ng_freq <- table(ngrams)
      for (ng in names(ng_freq)) {
        f <- as.integer(ng_freq[[ng]])
        ex <- cfg$exact_multi_lookup[[ng]]
        if (is.null(ex))
          ex <- character(0)
        ex <- unique(ex)
        wl <- unique(wc_trie_match(cfg$multi_trie, ng))
        for (cat in ex)
          counts[cat] <- counts[cat] + 1L
        for (cat in wl)
          counts[cat] <- counts[cat] + f
        if (collect_detected) {
          for (cat in unique(c(ex, wl)))
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
