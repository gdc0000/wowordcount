GLOBAL CONSTRAINTS
=========

- Target user: psychology researcher on an 8 GB RAM laptop. Base R only; no new heavy dependencies; no Python runtime dependency at analysis time.
- Numeric parity with the Python original is mandatory: same tokenizer regex behavior, same n-gram rule, same counting semantics. Golden tests enforce it.
- Dictionary paste format (TSV): header row starting with `DicTerm`, one column per category, cell value `X` (case-insensitive, trimmed) marks membership, trailing `*` marks a prefix wildcard, terms may contain internal spaces (multi-word).
- Max n-gram size = 5. N-grams are generated ONLY for lengths actually demanded by the dictionary (`required_ngram_lengths`), never eagerly.
- Output columns per category: `{Cat}_word_count` (integer), `{Cat}_word_perc` (proportion of n_tokens, 0 when n_tokens == 0). Global: `n_tokens`, `n_types`. Optional per category: `{Cat}_detected_words` (comma-space joined string; option default OFF).
- Column name sanitization identical to the original `enhance.py`: replace spaces with `_`, strip every character not in `[A-Za-z0-9_]`.
- UI language: English (module published internationally; Italian support can be added later via jamovi i18n).
- Every task ends with `git add <files>` + commit. Never commit secrets or build artifacts (`build*/`, `*.jmo` are gitignored).


TASK TEXT
=========
### Task 7: Analysis wiring — yaml definitions and wordcount.b.R

**Files:**
- Modify: `jamovi/0000.yaml` (menu group `Text`, dataset registration happens in Task 8)
- Create: `jamovi/wordcount.a.yaml`, `jamovi/wordcount.r.yaml`, `jamovi/wordcount.u.yaml`
- Create: `R/wordcount.b.R`
- Modify: `DESCRIPTION` if versions/imports need adjusting

**Interfaces:**
- Consumes: `wc_parse_dictionary`, `wc_dictionary_summary`, `wc_analyze_corpus`, chosen input mechanism from Task 6
- Produces: installed, working analysis `Text > Word Count (LIWC-style)` producing a summary table and, when ticked, spreadsheet columns via the dynamic Output element.

Key jamovi facts used here (verified sources):
- Dynamic multi-column Output: `.a.yaml` declares one option `saveResults` with `type: Output`; `.r.yaml` declares the matching element with `items: (0)`; at runtime call `set(keys, titles, descriptions, measureTypes)` once, then `setRowNums(rownames(data))` and `setValues(vector, key=keyName)` per column. Guard with `isNotFilled()`. (dev.jamovi.org/api/output)
- Row mapping MUST use `rownames(data)`, never `1:nrow(data)` (silent corruption with filtered rows).

- [ ] **Step 1: Define options (.a.yaml)**

`jamovi/wordcount.a.yaml`:
```yaml
---
name: wordcount
title: Word Count (LIWC-style)
menuGroup: Text
version: '0.1.0'
jas: '1.2'

options:
    - name: data
      type: Data

    - name: textVar
      title: Text Variable
      type: Variable
      permitted: [id, nominal]

    - name: dictionary
      title: Dictionary (paste TSV)
      type: String
      default: ''

    - name: detectedWords
      title: Include detected words columns
      type: Bool
      default: false

    - name: saveResults
      title: Add results to spreadsheet
      type: Output
```

- [ ] **Step 2: Define results (.r.yaml)**

`jamovi/wordcount.r.yaml`:
```yaml
---
name: wordcount
title: Word Count (LIWC-style)
jrs: '1.1'

items:
    - name: dictSummary
      title: Dictionary Summary
      type: Table
      rows: 0
      columns:
        - name: category
          title: Category
          type: text
        - name: exactTerms
          title: Exact Terms
          type: integer
        - name: wildcardPrefixes
          title: Wildcard Prefixes
          type: integer
        - name: multiWordTerms
          title: Multi-word Terms
          type: integer

    - name: statusNote
      title: Status
      type: Preformatted
      visible: false

    - name: savedResults
      title: Add results to spreadsheet
      type: Output
      items: (0)
      varTitle: '`Word Count result`'
      measureType: continuous
```

- [ ] **Step 3: Define layout (.u.yaml)**

`jamovi/wordcount.u.yaml`:
```yaml
---
title: Word Count (LIWC-style)
name: wordcount
jus: '3.0'
stage: 0
compilerMode: tame
children:
    - type: VariableSupplier
      persistentItems: false
      stretchFactor: 1
      children:
        - type: VariablesListBox
          name: textVar
          maxItemCount: 1
          height: 80
          dropTarget:
            title: Single text variable

    - type: LayoutBox
      margin: large
      children:
        - type: TextBox
          name: dictionary
          format: term
          width: 480
          height: 200
```

NOTE: `height`/`width` on TextBox correspond to whichever multiline mechanism Task 6 validated — substitute the exact element/properties decided there (e.g. CodeBox). Keep the option name `dictionary` regardless.

Below it add:
```yaml
        - type: CheckBox
          name: detectedWords
        - type: CheckBox
          name: saveResults
```

- [ ] **Step 4: Implement the analysis class**

`R/wordcount.b.R`:
```r
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
```

Notes:
- `inherit = wordcountBase` refers to the class jmvtools generates from the yaml files during `jmvtools::install()`; the method name it expects is `.runAnalysis` (generated skeleton shows it — adjust if the generated skeleton in `R/wordcount.h.R` differs, e.g. `.run`).
- If `set()` rejects `(0)`-item outputs at runtime, switch `.r.yaml` to `items: 1` and call `set()` before writing values — verify interactively in jamovi either way.

- [ ] **Step 5: Compile and smoke-test**

Run: `Rscript -e "jmvtools::install()"`
Expected: installs without error.

Manual smoke test (record outcome in commit message or notes):
1. Open jamovi → Data Library or open a small CSV with a text column.
2. Analyses → Text → Word Count (LIWC-style).
3. Select the text variable, paste the Task 5 sample dictionary, tick "Add results to spreadsheet".
4. Confirm: summary table rows appear; spreadsheet gains `n_tokens`, `n_types`, per-category count/perc columns with correct-looking values; toggling detected words adds string columns; changing the dictionary clears stale columns.

Fix whatever surfaces (typical culprits: wrong generated method name, yaml indentation, `permitted` values rejected).

- [ ] **Step 6: Commit**

```bash
git add jamovi/ R/wordcount.b.R DESCRIPTION
git commit -m "feat: wire wordcount analysis with dynamic spreadsheet outputs"
```

---