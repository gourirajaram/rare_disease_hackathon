#!/bin/bash
# filter_qc.sh - statistics, filtering and quality control of the normalized VCF
#
#   1. Statistics on the normalized VCF (saved to vcf_stats.txt)
#   2. FILTER breakdown (what passed / what failed)
#   3. Filtering: PASS + main chromosomes + no "*" alleles + DP/GQ thresholds
#   4. QC of the filtered VCF: statistics again + before/after comparison
#
# Usage:             ./filter_qc.sh
# Run in background: caffeinate -i nohup ./filter_qc.sh > /dev/null 2>&1 &

# ---------------------------------------------------------------
# Settings
# ---------------------------------------------------------------
NORM_VCF="/Users/gouri/rare_disease_hackathon/normalized/WGS_EX2312012.norm.vcf.gz"

# Filtered VCF goes OUTSIDE the repo (patient data)
FILTDIR="/Users/gouri/rare_disease_hackathon/filtered"
FILT_VCF="$FILTDIR/WGS_EX2312012.filtered.vcf.gz"

# Full bcftools stats files (outside the repo)
QCDIR="/Users/gouri/rare_disease_hackathon/qc"

# Report, stats summary and logs (inside the repo - add to .gitignore)
REPO="/Users/gouri/rare_disease_hackathon/GITHUB/rare_disease_hackathon"
OUT="$REPO/filter_qc_outputs.txt"
STATS="$REPO/vcf_stats.txt"
LOGDIR="$REPO/logs"

THREADS=6
MIN_DP=10    # minimum read depth for the genotype
MIN_GQ=20    # minimum genotype quality

# ---------------------------------------------------------------
# Logging setup (same as the other scripts)
# ---------------------------------------------------------------
mkdir -p "$LOGDIR" "$QCDIR" "$FILTDIR"
LOG="$LOGDIR/filter_qc_$(date '+%Y%m%d_%H%M%S').log"

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

# ---------------------------------------------------------------
# Helper functions for reading bcftools stats files
# ---------------------------------------------------------------
# get_sn FILE "number of SNPs:"  -> one value from the SN (summary numbers) section
get_sn() {
    awk -F'\t' -v k="$2" '$1=="SN" && $3==k {print $4; exit}' "$1"
}

# ratios FILE -> "tstv hets homalt het/hom meandepth"
#   TSTV line: $5 = Ts/Tv ratio
#   PSC line (per sample): $5 = hom-alt, $6 = het, $10 = mean depth
ratios() {
    awk -F'\t' '
        $1=="TSTV" && !t { tstv = $5; t = 1 }
        $1=="PSC"  && !p { homalt = $5; het = $6; dp = $10; p = 1 }
        END {
            hh = (homalt > 0) ? sprintf("%.2f", het/homalt) : "NA"
            print tstv, het, homalt, hh, dp
        }' "$1"
}

# write_stats "LABEL" FILE -> append a readable summary to vcf_stats.txt
write_stats() {
    local label=$1 file=$2
    local tstv het homalt hethom dp
    read tstv het homalt hethom dp <<EOF
$(ratios "$file")
EOF
    {
        echo "=================================================="
        echo "$label"
        echo "=================================================="
        echo "--- Summary numbers ---"
        grep '^SN' "$file" | cut -f3- | sed 's/^/  /'
        echo "--- Key ratios ---"
        echo "  Ts/Tv:           $tstv   (expected ~2.0-2.1 for WGS)"
        echo "  Heterozygous:    $het"
        echo "  Homozygous alt:  $homalt"
        echo "  Het/hom ratio:   $hethom   (expected ~1.4-2.2 for WGS)"
        echo "  Mean depth:      $dp"
        echo ""
    } >> "$STATS"
}

echo "STATISTICS, FILTERING AND QC"
echo "Input:      $NORM_VCF"
echo "Output:     $FILT_VCF"
echo "Thresholds: FILTER=PASS, DP>=$MIN_DP, GQ>=$MIN_GQ, main chromosomes, no * alleles"
echo "Date:       $(date)"

if [ ! -f "$NORM_VCF" ]; then
    echo "ERROR: normalized VCF not found. Run normalize.sh first."
    exit 1
fi

# Start a fresh vcf_stats.txt for this run
{
    echo "VCF STATISTICS"
    echo "Sample: $(bcftools query -l "$NORM_VCF")"
    echo "Date:   $(date)"
    echo ""
} > "$STATS"

# ---------------------------------------------------------------
section "STEP 1: Statistics on the normalized VCF"
# ---------------------------------------------------------------
echo "Running bcftools stats on all records..."
bcftools stats -s - --threads "$THREADS" "$NORM_VCF" > "$QCDIR/normalized.stats.txt"
echo "Running bcftools stats on PASS records..."
bcftools stats -s - -f PASS --threads "$THREADS" "$NORM_VCF" > "$QCDIR/normalized_pass.stats.txt"

write_stats "NORMALIZED VCF - all records" "$QCDIR/normalized.stats.txt"
write_stats "NORMALIZED VCF - PASS records only" "$QCDIR/normalized_pass.stats.txt"

TOTAL=$(get_sn "$QCDIR/normalized.stats.txt" "number of records:")
echo "Total records: $TOTAL"
echo "OK: statistics saved to $STATS"

# ---------------------------------------------------------------
section "STEP 2: FILTER breakdown"
# ---------------------------------------------------------------
# PASS = passed all GATK filters; other labels = failed that filter
bcftools query -f '%FILTER\n' "$NORM_VCF" | sort | uniq -c | sort -rn \
    | awk -v t="$TOTAL" '{ printf "  %-45s %10d  (%5.1f%%)\n", $2, $1, 100*$1/t }'

# ---------------------------------------------------------------
section "STEP 3: Filtering"
# ---------------------------------------------------------------
# Main chromosomes that actually have variants (1-22, X, Y, M or MT),
# as a comma-separated list for bcftools -r
CHROMS=$(bcftools index -s "$NORM_VCF" | cut -f1 | grep -xE '[0-9]+|X|Y|M|MT' | paste -sd, -)
echo "Keeping chromosomes: $CHROMS"

# -f PASS          keep only records with FILTER = PASS
# -r "$CHROMS"     keep only main chromosomes (drops decoys / unplaced contigs)
# -i '...'         keep only records where ALL of these are true:
#                    ALT is not "*"           (spanning-deletion placeholder)
#                    FMT/DP >= MIN_DP         (enough reads)
#                    FMT/GQ >= MIN_GQ         (confident genotype)
# -Oz              write bgzip-compressed VCF
echo "Filtering (a few minutes)..."
if bcftools view -f PASS -r "$CHROMS" \
        -i "ALT!=\"*\" && FMT/DP>=$MIN_DP && FMT/GQ>=$MIN_GQ" \
        --threads "$THREADS" -Oz -o "$FILT_VCF" "$NORM_VCF"; then
    echo "OK: filtering finished."
else
    echo "PROBLEM: filtering failed. See the log: $LOG"
    exit 1
fi

bcftools index -t -f "$FILT_VCF" && echo "OK: filtered VCF indexed."

# ---------------------------------------------------------------
section "STEP 4: QC of the filtered VCF"
# ---------------------------------------------------------------
echo "Running bcftools stats on the filtered VCF..."
bcftools stats -s - --threads "$THREADS" "$FILT_VCF" > "$QCDIR/filtered.stats.txt"
write_stats "FILTERED VCF" "$QCDIR/filtered.stats.txt"

# 4a. Confirm the filters really worked (all of these should be 0)
NONPASS=$(bcftools view -H -e 'FILTER="PASS"' "$FILT_VCF" | wc -l | tr -d ' ')
STAR=$(bcftools view -H -i 'ALT="*"' "$FILT_VCF" | wc -l | tr -d ' ')
LOWQ=$(bcftools view -H -i "FMT/DP<$MIN_DP || FMT/GQ<$MIN_GQ" "$FILT_VCF" | wc -l | tr -d ' ')
echo "Non-PASS records left:        $NONPASS  (should be 0)"
echo "'*' records left:             $STAR  (should be 0)"
echo "Records below DP/GQ minimum:  $LOWQ  (should be 0)"

# 4b. Before / after comparison
read B_TSTV B_HET B_HOM B_HH B_DP <<EOF
$(ratios "$QCDIR/normalized.stats.txt")
EOF
read A_TSTV A_HET A_HOM A_HH A_DP <<EOF
$(ratios "$QCDIR/filtered.stats.txt")
EOF

B_REC=$TOTAL
A_REC=$(get_sn "$QCDIR/filtered.stats.txt" "number of records:")
B_SNP=$(get_sn "$QCDIR/normalized.stats.txt" "number of SNPs:")
A_SNP=$(get_sn "$QCDIR/filtered.stats.txt" "number of SNPs:")
B_IND=$(get_sn "$QCDIR/normalized.stats.txt" "number of indels:")
A_IND=$(get_sn "$QCDIR/filtered.stats.txt" "number of indels:")
KEPT=$(awk -v a="$A_REC" -v b="$B_REC" 'BEGIN { printf "%.1f", 100*a/b }')

{
    echo ""
    echo "--- Before vs after filtering ---"
    printf "  %-18s %14s %14s\n" "Metric" "Normalized" "Filtered"
    printf "  %-18s %14s %14s\n" "Records"        "$B_REC"  "$A_REC"
    printf "  %-18s %14s %14s\n" "SNPs"           "$B_SNP"  "$A_SNP"
    printf "  %-18s %14s %14s\n" "Indels"         "$B_IND"  "$A_IND"
    printf "  %-18s %14s %14s\n" "Ts/Tv"          "$B_TSTV" "$A_TSTV"
    printf "  %-18s %14s %14s\n" "Heterozygous"   "$B_HET"  "$A_HET"
    printf "  %-18s %14s %14s\n" "Homozygous alt" "$B_HOM"  "$A_HOM"
    printf "  %-18s %14s %14s\n" "Het/hom"        "$B_HH"   "$A_HH"
    printf "  %-18s %14s %14s\n" "Mean depth"     "$B_DP"   "$A_DP"
    echo ""
    echo "  Records kept: $KEPT%"
} | tee -a "$STATS"

# ---------------------------------------------------------------
section "SUMMARY"
# ---------------------------------------------------------------
echo "Filtered VCF:  $FILT_VCF"
echo "Records kept:  $A_REC of $B_REC ($KEPT%)"
echo ""
echo "Statistics:    $STATS"
echo "Report:        $OUT"
echo "Full stats:    $QCDIR"
echo "Log:           $LOG"
