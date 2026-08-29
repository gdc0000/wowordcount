# wowordcount

LIWC-style word counting for [jamovi](https://www.jamovi.org). Load a text
variable, build your own dictionary in the app, and get per-document word
counts and percentages for each dictionary category — the classic Linguistic
Inquiry and Word Count workflow.

Everything runs locally in jamovi: base R only, no external services, no
Python runtime.

## Installation

Once published, install from the jamovi library via jamovi's built-in module
gallery. To install a development build from source instead, with jamovi and
the `jmvtools` R package available, run from the module root:

```r
jmvtools::install()
```

## Quick start

The module bundles `sentences.csv`, a small set of eight fictional documents.
After installing the module, open jamovi's **Open > Data Library** and select
**wowordcount > sentences**: the `text` variable is pre-loaded, so you can run
the analysis with the default lexicon right away.

In your own data, any text variable can be analysed — for example a column of
interview responses, tweets, or document abstracts.

## Building your dictionary

Dictionaries are entered directly in the analysis options using the
**lexicon builder**: one category per row with its terms as a comma-separated
list. The default lexicon provides a working example:

| Category | Terms (comma-separated) |
| --- | --- |
| Positivity | very, good, happy, amazing |
| Negations | not, non, never, no, niente |
| Modality | can*, could*, might*, may*, should* |

Rules:

- A trailing `*` marks a **prefix wildcard**: `can*` matches `can`, `cannot`,
  `candle`, and so on.
- Terms may contain internal spaces (multi-word terms, matched against
  n-grams up to length 5).
- Category names become output column names after sanitization: spaces
  become `_` and every character outside `[A-Za-z0-9_]` is stripped (e.g.
  `Social Words!` becomes `Social_Words`).

Click **Add category** for each category, then fill in its terms as a
comma-separated list. Duplicate rows for the same category are merged,
and rows without terms are ignored.

## Outputs

For each document the analysis reports the token and type totals, plus one
word count and one percentage per dictionary category. Unlike the original
LIWC, which does not report which words matched, `wowordcount` can also list
exactly which words and multi-word expressions were detected in each
document — useful for auditing how the dictionary behaves on your data.

Tick **Append results to the data set** under the collapsed **Save** section
(like EFA/PCA factor scores) and run: the per-document columns are appended
directly to your spreadsheet, one row per document:

| Column | Meaning |
| --- | --- |
| `n_tokens` | Number of tokens in the document |
| `n_types` | Number of distinct tokens |
| `{Cat}_word_count` | Integer count of dictionary hits for category `{Cat}` |
| `{Cat}_word_perc` | `{Cat}_word_count / n_tokens`; 0 when the document has no tokens |
| `{Cat}_detected_words` | Comma-space separated list of matched words/n-grams (optional, off by default) |

## Counting semantics

Counting follows **classic LIWC frequency semantics**:

- Every token/n-gram **occurrence** counts with its full document frequency
  toward each category it matches. Example: `"not not never"` adds **3** to
  a negation category containing `not` and `never`.
- **Wildcard prefix** terms (`can*`) match every token starting with the
  prefix; each matching occurrence counts once per category.
- A term that matches a category in several ways — listed exactly *and*
  reachable through a wildcard, or through two overlapping prefixes —
  counts **once per category** per occurrence (per-category dedup).

Numeric output is covered by an automated test suite, including golden
fixtures verified against an independent implementation of the same
semantics.

## License

GPL (>= 2) — see the package `DESCRIPTION` and the `LICENSE` file.

## Citation

Di Cicco, G. (2026). *wowordcount: LIWC-style Word Count Analyses* (Version
1.0.0) [jamovi module].

## AI full disclosure

- This software is developed with **strong assistance from GLM-5.3-Flash** and with human leading on ideas, testing, and debugging.
