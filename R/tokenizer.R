# Cleaning/tokenization parity port of app/text_analysis.py (WordCount).
# Python \w matches Unicode word chars; (*UCP) switches PCRE to Unicode mode
# so accented letters behave identically. Apostrophe preserved like the original.

wc_max_ngram_size <- 5L

wc_clean_document <- function(doc) {
  if (is.na(doc))
    return("")
  doc <- tolower(as.character(doc))
  gsub("(*UCP)[^\\w\\s']", " ", doc, perl = TRUE)
}

wc_tokenize <- function(doc) {
  parts <- strsplit(wc_clean_document(doc), "[[:space:]]+", perl = TRUE)[[1]]
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
    starts <- 1L:(n_tokens - n + 1L)
    windows <- vapply(
      starts,
      function(s) paste(tokens[s:(s + n - 1L)], collapse = " "),
      character(1)
    )
    out <- c(out, windows)
  }
  out
}
