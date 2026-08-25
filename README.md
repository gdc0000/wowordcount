# wowordcount

LIWC-style word counting for [jamovi](https://www.jamovi.org). Load a text
variable, paste your own dictionary, and get per-document word counts and
percentages for each dictionary category — the classic Linguistic Inquiry and
Word Count workflow, without sending your data anywhere.

## What it does

`wowordcount` counts words and word patterns in documents using
**user-supplied wordlists** (dictionaries), in the style of LIWC. It is a
native jamovi port of the WordCount application: base R only, no Python
runtime required at analysis time, and comfortable on an 8 GB laptop.

For each document it reports the token/type totals plus one word count and one
percentage per dictionary category, with optional columns listing exactly
which words (and multi-word expressions) were detected.

## Install

Once published, install from the jamovi library via jamovi's built-in module
gallery. Meanwhile you can sideload the module from source: with jamovi and
the `jmvtools` R package installed, run from the module root:

```r
jmvtools::install()
```

## Dictionary format

Dictionaries are pasted as tab-separated text (TSV). The header row starts
with `DicTerm`, followed by one column per category; each row defines a term.
The bundled example uses three categories:

```
DicTerm	Intensifiers	Negations	Modal_Expressions
very	X		
extremely	X		
not		X	
never		X	
can*			X
might*			X
```

Fields are separated by **TAB** characters (they render as spaces above).

Rules:

- A cell containing `X` (case-insensitive, surrounding spaces ignored) marks
  membership of that term in the category.
- A trailing `*` marks a **prefix wildcard**: `can*` matches `can`, `cannot`,
  `candle`, and so on.
- Terms may contain internal spaces (multi-word terms, matched against
  n-grams up to length 5).
- Category names become output column names after sanitization: spaces become
  `_` and every character outside `[A-Za-z0-9_]` is stripped (e.g.
  `Modal_Expressions` stays as-is).

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

> This differs from the legacy Streamlit WordCount app, which counted exact
> matches once per distinct word type; results are NOT comparable between
> the two tools.

## Outputs

With results saved to the spreadsheet, each row corresponds to one document:

| Column | Meaning |
| --- | --- |
| `n_tokens` | Number of tokens in the document |
| `n_types` | Number of distinct tokens |
| `{Cat}_word_count` | Integer count of dictionary hits for category `{Cat}` |
| `{Cat}_word_perc` | `{Cat}_word_count / n_tokens`; 0 when the document has no tokens |
| `{Cat}_detected_words` | Comma-space separated list of matched words/n-grams (optional, off by default) |

## Performance

Documents are streamed one at a time and n-grams are generated only for the
lengths actually demanded by the dictionary (never eagerly, maximum length 5),
so memory use stays low even for large corpora. Everything runs in base R;
there is no Python dependency at analysis time.

A live progress bar and incremental feedback are planned; current builds
report a summary line after completion.

## Parity

Numeric results (tokenization, n-gram rule, counting semantics) were verified
against a stdlib-only replica of the original counting logic
(`tools/generate_golden.py`, itself a verbatim port kept in-tree); its outputs
are bundled as golden fixtures with the module's test suite.

## Try it

The module ships with `demo_texts`, a small set of fictional English/Italian
social-media-style posts available in the Data Library — paste the example
dictionary above, pick `text` as the Text Variable, and run.

## License

MIT — see the package `DESCRIPTION`.

## Citation

Di Cicco, G. (2026). *wowordcount: LIWC-style Word Count Analyses* (Version
0.1.0) [jamovi module].
