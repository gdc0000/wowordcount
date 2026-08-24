#' @export
wordcountClass <- R6::R6Class(
    "wordcountClass",
    inherit = wordcountBase,
    private = list(
        .runAnalysis = function() {
            dict_text <- self$options$dictionary
            if (is.null(dict_text) || nchar(trimws(dict_text)) == 0L)
                stop("Paste a dictionary (TSV) into the dictionary box.")

            dict <- wc_parse_dictionary(dict_text)

            # summary table
            tbl <- self$results$dictSummary
            summary_df <- wc_dictionary_summary(dict)
            for (i in seq_len(nrow(summary_df))) {
                tbl$addRow(rowKey = summary_df$Category[i], values = list(
                    category = summary_df$Category[i],
                    exactTerms = summary_df$ExactTerms[i],
                    wildcardPrefixes = summary_df$WildcardPrefixes[i],
                    multiWordTerms = summary_df$MultiWordTerms[i]
                ))
            }
            if (nrow(summary_df) == 0L)
                tbl$setNote(
                    "noCats",
                    "No categories were found in the dictionary."
                )

            texts <- self$data[[self$options$textVar]]

            want_detected <- isTRUE(self$options$detectedWords)
            results <- wc_analyze_corpus(texts, dict,
                                         collect_detected = want_detected)

            note <- sprintf(
                "%d documents analysed, %d categories.",
                nrow(results), length(dict$categories)
            )
            self$results$statusNote$setVisible(TRUE)
            self$results$statusNote$setContent(note)

            if (all(results$n_tokens == 0))
                tbl$setNote(
                    "noHits",
                    "No tokens found in the selected text variable."
                )

            if (self$options$saveResults &&
                self$results$savedResults$isNotFilled()) {
                keys <- names(results)
                titles <- keys
                descriptions <- vapply(keys, function(k) {
                    if (grepl("_word_count$", k))
                        "Matches for category (count)"
                    else if (grepl("_word_perc$", k))
                        "Matches divided by token count"
                    else if (grepl("_detected_words$", k))
                        "Comma-separated words matched for category"
                    else if (k == "n_tokens")
                        "Total number of tokens in the document"
                    else
                        "Number of distinct tokens in the document"
                }, character(1))
                measure_types <- ifelse(
                    grepl("_detected_words$", keys), "nominal", "continuous")

                self$results$savedResults$set(
                    keys, titles, descriptions, measure_types)
                self$results$savedResults$setRowNums(rownames(self$data))
                for (k in keys)
                    self$results$savedResults$setValues(
                        results[[k]], key = k)
            }

            TRUE
        }
    )
)
