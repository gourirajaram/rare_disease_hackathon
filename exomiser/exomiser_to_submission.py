#!/usr/bin/env python3
"""
Convert Exomiser *.variants.tsv results into the Track 1 submission CSV.

Usage:
    python3 exomiser_to_submission.py RESULTS_DIR submission.csv [--top 5]

Assumes each Exomiser run used outputFileName = proband ID
(e.g. PROBAND01 -> PROBAND01.variants.tsv).

Each output row = one candidate diagnosis (one gene + inheritance mode):
  - single variant (dominant / hom-alt / X-linked) -> chrom_1..alt_1 only
  - compound heterozygous pair                      -> chrom_1..alt_1 + chrom_2..alt_2
epcr = Exomiser gene combined score (0-1), used as a proxy for probability.
"""
import argparse
import csv
import glob
import os
import re
from collections import OrderedDict

OUT_COLS = ["proband_id", "chrom_1", "pos_1", "ref_1", "alt_1",
            "chrom_2", "pos_2", "ref_2", "alt_2", "epcr", "finding_type", "notes"]


def chrom(c):
    c = str(c).strip()
    if c.lower().startswith("chr"):
        c = c[3:]
    if c in ("MT", "M"):
        c = "M"
    return "chr" + c


def proband_from_path(path):
    name = os.path.basename(path)
    name = re.sub(r"\.variants\.tsv$", "", name)
    # older Exomiser versions write one file per MOI: NAME_AD.variants.tsv
    name = re.sub(r"_(AD|AR|XD|XR|MT|ANY)$", "", name)
    return name


# accept alternative column names across Exomiser versions
ALIASES = {
    "CONTIG": ["CONTIG", "CHROM", "CHR", "CHROMOSOME"],
    "START": ["START", "POS", "POSITION"],
    "REF": ["REF"],
    "ALT": ["ALT"],
    "GENE_SYMBOL": ["GENE_SYMBOL", "GENE", "SYMBOL"],
    "MOI": ["MOI", "MODE_OF_INHERITANCE"],
    "EXOMISER_GENE_COMBINED_SCORE": ["EXOMISER_GENE_COMBINED_SCORE", "COMBINED_SCORE", "GENE_COMBINED_SCORE"],
    "EXOMISER_VARIANT_SCORE": ["EXOMISER_VARIANT_SCORE", "VARIANT_SCORE"],
    "CONTRIBUTING_VARIANT": ["CONTRIBUTING_VARIANT", "CONTRIBUTING"],
    "HGVS": ["HGVS"],
    "EXOMISER_ACMG_CLASSIFICATION": ["EXOMISER_ACMG_CLASSIFICATION", "ACMG_CLASSIFICATION"],
}
REQUIRED = ["CONTIG", "START", "REF", "ALT", "GENE_SYMBOL", "EXOMISER_GENE_COMBINED_SCORE"]


def read_rows(path):
    with open(path, newline="") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        cols = [f.lstrip("#").strip() for f in reader.fieldnames]
        upper = {c.upper(): c for c in cols}
        mapping = {}
        for canon, alts in ALIASES.items():
            for a in alts:
                if a in upper:
                    mapping[canon] = upper[a]
                    break
        missing = [c for c in REQUIRED if c not in mapping]
        if missing:
            raise SystemExit(f"{path}: missing columns {missing}.\nColumns found: {cols}")
        reader.fieldnames = cols
        rows = []
        for r in reader:
            rows.append({canon: r.get(src, "") for canon, src in mapping.items()})
        if "CONTRIBUTING_VARIANT" not in mapping:
            # no flag column: treat every row as contributing
            for r in rows:
                r["CONTRIBUTING_VARIANT"] = "1"
        return rows


def fnum(x, default=0.0):
    try:
        return float(x)
    except (TypeError, ValueError):
        return default


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("results_dir")
    ap.add_argument("out_csv")
    ap.add_argument("--top", type=int, default=5,
                    help="max candidate diagnoses per proband (default 5)")
    ap.add_argument("--min-score", type=float, default=0.0,
                    help="drop candidates with combined score below this")
    args = ap.parse_args()

    files = sorted(glob.glob(os.path.join(args.results_dir, "*.variants.tsv")))
    if not files:
        raise SystemExit(f"No *.variants.tsv files found in {args.results_dir}")

    by_proband = OrderedDict()
    for f in files:
        by_proband.setdefault(proband_from_path(f), []).extend(read_rows(f))

    out = []
    for pid, rows in by_proband.items():
        # keep only variants Exomiser says contribute to the gene score
        contrib = [r for r in rows if str(r.get("CONTRIBUTING_VARIANT", "")).strip() in ("1", "true", "True")]

        # group into candidate diagnoses: gene + inheritance mode
        cands = OrderedDict()
        for r in contrib:
            key = (r.get("GENE_SYMBOL", ""), r.get("MOI", ""))
            cands.setdefault(key, []).append(r)

        ranked = sorted(cands.items(),
                        key=lambda kv: -fnum(kv[1][0].get("EXOMISER_GENE_COMBINED_SCORE")))

        seen = set()
        n = 0
        for (gene, moi), vars_ in ranked:
            score = fnum(vars_[0].get("EXOMISER_GENE_COMBINED_SCORE"))
            if score < args.min_score:
                continue
            vars_ = sorted(vars_, key=lambda r: -fnum(r.get("EXOMISER_VARIANT_SCORE")))[:2]
            sig = tuple((chrom(v["CONTIG"]), v["START"], v["REF"], v["ALT"]) for v in vars_)
            if sig in seen:
                continue
            seen.add(sig)

            v1 = vars_[0]
            v2 = vars_[1] if len(vars_) > 1 else None
            note_bits = [gene, moi, v1.get("HGVS", "")]
            if v1.get("EXOMISER_ACMG_CLASSIFICATION"):
                note_bits.append("ACMG:" + v1["EXOMISER_ACMG_CLASSIFICATION"])
            out.append({
                "proband_id": pid,
                "chrom_1": chrom(v1["CONTIG"]), "pos_1": v1["START"],
                "ref_1": v1["REF"], "alt_1": v1["ALT"],
                "chrom_2": chrom(v2["CONTIG"]) if v2 else "",
                "pos_2": v2["START"] if v2 else "",
                "ref_2": v2["REF"] if v2 else "",
                "alt_2": v2["ALT"] if v2 else "",
                "epcr": f"{score:.4f}",
                "finding_type": "primary",
                "notes": " | ".join(b for b in note_bits if b),
            })
            n += 1
            if n >= args.top:
                break

    with open(args.out_csv, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=OUT_COLS)
        w.writeheader()
        w.writerows(out)
    print(f"Wrote {len(out)} rows for {len(by_proband)} probands -> {args.out_csv}")


if __name__ == "__main__":
    main()
