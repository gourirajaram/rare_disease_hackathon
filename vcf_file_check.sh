#!/bin/bash
VCF="/Users/gouri/rare_disease_hackathon/WGS_EX2312012_HGWCNDSX7.vcf.gz"
OUT="/Users/gouri/rare_disease_hackathon/GITHUB/rare_disease_hackathon/vcf_check_outputs.txt"
LOGDIR="/Users/gouri/rare_disease_hackathon/GITHUB/rare_disease_hackathon/logs"
REF=""   # optional: path to a reference .fa (indexed with samtools faidx) for the REF check in Step 4

# ---------------------------------------------------------------
# Logging setup
# ---------------------------------------------------------------
mkdir -p "$LOGDIR"
LOG="$LOGDIR/vcf_check_$(date '+%Y%m%d_%H%M%S').log"

# Results (stdout) -> screen + outputs file
exec > >(tee "$OUT")
# Errors, warnings and command trace (stderr) -> log file
exec 2>>"$LOG"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

on_error() {
    log "ERROR: exit code $1 at line $2 -> $3"
}

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

log "Script started"
log "VCF: $VCF"
log "Results file: $OUT"

# Record every command with its line number in the log
PS4='+ [line ${LINENO}] '
set -x

section() {
    log "=== $1 ==="
    echo ""
    echo "=================================================="
    echo "$1"
    echo "=================================================="
}

echo "VCF SANITY CHECK"
echo "File:     $VCF"
echo "Date:     $(date)"
echo "bcftools: $(bcftools --version | head -1)"
echo "Log:      $LOG"

if [ ! -f "$VCF" ]; then
    echo "ERROR: file not found: $VCF"
    exit 1
fi
ls -lh "$VCF"

# ---------------------------------------------------------------
section "STEP 1: Format, compression and index"
# ---------------------------------------------------------------
FORMAT=$(htsfile "$VCF")
echo "$FORMAT"

if echo "$FORMAT" | grep -q "BGZF"; then
    echo "OK: file is bgzip-compressed."
elif echo "$FORMAT" | grep -q "gzip"; then
    echo "File is plain gzip, not bgzip. Recompressing to a new file (original untouched)..."
    NEW="${VCF%.vcf.gz}.bgz.vcf.gz"
    gzip -dc "$VCF" | bgzip > "$NEW"
    VCF="$NEW"
    echo "Now using: $VCF"
elif echo "$FORMAT" | grep -q "VCF"; then
    echo "File is uncompressed. Compressing with bgzip to a new file..."
    NEW="${VCF%.gz}.bgz.vcf.gz"
    bgzip -c "$VCF" > "$NEW"
    VCF="$NEW"
    echo "Now using: $VCF"
else
    echo "ERROR: this does not look like a VCF file."
    exit 1
fi

echo "Building index with bcftools (overwrites any existing index)..."
bcftools index -t -f "$VCF" && echo "OK: index ready ($VCF.tbi)"
# ---------------------------------------------------------------
section "STEP 2: File validity"
# ---------------------------------------------------------------
echo "Reading the whole file (can take a few minutes for a WGS)..."
ERRFILE=$(mktemp)
if bcftools view "$VCF" > /dev/null 2> "$ERRFILE"; then
    echo "OK: bcftools read the whole file without errors."
else
    echo "PROBLEM: bcftools could not read the file. First errors:"
    head -20 "$ERRFILE"
fi
NWARN=$(grep -c . "$ERRFILE" || true)
if [ "$NWARN" -gt 0 ]; then
    echo "bcftools printed $NWARN warning line(s). First few:"
    head -10 "$ERRFILE"
    cat "$ERRFILE" >> "$LOG"
fi
rm -f "$ERRFILE"

echo "Total variant records: $(bcftools index -n "$VCF")"

# ---------------------------------------------------------------
section "STEP 3: Header"
# ---------------------------------------------------------------
HEADER=$(mktemp)
bcftools view -h "$VCF" > "$HEADER"

echo "--- File format ---"
grep '^##fileformat' "$HEADER"

echo ""
echo "--- Variant caller / source ---"
grep -iE '^##(source|.*commandline|deepvariant)' "$HEADER" | cut -c1-200 | head -5
grep -qiE '^##(source|.*commandline|deepvariant)' "$HEADER" || echo "(not recorded)"

echo ""
echo "--- Reference line ---"
grep '^##reference' "$HEADER" || echo "(no ##reference line)"

echo ""
echo "Number of ##contig lines: $(grep -c '^##contig' "$HEADER")"

echo ""
echo "--- INFO fields ---"
grep '^##INFO' "$HEADER" | sed 's/.*ID=\([^,]*\),.*/\1/' | tr '\n' ' '
echo ""

echo ""
echo "--- FORMAT fields ---"
grep '^##FORMAT' "$HEADER" | sed 's/.*ID=\([^,]*\),.*/\1/' | tr '\n' ' '
echo ""

echo ""
echo "--- Key per-sample fields ---"
for f in GT DP GQ AD; do
    if grep -q "^##FORMAT=<ID=$f," "$HEADER"; then
        echo "  $f  present"
    else
        echo "  $f  MISSING"
    fi
done

# ---------------------------------------------------------------
section "STEP 4: Reference build"
# ---------------------------------------------------------------
BUILD="unknown"
CHR1_LEN=$(grep -E '^##contig=<ID=(chr)?1,' "$HEADER" | sed -n 's/.*length=\([0-9]*\).*/\1/p')

case "$CHR1_LEN" in
    249250621) BUILD="GRCh37/hg19" ;;
    248956422) BUILD="GRCh38/hg38" ;;
    "")        echo "chr1 length not in header." ;;
    *)         echo "chr1 length is $CHR1_LEN (not a standard human build)." ;;
esac
[ -n "$CHR1_LEN" ] && echo "chr1 length in header: $CHR1_LEN"
echo "Build from contig lengths: $BUILD"

echo ""
echo "Build keywords mentioned in the header:"
grep -ioE 'grch37|grch38|hg19|hg38|b37|hs37d5' "$HEADER" | sort | uniq -c || echo "(none)"

if [ -n "$REF" ]; then
    echo ""
    echo "Checking REF alleles against $REF (slow for a WGS)..."
    MISMATCH=$(bcftools norm --check-ref w -f "$REF" "$VCF" -Ou -o /dev/null 2>&1 | grep -ci 'mismatch' || true)
    echo "REF mismatch lines: $MISMATCH"
    echo "(Near zero = build matches. Large number = wrong build.)"
else
    echo ""
    echo "No reference given, so the REF-allele check was skipped."
    echo "Set REF= at the top of the script to run it."
fi

# ---------------------------------------------------------------
section "STEP 5: Chromosome naming"
# ---------------------------------------------------------------
echo "Variants per chromosome (name, length, count):"
bcftools index -s "$VCF"

CONTIGS=$(bcftools index -s "$VCF" | cut -f1)
if echo "$CONTIGS" | grep -q '^chr'; then
    NAMING="UCSC style (chr1, chr2, ...)"
    PREFIX="chr"
else
    NAMING="Ensembl/NCBI style (1, 2, ...)"
    PREFIX=""
fi
echo ""
echo "Naming: $NAMING"

MITO=$(echo "$CONTIGS" | grep -xE 'chrM|chrMT|MT|M' || true)
echo "Mitochondrial chromosome: ${MITO:-(none found)}"

MISSING=""
for c in $(seq 1 22) X Y; do
    echo "$CONTIGS" | grep -qx "${PREFIX}${c}" || MISSING="$MISSING ${PREFIX}${c}"
done
if [ -z "$MISSING" ]; then
    echo "OK: all of chromosomes 1-22, X and Y have variants."
else
    echo "Chromosomes with NO variants:$MISSING"
    echo "(Missing Y is normal for a female sample.)"
fi

if [ -n "$REF" ] && [ -f "$REF.fai" ]; then
    echo ""
    echo "First chromosome names in reference: $(cut -f1 "$REF.fai" | head -5 | tr '\n' ' ')"
fi

# ---------------------------------------------------------------
section "STEP 6: Samples"
# ---------------------------------------------------------------
SAMPLES=$(bcftools query -l "$VCF")
NSAMP=$(echo "$SAMPLES" | grep -c . || true)
echo "Number of samples: $NSAMP"
echo "Sample names:"
echo "$SAMPLES" | sed 's/^/  /'

case "$NSAMP" in
    0) TYPE="sites-only (no genotypes)" ;;
    1) TYPE="single-sample" ;;
    3) TYPE="3 samples - possibly a trio (check which is child/parents)" ;;
    *) TYPE="multi-sample" ;;
esac
echo "Type: $TYPE"

# ---------------------------------------------------------------
section "SUMMARY"
# ---------------------------------------------------------------
echo "File:        $VCF"
echo "Variants:    $(bcftools index -n "$VCF")"
echo "Build:       $BUILD"
echo "Naming:      $NAMING"
echo "Samples:     $NSAMP ($TYPE)"
echo ""
echo "Results saved to: $OUT"
echo "Log saved to:     $LOG"

rm -f "$HEADER"
