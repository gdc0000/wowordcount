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
### Task 6: Spike — multiline dictionary input control

The official TextBox documentation lists no multiline property (issue jamovi/jamovi#1820 unresolved). This task decides the input mechanism empirically before UI wiring.

**Files:**
- Modify: `jamovi/wordcount.a.yaml`, `jamovi/wordcount.u.yaml` (temporary experiments)
- Create: `docs/superpowers/notes/2026-08-24-multiline-input-decision.md`

**Interfaces:**
- Consumes: scaffolded module from Task 1
- Produces: a documented, compiling decision recorded in the notes file; `self$options$dictionary` guaranteed to deliver the pasted TSV string with newlines intact.

- [ ] **Step 1: Candidate A — plain TextBox paste**

Set in `wordcount.a.yaml`:
```yaml
- name: dictionary
  title: Dictionary (paste TSV)
  type: String
  default: ''
```
and reference a plain `TextBox` in `wordcount.u.yaml`. Install, open jamovi, paste the sample dictionary (with real newlines) from clipboard into the box. Verify what arrives in R by temporarily adding to `.run()`:
```r
writeLines(self$options$dictionary, file.path(tempdir(), "dict_dump.txt"))
```
Inspect the dump: are `\n` preserved? Record result in the notes file.

- [ ] **Step 2: Candidate B — CodeBox element (as used by the Rj module)**

If Candidate A strips newlines, try the `CodeBox` control (multiline editor shipped with the compiler, used by the Rj "R syntax" module):
```yaml
- type: CodeBox
  name: dictionary
  format: term
```
Re-install and repeat the dump check. Record result.

If CodeBox is not recognized by the compiler, search the installed jamovi modules directory (`%LOCALAPPDATA%/jamovi/modules` or the app's `modules/` dir) for `CodeBox` occurrences in other modules' compiled assets to confirm the correct spelling before giving up on B.

- [ ] **Step 3: Candidate C — documented fallback (single-line flat format)**

Only if both A and B fail: accept a single-line format where terms are separated by `;` and fields by `,` (`very:Int; not:Neg; kind of:Int`), implemented in `dictionary.R` behind the same `wc_parse_dictionary` interface (detect absence of `\n` + presence of `;`). Record the deviation from spec in the notes file and inform the maintainer that full TSV paste requires upstream multiline support.

- [ ] **Step 4: Record decision and revert experiments**

Write `docs/superpowers/notes/2026-08-24-multiline-input-decision.md` with: candidates tried, observed behavior, chosen mechanism, evidence (dump excerpts). Revert the temporary dump code from `.run()`.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/notes/ jamovi/
git commit -m "chore: decide multiline dictionary input mechanism"
```

---