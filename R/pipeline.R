wc_sanitize_name <- function(x) {
  x <- gsub(" ", "_", x, fixed = TRUE)
  gsub("[^A-Za-z0-9_]", "", x)
}

wc_analyze_corpus <- function(texts, dict, collect_detected = FALSE) {
  cfg <- wc_prepare_config(dict)
  categories <- dict$categories
  san <- vapply(categories, wc_sanitize_name, character(1))
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
