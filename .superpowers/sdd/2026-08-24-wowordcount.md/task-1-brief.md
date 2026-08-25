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
### Task 1: Environment check and module scaffold

**Files:**
- Create: `.gitignore`
- Create: `wowordcount/` module scaffold (moved to repo root afterwards)
- Modify: repo root becomes the R package root

**Interfaces:**
- Consumes: nothing
- Produces: a compiling empty module `wowordcount` installed into local jamovi; analysis stub named `wordcount`; helper scripts runnable via `Rscript`.

- [ ] **Step 1: Verify toolchain**

Run:
```powershell
Get-Command Rscript | Select-Object Source
Rscript -e "cat(as.character(getRversion()))"
Rscript -e "cat('jmvtools:', requireNamespace('jmvtools', quietly=TRUE), '\n')"
Rscript -e "cat('testthat:', requireNamespace('testthat', quietly=TRUE), '\n')"
python --version
```
Expected: R >= 4.3 present, jmvtools TRUE (install with `install.packages('jmvtools')` if FALSE — it needs Node.js; verify with `node -v`), testthat TRUE (install from CRAN if missing), Python 3.x present.

- [ ] **Step 2: Create the module**

Run:
```powershell
Rscript -e "jmvtools::create('wowordcount')"
```
Expected: folder `wowordcount/` created under repo root containing `DESCRIPTION`, `NAMESPACE`, `R/`, `jamovi/`.

- [ ] **Step 3: Move package root to repo root**

The repo root must be the package root (like the gamlj repo), keeping `docs/` alongside.

```powershell
Move-Item wowordcount\DESCRIPTION .
Move-Item wowordcount\NAMESPACE .
Move-Item wowordcount\R .
Move-Item wowordcount\jamovi .
Move-Item wowordcount\.Rbuildignore . -ErrorAction SilentlyContinue
Remove-Item wowordcount -Recurse -Force
```

Edit `jamovi/0000.yaml`: set `title: wowordcount`, `name: wowordcount`, keep generated `version`, `jms`, authors placeholder `Gabriele Di Cicco`, and change the analysis entry to `menuGroup: Text` (so it appears under a "Text" menu).

Edit `DESCRIPTION`: `Package: wowordcount`, `Title: LIWC-style Word Count Analyses`, `Author/maintainer: Gabriele Di Cicco`, `Depends: R (>= 4.2)`, `Imports: jmvcore (>= 2.4), methods`, `License: MIT` plus `Encoding: UTF-8`.

- [ ] **Step 4: Add .gitignore**

Create `.gitignore` at repo root:
```
# jamovi
/build/
/build-*/
*.jmo
# R
.Rhistory
.RData
*.tar.gz
# python
__pycache__/
```

- [ ] **Step 5: Compile and install the empty module**

Run:
```powershell
Rscript -e "jmvtools::install()"
```
Expected: `Successfully installed wowordcount into jamovi` (warnings about empty analysis body are fine).

- [ ] **Step 6: Commit**

```bash
git add .gitignore DESCRIPTION NAMESPACE R jamovi
git commit -m "chore: scaffold wowordcount jamovi module"
```

---