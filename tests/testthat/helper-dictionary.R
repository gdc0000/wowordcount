# translate DicTerm TSV lines into the lexicon structure the
# live parser expects: one entry per category, comma-joined terms
make_dict <- function(...) {
  lines <- strsplit(paste(..., sep = "\n"), "\n", fixed = TRUE)[[1]]
  header <- strsplit(lines[[1]], "\t", fixed = TRUE)[[1]]
  stopifnot(identical(tolower(trimws(header[[1]])), "dicterm"))
  categories <- trimws(header[-1])
  terms_by_cat <- stats::setNames(
    rep(list(character(0)), length(categories)), categories)
  for (line in lines[-1]) {
    cells <- strsplit(line, "\t", fixed = TRUE)[[1]]
    term <- trimws(cells[[1]])
    if (!nzchar(term))
      next
    # a comma in a term would be silently re-split by wc_parse_lexicon_rows; never feed it one
    stopifnot(!grepl(",", term))
    for (j in seq_along(categories)) {
      # strsplit drops trailing empty cells, so pad missing columns to ""
      cell <- if (length(cells) > j) trimws(cells[[j + 1L]]) else ""
      if (identical(toupper(cell), "X"))
        terms_by_cat[[j]] <- c(terms_by_cat[[j]], term)
    }
  }
  wc_parse_lexicon_rows(lapply(seq_along(categories), function(j)
    list(category = categories[[j]],
         terms = paste(terms_by_cat[[j]], collapse = ", "))))
}
