#!/usr/bin/env python3
"""Regenerate inst/tests/golden/expected.json from committed inputs.

Standalone replication of app/text_analysis.py core logic from
gdc0000/WordCount (MIT). Stdlib only: re, collections, json, pathlib.

Controller ruling R8 amendment (2026-08-24): counting follows upstream
asymmetric semantics — EXACT term hits add +1 per distinct type present,
WILDCARD prefix hits add the full document frequency (+f). The originally
copied snippet added full frequency for exact hits too; exact vs wildcard
counting is split accordingly (and detected lists de-duplicated) so the
fixture mirrors app/text_analysis.py / R counter.R.
"""
import json
import re
from collections import Counter
from pathlib import Path

MAX_NGRAM_SIZE = 5
TOKEN_CLEAN_RE = re.compile(r"[^\w\s']")

HERE = Path(__file__).resolve().parent.parent
GOLDEN = HERE / "inst" / "tests" / "golden"


def tokenize(document):
    clean = TOKEN_CLEAN_RE.sub(" ", str(document).lower())
    return [t for t in clean.split() if t]


def ngrams_of(tokens, lengths):
    out = []
    n_tokens = len(tokens)
    for n in lengths:
        if n > n_tokens:
            continue
        out.extend(
            " ".join(tokens[i:i + n]) for i in range(n_tokens - n + 1))
    return out


def main():
    dic_lines = GOLDEN.joinpath("dictionary.tsv").read_text(
        encoding="utf-8").splitlines()
    rows = [ln.split("\t") for ln in dic_lines if ln.strip()]
    header = [h.strip() for h in rows[0]]
    assert header[0].lower() == "dicterm"
    categories = header[1:]

    exact_single = {c: [] for c in categories}
    wildcard_single = {c: [] for c in categories}
    exact_multi = {c: [] for c in categories}
    wildcard_multi = {c: [] for c in categories}

    for row in rows[1:]:
        padded = row + [""] * (len(header) - len(row))
        term = padded[0].strip()
        if not term:
            continue
        for idx, cat in enumerate(categories, start=1):
            cell = padded[idx].strip().upper()
            if cell != "X":
                continue
            is_wild = term.endswith("*")
            clean = term[:-1].strip() if is_wild else term.strip()
            multi = len(clean.split()) > 1
            bucket = (
                (wildcard_multi if multi else wildcard_single) if is_wild
                else (exact_multi if multi else exact_single)
            )[cat]
            if clean not in bucket:
                bucket.append(clean)

    required = set()
    for cat in categories:
        for t in exact_multi[cat]:
            required.add(len(t.split()))
        for p in wildcard_multi[cat]:
            k = len(p.split())
            required.update(range(max(k, 2), MAX_NGRAM_SIZE + 1))

    docs = GOLDEN.joinpath("corpus.txt").read_text(
        encoding="utf-8").splitlines()
    expected = []
    for doc in docs:
        tokens = tokenize(doc)
        rec = {
            "n_tokens": len(tokens),
            "n_types": len(set(tokens)),
        }
        counts = {c: 0 for c in categories}
        detected = {c: [] for c in categories}
        freq = Counter(tokens)
        for tok, f in freq.items():
            # R8: exact hits add +1 per distinct type present.
            for cat in categories:
                if tok in exact_single[cat]:
                    counts[cat] += 1
                    detected[cat].append(tok)
            # R8: wildcard prefix hits add full frequency +f, once per
            # category even when several prefixes match.
            for cat in categories:
                if any(p and tok.startswith(p)
                       for p in wildcard_single[cat]):
                    counts[cat] += f
                    detected[cat].append(tok)
        if required and len(tokens) >= 2:
            ng = Counter(ngrams_of(tokens, sorted(required)))
            for gram, f in ng.items():
                # R8: exact multi-word hits add +1 per distinct type.
                for cat in categories:
                    if gram in exact_multi[cat]:
                        counts[cat] += 1
                        detected[cat].append(gram)
                # R8: wildcard multi-word prefixes add full frequency +f.
                for cat in categories:
                    if any(p and gram.startswith(p)
                           for p in wildcard_multi[cat]):
                        counts[cat] += f
                        detected[cat].append(gram)
        rec["counts"] = counts
        # Dedup mirrors wc_count_document, which records each matched term
        # once per category even when both an exact and a wildcard rule hit.
        rec["detected"] = {c: sorted(set(v)) for c, v in detected.items()}
        expected.append(rec)

    GOLDEN.joinpath("expected.json").write_text(
        json.dumps(expected, indent=1, ensure_ascii=False),
        encoding="utf-8")
    print(f"wrote {len(expected)} records")


if __name__ == "__main__":
    main()
