# Cleaning/tokenization parity port of app/text_analysis.py (WordCount).
# Python \w matches Unicode word chars; (*UCP) switches PCRE to Unicode mode
# so accented letters behave identically. Apostrophe preserved like the original.

wc_max_ngram_size <- 5L

wc_tokenize <- function(doc) {
  if (is.na(doc))
    return(character(0))
  doc <- tolower(as.character(doc))
  cleaned <- gsub("(*UCP)[^\\w\\s']", " ", doc, perl = TRUE)
  parts <- strsplit(cleaned, "(*UCP)\\s+", perl = TRUE)[[1]]
  parts[nzchar(parts)]
}

wc_generate_ngrams <- function(tokens, lengths) {
  lengths <- unique(as.integer(lengths))
  lengths <- lengths[lengths >= 2L]
  n_tokens <- length(tokens)
  out <- character(0)
  for (n in lengths) {
    if (n > n_tokens || n < 2L)
      next
    starts <- seq_len(n_tokens - n + 1L)
    # one paste() call per length: paste column-wise across n shifted
    # token vectors; output identical to per-window collapse = " "
    windows <- do.call(
      paste,
      c(lapply(seq_len(n) - 1L, function(o) tokens[o + starts]),
        list(sep = " "))
    )
    out <- c(out, windows)
  }
  out
}
