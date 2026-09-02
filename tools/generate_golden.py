#!/usr/bin/env python3
"""Regenerate inst/tests/golden/expected.json from committed inputs.

Standalone replica of the wowordcount R counter (base-R module logic).
Stdlib only: re, collections, json, pathlib.

Counting follows CLASSIC LIWC frequency semantics (user ruling 2026-08-25,
superseding the 2026-08-24 upstream-parity amendment): every token/n-gram
occurrence counts with its full document frequency (+f) toward each
category it matches, AT MOST ONCE per category per token — an exact term
and a wildcard prefix (or several overlapping prefixes) hitting the same
category count a single +f.
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
            # Classic LIWC: one full-frequency count per matched category,
            # regardless of how many rules (exact/wildcard/prefixes) hit it.
            for cat in categories:
                exact_hit = tok in exact_single[cat]
                wild_hit = any(p and tok.startswith(p)
                               for p in wildcard_single[cat])
                if exact_hit or wild_hit:
                    counts[cat] += f
                    detected[cat].append(tok)
        if required and len(tokens) >= 2:
            ng = Counter(ngrams_of(tokens, sorted(required)))
            for gram, f in ng.items():
                # Classic LIWC dedup per category, as for single tokens.
                for cat in categories:
                    exact_hit = gram in exact_multi[cat]
                    wild_hit = any(p and gram.startswith(p)
                                   for p in wildcard_multi[cat])
                    if exact_hit or wild_hit:
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
