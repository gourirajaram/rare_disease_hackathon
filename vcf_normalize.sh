#!/bin/bash
VCF="/Users/gouri/rare_disease_hackathon/WGS_EX2312012_HGWCNDSX7.vcf.gz"
REFDIR="/Users/gouri/rare_disease_hackathon/reference"
REF="$REFDIR/GRCh38_no_alt_hs38d1_no_chr.fa.gz"
REF_URL="https://ftp.ncbi.nlm.nih.gov/genomes/all/GCA/000/001/405/GCA_000001405.15_GRCh38/seqs_for_alignment_pipelines.ucsc_ids/GCA_000001405.15_GRCh38_no_alt_plus_hs38d1_analysis_set.fna.gz"
OUTDIR="/Users/gouri/rare_disease_hackathon/normalized"
NORM_VCF="$OUTDIR/WGS_EX2312012.norm.vcf.gz"
REPO="/Users/gouri/rare_disease_hackathon/GITHUB/rare_disease_hackathon"
OUT="$REPO/normalize_outputs.txt"
LOGDIR="$REPO/logs"
THREADS=6
# Logging setup (same as vcf_file_check.sh)
# ---------------------------------------------------------------
mkdir -p "$LOGDIR" "$OUTDIR" "$REFDIR"
LOG="$LOGDIR/normalize_$(date '+%Y%m%d_%H%M%S').log"

exec > >(tee "$OUT")      # results -> screen + report file
exec 2>>"$LOG"            # errors, warnings, command trace -> log file

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }
on_error() { log "ERROR: exit code $1 at line $2 -> $3"; }
on_exit() {
    local code=$?
    if [ $code -eq 0 ]; then
        log "Script finished successfully"
    else
        log "Script STOPPED with exit code $code"
        echo ""
        echo "Script stopped early. Check the log: $LOG"
    fi
}
trap 'on_error $? $LINENO "$BASH_COMMAND"' ERR
trap 'log "Interrupted by user (Ctrl+C)"; exit 130' INT
trap on_exit EXIT

PS4='+ [line ${LINENO}] '
set -x   # record every command in the log

section() {
    log "=== $1 ==="
    echo ""
    echo "=================================================="
    echo "$1"
    echo "=================================================="
}

echo "VCF NORMALIZATION"
echo "Input:     $VCF"
echo "Reference: $REF"
echo "Output:    $NORM_VCF"
echo "Date:      $(date)"
echo "bcftools:  $(bcftools --version | head -1)"

if [ ! -f "$VCF" ]; then
    echo "ERROR: input VCF not found: $VCF"
    exit 1
fi
# ---------------------------------------------------------------
section "STEP 1: Prepare the reference genome"
# ---------------------------------------------------------------
# Skip everything if the reference and its index already exist
if [ -f "$REF" ] && [ -f "$REF.fai" ]; then
    echo "OK: reference already prepared."
else
    RAW="$REFDIR/$(basename "$REF_URL")"

    # Download (~900 MB) unless already downloaded
    if [ ! -f "$RAW" ]; then
        echo "Downloading NCBI GRCh38 no_alt + hs38d1 analysis set (~900 MB)..."
        curl -fL --retry 3 -o "$RAW.part" "$REF_URL" || { echo "ERROR: download failed"; exit 1; }
        mv "$RAW.part" "$RAW"
    fi

    # Remove the "chr" prefix so names match the VCF (chr1 -> 1),
    # then compress with bgzip (tools can read bgzipped FASTA directly)
    echo "Stripping 'chr' from names and compressing with bgzip..."
    gzip -dc "$RAW" | sed 's/^>chr/>/' | bgzip -@ "$THREADS" > "$REF"

    # Index the reference (creates .fai and .gzi next to it)
    echo "Indexing reference..."
    samtools faidx "$REF" || { echo "ERROR: samtools faidx failed"; exit 1; }
    echo "OK: reference ready."
fi
echo "First names in reference: $(cut -f1 "$REF.fai" | head -5 | tr '\n' ' ')"
# ---------------------------------------------------------------
section "STEP 2: Check the reference matches the VCF"
# ---------------------------------------------------------------
# 2a. Every contig that HAS variants must exist in the reference,
#     otherwise bcftools norm stops with an error.
TMPV=$(mktemp); TMPR=$(mktemp)
bcftools index -s "$VCF" | cut -f1 | LC_ALL=C sort > "$TMPV"
cut -f1 "$REF.fai" | LC_ALL=C sort > "$TMPR"
MISSING_CONTIGS=$(LC_ALL=C comm -23 "$TMPV" "$TMPR")
rm -f "$TMPV" "$TMPR"

if [ -z "$MISSING_CONTIGS" ]; then
    echo "OK: all contigs with variants exist in the reference."
else
    echo "PROBLEM: these contigs have variants but are missing from the reference:"
    echo "$MISSING_CONTIGS" | head -20
    echo "Stopping. The reference does not match the VCF."
    exit 1
fi
section "STEP 3: Counts before normalization"
# ---------------------------------------------------------------
BEFORE_TOTAL=$(bcftools view -H "$VCF" | wc -l | tr -d ' ')
# -m3 keeps records with 3+ alleles (REF + 2 or more ALTs) = multiallelic
BEFORE_MULTI=$(bcftools view -H -m3 "$VCF" | wc -l | tr -d ' ')
echo "Total records:       $BEFORE_TOTAL"
echo "Multiallelic sites:  $BEFORE_MULTI"
section "STEP 4: Normalize (split + trim + left-align)"
# ---------------------------------------------------------------
# -m -any            split ALL multiallelic records (SNPs and indels) into biallelic lines
# -f "$REF"          reference used to trim and left-align indels
# --check-ref w      warn (don't stop) if a REF allele doesn't match the reference
# --old-rec-tag      store the original record in an INFO tag (ORIGINAL), so you can
#                    always see which lines came from a split multiallelic site
# -Oz                write bgzip-compressed VCF
echo "Running bcftools norm (can take 10-20 minutes for a WGS)..."
NORMERR=$(mktemp)
if bcftools norm -m -any -f "$REF" --check-ref w --old-rec-tag ORIGINAL \
        --threads "$THREADS" -Oz -o "$NORM_VCF" "$VCF" 2> "$NORMERR"; then
    echo "OK: normalization finished."
else
    echo "PROBLEM: bcftools norm failed. First errors:"
    head -20 "$NORMERR"
    cat "$NORMERR" >> "$LOG"
    rm -f "$NORMERR"
    exit 1
fi
# bcftools prints a summary line: how many records were split, realigned, etc.
echo ""
echo "bcftools summary:"
grep '^Lines' "$NORMERR"
echo "REF mismatch warnings (whole genome): $(grep -i 'mismatch' "$NORMERR" | grep -vc '^Lines' || true)"
cat "$NORMERR" >> "$LOG"
rm -f "$NORMERR"

# ---------------------------------------------------------------
section "STEP 5: Index and verify the result"
# ---------------------------------------------------------------
bcftools index -t -f "$NORM_VCF" && echo "OK: index created."

AFTER_TOTAL=$(bcftools view -H "$NORM_VCF" | wc -l | tr -d ' ')
AFTER_MULTI=$(bcftools view -H -m3 "$NORM_VCF" | wc -l | tr -d ' ')
echo "Total records:       $AFTER_TOTAL"
echo "Multiallelic sites:  $AFTER_MULTI  (should be 0)"

if [ "$AFTER_MULTI" -eq 0 ]; then
    echo "OK: all multiallelic sites were split."
else
    echo "WARNING: some multiallelic sites remain."
fi

# ---------------------------------------------------------------
section "SUMMARY"
# ---------------------------------------------------------------
echo "Input:                 $VCF"
echo "Output:                $NORM_VCF"
echo "Records before:        $BEFORE_TOTAL"
echo "Records after:         $AFTER_TOTAL  (+$((AFTER_TOTAL - BEFORE_TOTAL)) from splitting)"
echo "Multiallelic before:   $BEFORE_MULTI"
echo "Multiallelic after:    $AFTER_MULTI"
echo ""
echo "Report saved to: $OUT"
echo "Log saved to:    $LOG"
