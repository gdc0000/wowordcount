# LIWC-classic semantics + Lexicon Builder UI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Switch counting to classic LIWC frequency semantics (one full-frequency count per category per token) and add a native Lexicon Builder UI (Array option) with priority over the paste field.

**Architecture:** Delta on the completed wowordcount module. Task A touches the counting core, golden fixtures, and README semantics. Task B adds an Array option (`lexicon`: rows of category + comma-separated terms) parsed by a new `wc_parse_lexicon_rows()` that reuses the existing wildcard/multi-word routing, with `.run()` priority: builder > paste > error.

**Tech Stack:** R (base), jmvtools/jmvcore, testthat, Python stdlib for fixtures.

**Spec:** delta on `docs/superpowers/specs/2026-08-24-wowordcount-design.md`; user rulings in chat 2026-08-25 (dedup per category = 1x; builder + paste coexist, builder priority).

## Global Constraints

- LIWC-classic semantics: every token/ngram occurrence counts (full frequency) toward each matched category, AT MOST ONCE per category per token (exact+wildcard overlap in the same category counts 1x).
- Golden fixtures must be REGENERATED, never hand-edited.
- README must state the divergence from the legacy Streamlit tool (which counted exact matches as distinct types).
- Suite must stay green (FAIL 0) after each task; commits per task.

---

### Task A: LIWC-classic counting semantics

**Files:**
- Modify: `R/counter.R` (exact hits: +f; combine exact+wildcard per category dedup)
- Modify: `tests/testthat/test-counter.R` (updated expectations + overlap dedup test)
- Modify: `tools/generate_golden.py` (same semantics) + regenerate `inst/tests/golden/expected.json`
- Modify: `README.md` (Counting semantics section rewrite)

**Interfaces:**
- Consumes: existing `wc_prepare_config`, `wc_count_document` signatures (unchanged)
- Produces: `wc_count_document` with LIWC-classic semantics; regenerated fixtures

- [ ] Update counter loops: `cats_hit <- unique(c(exact_cats, wild_cats))`; `counts[cat] += f` once per category; same for ngram loop; detected collection per unique category hit; update file-top comment
- [ ] Update tests: not/not/never -> 3; kind of x2 -> 2; yes/yes -> 2/2; dog+do* same cat -> 3 (dog 2 + dot 1); c*/ca* overlap same cat -> cat 1 + dog 1 = 2 (dedup)
- [ ] Patch generator: per token/ngram, per category: if exact OR any prefix matches -> += f once; regenerate expected.json via `python tools\generate_golden.py`
- [ ] README: rewrite Counting semantics (LIWC classic; divergence note vs legacy Streamlit)
- [ ] Run suite -> FAIL 0; commit "feat: classic LIWC frequency semantics with per-category dedup"

### Task B: Lexicon Builder UI

**Files:**
- Modify: `jamovi/wordcount.a.yaml` (option `lexicon`, type Array, template Group: category String + terms String)
- Modify: `jamovi/wordcount.u.yaml` (ListBox bound to lexicon; reference jmv regression refLevels u.yaml for exact binding syntax)
- Modify: `R/dictionary.R` (`wc_parse_lexicon_rows(entries)` -> wcdict; refactor shared routing helper)
- Modify: `R/wordcount.b.R` (priority: lexicon rows > paste > clear error)
- Modify: `tests/testthat/test-dictionary.R` (builder tests)
- Modify: `README.md` (Building a lexicon in the UI section)

**Interfaces:**
- Consumes: existing bucket routing in dictionary.R
- Produces: `wc_parse_lexicon_rows(entries)` where entries is a list of list(category=, terms=comma-separated string) -> wcdict

- [ ] a.yaml: lexicon Array option with template {category: String title Category, terms: String title "Terms (comma-separated)"}
- [ ] u.yaml: ListBox for lexicon (copy binding pattern from jmv::regression refLevels u.yaml fetched from GitHub raw)
- [ ] dictionary.R: wc_parse_lexicon_rows; split terms on ","; trim; route wildcard/multi via shared helper; empty rows skipped; duplicate category rows merged (union)
- [ ] b.R: lexicon priority logic + updated empty-input error message mentioning both paths
- [ ] Tests: builder parse (categories, wildcard, multi-word, dedup, empty-terms row skipped); suite FAIL 0
- [ ] README section; jmvtools::install(home='C:/Program Files/jamovi 2.6.26.0') succeeds; commit "feat: lexicon builder UI with priority over paste"
- [ ] GUI smoke with human partner (builder rows, run, spreadsheet columns)
