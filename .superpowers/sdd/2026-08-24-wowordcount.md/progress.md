# SDD ledger — plan: docs/superpowers/plans/2026-08-24-wowordcount.md


## Pre-flight scan
| Pair | Produces/Consumes | Finding |
|---|---|---|
| T2->T4,T5 | wc_tokenize/wc_generate_ngrams sigs | ok |
| T3->T4,T5,T7 | wcdict list structure | ok |
| T4->T5,T7 | wc_count_document(cfg) sig | ok |
| T5->T7 | df colnames = Output keys | ok |
| T6->T7 | multiline mechanism choice | T7 already mandates substitution note |
| T2 self | test line 'brown fox' %in% ng[ng==...] weak | valid-but-tautological assertion; deferred minor |
| T4 self | seq(max(k,2L),5) descending when k>5 words | PLAN DEFECT -> Ruling R3 |
| T5 self | corpus.txt authored by implementer | edge cases enumerated; acceptable |
| T7 self | .runAnalysis vs generated skeleton name | fallback instruction present |

## Rulings
R1: branch feat-wowordcount instead of git worktree — fresh empty repo, branch isolation suffices. Cost if wrong: none, trivial merge.
R2: harness task tool exposes no model field — single default model for all subagents; compensated with precise briefs + mandatory per-task review gates. Cost: higher token spend than tiered selection.
R3: Task 4 plan code seq(max(k, 2L), wc_max_ngram_size) yields descending values for terms longer than 5 words. Mandate fix at implementation: only add lengths when k <= wc_max_ngram_size (mirrors Python ange() which is empty there); same guard for exact_multi term lengths. Cost if wrong: none — matches upstream semantics exactly.

BASE before Task 1: 9a6e7e4

## Notes
- Briefs were initially written empty (PS 5.1 String.Split multi-char bug); regenerated correctly for all 8 tasks. Task 1 implementer worked from the plan doc directly — equivalent text.
- jmvtools modern version: create() does NOT generate jamovi/0000.yaml nor R/*.b.R; both appear on first successful compile. addAnalysis() produced wordcount.a.yaml/.r.yaml stubs. menuGroup: Text set in .a.yaml.
- ENV: R 4.5.1 at C:\Program Files\R\R-4.5.1\bin\x64\Rscript.exe (NOT on PATH — pass full path to future implementers); Node 22.16.0; Python 3.10.11; jamovi desktop NOT installed -> jmvtools::install()/compile fails with 'jamovi could not be found!'. Tasks 2-5 (pure R + testthat) unaffected. Tasks 6-7 need compile -> will ask human partner to install jamovi before those tasks.
Task 1: complete (commits 9a6e7e4..d6abdbb, review clean) | deferred minors: Authors@R lacks email (CRAN only), .r.yaml template stub (replaced by Task 7), R/ empty until Task 2
Ruling R4: Task 2 brief contained tautological assertion (pre-flagged in pre-flight). Implementer replaced it with absence-of-unrequested-trigrams checks ('the quick brown','quick brown fox' not in ng for lengths 2,4) — matches Python ngrams_of exactly. Correction accepted; cost if wrong: none, strictly stronger than original.
Task 2: fix round 1/5 (2 addressed, 0 open — NBSP split parity (*UCP)\s+, dead assertion removed; commit 41ec9c8..4386b1c)
Task 2: complete (commits d6abdbb..4386b1c, review clean after scoped re-review; GREEN 14 PASS re-verified by controller)
Deferred minors T2: \x1c-\x1f whitespace nuance (irrelevant for prose corpora); Authors@R email n/a; golden fixture should not rely on mojibake-prone editors
Task 3: complete (commits 4386b1c..5ff691a, review clean; GREEN 30 PASS re-verified by controller)
Ruling R5 (carried into Task 4 dispatch): bare '*' term yields empty-string prefix; Python upstream EXCLUDES empty prefixes ('if prefix:' guards in _prepare_analysis_config) — wc_prepare_config MUST skip empty prefixes for both tries, else root-terminal trie matches every token. Cost if wrong: catastrophic overcounting.
Deferred minors T3: duplicate category names collide in named lists (pathological); rbind O(n^2) on huge dictionaries (fine at target scale)
Task 4: implementer DONE_WITH_CONCERNS before review — two upstream-parity conflicts verified by executing verbatim upstream code.
Ruling R6: UPSTREAM SEMANTICS ARE BINDING (spec parity goal outweighs assumed uniform counting): exact single/multi terms contribute +1 per DISTINCT type present in the document; wildcard single/multi prefixes contribute FULL FREQUENCY. This asymmetry is exactly what app/text_analysis.py does (Counter-keys loop vs items() loop) and what the user's published research relies on. Golden fixtures replicate upstream automatically. Cost if wrong: results differ from the Streamlit app the user has used for years — worse than any theoretical purity gain.
Ruling R7: brief test 'multi-word wildcard prefix matches' expected 1 but upstream yields 5 on that input (all n-grams of lengths required by the dictionary that string-prefix-match 'might be', incl. 'might bee'). Test corrected to expect 5.
Task 4: complete (commits 5ff691a..db55893, review clean; reviewer independently re-ran suite FAIL 0 PASS 46)
Ruling R8 (for Task 5): the plan's tools/generate_golden.py snippet sums FULL FREQUENCY for exact terms too — that contradicts ruled upstream semantics R6. Mandated amendment: generator must add +1 per distinct type for exact hits and +frequency for wildcard hits (tokens and n-grams both), replicating app/text_analysis.py exactly.
Deferred minors T4: req_len computed for empty prefix path (unreachable via parser); c()-growth loops quadratic-ish at huge dict scale; isEmptyTrie lacks wc_ prefix
Ruling R9 (pre-review): Task 5 golden dictionary.tsv interior-tab drift vs plan intent changes which category some terms land in — harmless because BOTH parsers consume the same committed file, so parity holds; fixture cosmetics deferred to Task 8 README work.
Task 5: complete (commits db55893..c9aead9, review clean; reviewer regenerated expected.json SHA-identical from committed script+inputs; independent suite run FAIL 0 PASS 161)
Ruling R10: Task 6 empirical candidates impossible without jamovi desktop (not installed). Static resolution performed instead: local jamovi-compiler source shows the compiler does NOT validate UI element vocabulary (client renders); TextArea/CodeBox absent from compiler tree; plain TextBox is the only documented text control. Decision: wire Task 7 with plain TextBox (multiline paste behavior verified at first GUI smoke); fallback to brief's Candidate C flat-format only if paste strips newlines. Task 6 marked complete-by-static-analysis with notes file still required.
Deferred minors T5: generator write_text newline pinning; expected.json trailing newline; fixture interior-tab label quirk (patch recommended during Task 8); expect_setequal info= dropped
Task 6: complete (static-analysis path per R10; notes committed; runtime gate deferred to Task 7 smoke)
Task 7: complete (commits c9aead9..65df9bb, review clean)
PENDING RUNTIME GATES (need jamovi desktop installed): generated-skeleton method name check (.runAnalysis vs .run), TextBox multiline paste gate (fallback Candidate C), Output items:(0)+set() runtime check, full GUI smoke of Task 7 Step 5
Task 8: complete (commits 65df9bb..c256c6f, review clean)
Final whole-branch review: CHANGES REQUIRED -> fix wave 3c9694b..7c74131 (F1 nominaltext, F2 per-prefix wildcard parity, F3 R6 import, F4 README honesty+future-work, F5 zero-hit note) -> scoped re-review ALL ADDRESSED, no new breakage, suite FAIL 0 PASS 162
Ruling R11: final-fix test dict amended with 'dog\tX' to make the overlap assertion coherent (controller-sanctioned)
Ruling R12: wordcount.a.yaml staged into commit 1 to match its message (controller-sanctioned)
STATUS: all tasks complete; PENDING runtime gates need jamovi desktop installed (skeleton method name, TextBox multiline paste gate w/ Candidate C fallback, Output items:(0) runtime, GUI smoke)
Ruling R13 (smoke-time fixes by controller, documented): permitted enum for jas 1.2 is numeric|factor|id only (final-review 'nominaltext' finding was wrong for this compiler); u.yaml height must be enum + dropTarget not allowed on VariablesListBox; hand-authored 0000.yaml needs explicit analyses: block; base-class convention is private .run (renamed from .runAnalysis); PS5.1 Set-Content UTF8 injects BOM breaking R parse — stripped with WriteAllText UTF8Encoding(false).
Commits ef1f665, 33fc705. jmvtools::install(home='C:/Program Files/jamovi 2.6.26.0') -> Module installed successfully. Suite FAIL 0 PASS 162.
Ruling R14 (GUI smoke finding): jamovi client renders TextBox single-line tiny regardless of width/height — multiline TSV paste impossible (issue #1820 confirmed live). Activating pre-designed Candidate C: flat single-line format 'term:Cat1,Cat2; term2:Cat1' auto-detected (no newline + contains ';') in wc_parse_dictionary; TSV multiline remains accepted when newlines present. UI attempt: move TextBox into own LayoutBox for full width.
## Delta plan: docs/superpowers/plans/2026-08-25-liwc-classic-builder.md (user rulings 2026-08-25: dedup per category 1x; builder+paste coexist, builder priority)
Delta Task A: complete (commit 20f7bf0, review clean, suite FAIL 0 PASS 172; reviewer regenerated fixtures independently — zero delta). Deferred: README 'verbatim port' wording folds into Task B docs.
Delta Task B: complete (commits bfd1ef3..55456bf after fix round 1; review clean; suite FAIL 0 PASS 192; install ok)
Deferred: positional callers of wordcount() affected by lexicon param insertion (jamovi passes named — safe); nzchar(NA) theoretical
