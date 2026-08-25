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
### Task 8: Example dataset, README, release hygiene

**Files:**
- Create: `data/demo_texts.csv`
- Modify: `jamovi/0000.yaml` (register dataset), `README.md`, `man/` (optional), `DESCRIPTION` (version bump if needed)
- Create: `.github/workflows/R-CMD-check.yaml` optional CI — SKIP unless requested; do not create proactively.

**Interfaces:**
- Consumes: finished analysis from Task 7
- Produces: module ready for sharing; Data Library entry `demo_texts`; README documenting the dictionary format with the user's own example (Intensifiers/Negations/Modal_Expressions).

- [ ] **Step 1: Bundle demo dataset**

Create `data/demo_texts.csv` (small, no PII — fictional social-media posts mixing English/Italian, 10–15 rows, one `post_id` column + one `text` column).

Register in `jamovi/0000.yaml`:
```yaml
datasets:
    - name: demo_texts
      path: demo_texts.csv
      description: Fictional short texts for trying the Word Count analysis
      tags:
        - wordcount
```

- [ ] **Step 2: Write README.md**

Sections: What it does (LIWC-style counting from user-supplied wordlists); Install (jamovi library once published; sideload via `jmvtools::install()` meanwhile); Dictionary format — embed EXACTLY this example as a fenced block (tabs rendered as spaces in markdown is acceptable, note says "fields separated by TAB"):
```
DicTerm	Intensifiers	Negations	Modal_Expressions
very	X
extremely	X
not		X
never		X
can*			X
```
plus rules: `X` marks membership, `*` = prefix wildcard, spaces allowed inside terms; Outputs table explaining every produced column; Performance note (streams documents, generates only needed n-grams); Parity statement (verified against the Streamlit WordCount via golden tests); License MIT; Citation/orcid.

- [ ] **Step 3: Full verification pass**

```powershell
Rscript -e "testthat::test_local('.')"
Rscript -e "jmvtools::install()"
```
Expected: all tests PASS; install succeeds. Open jamovi once more, run the analysis on `demo_texts` end-to-end with save-results ticked and detected-words off/on.

- [ ] **Step 4: Commit**

```bash
git add data/ jamovi/0000.yaml README.md
git commit -m "docs: readme, demo dataset, module metadata"
```

---