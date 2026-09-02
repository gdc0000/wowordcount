wc_sanitize_name <- function(x) {
  x <- gsub(" ", "_", x, fixed = TRUE)
  # strip only non-word characters so Unicode letters (accents, CJK,
  # digits) survive; (*UCP) makes \w Unicode-aware under perl = TRUE
  gsub("(*UCP)[^\\w]", "", x, perl = TRUE)
}

wc_analyze_corpus <- function(texts, dict, collect_detected = FALSE) {
  cfg <- wc_prepare_config(dict)
  categories <- dict$categories
  san <- vapply(categories, wc_sanitize_name, character(1))

  # distinct categories must sanitise to distinct names, or their
  # output columns would silently overwrite each other
  if (anyDuplicated(san)) {
    dup_san <- unique(san[duplicated(san)])
    dup_orig <- categories[san %in% dup_san]
    jmvcore::reject(paste0(
      "Category names '", paste(dup_san, collapse = "', '"),
      "' collide after sanitisation: they are produced by the ",
      "categories '", paste(dup_orig, collapse = "', '"),
      "'. Rename the categories so they differ by more than punctuation."))
  }

  # a category without a single letter or number cannot name a column
  if (any(san == "")) {
    empty_orig <- categories[san == ""]
    jmvcore::reject(paste0(
      "Category name(s) ", paste0("'", empty_orig, "'", collapse = ", "),
      " contain no letters or numbers after removing punctuation; ",
      "a category name must contain at least one letter or number."))
  }

  n_docs <- length(texts)

  n_tokens <- integer(n_docs)
  n_types <- integer(n_docs)
  counts_mat <- matrix(
    0, nrow = n_docs, ncol = length(categories),
    dimnames = list(NULL, categories)
  )
  detected <- stats::setNames(
    vector("list", length(categories)), categories)

  for (i in seq_len(n_docs)) {
    tokens <- wc_tokenize(texts[[i]])
    res <- wc_count_document(tokens, cfg,
                             collect_detected = collect_detected)
    n_tokens[[i]] <- res$n_tokens
    n_types[[i]] <- res$n_types
    counts_mat[i, ] <- res$counts[categories]
    if (collect_detected) {
      for (cat in categories) {
        detected[[cat]][[i]] <-
          paste(sort(unique(res$detected[[cat]])), collapse = ", ")
      }
    }
  }

  perc_mat <- sweep(counts_mat, 1, pmax(n_tokens, 1), "/")
  perc_mat[n_tokens == 0, ] <- 0

  out <- data.frame(n_tokens = n_tokens, n_types = n_types,
                    stringsAsFactors = FALSE)
  for (j in seq_along(categories)) {
    out[[paste0(san[[j]], "_word_count")]] <-
      as.integer(counts_mat[, j])
    out[[paste0(san[[j]], "_word_perc")]] <- perc_mat[, j]
  }
  if (collect_detected) {
    for (j in seq_along(categories)) {
      col <- paste0(san[[j]], "_detected_words")
      out[[col]] <- vapply(detected[[j]],
                           function(v) ifelse(is.null(v), "", v),
                           character(1))
    }
  }
  out
}
