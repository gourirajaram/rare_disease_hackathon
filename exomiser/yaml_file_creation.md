On MacOS
```bash
textutil -convert txt -stdout Challenge_Clinical_Phenotype_1.docx | less
textutil -convert txt Challenge_Clinical_Phenotype_1.docx -output mva_hpo.txt
grep -oE "HP:[0-9]{7}" mva_hpo.txt | sort -u | sed "s/.*/'&'/" | paste -sd, - | sed 's/^/[/;s/$/]/' > hpo_ids.txt
HPO=$(cat hpo_ids.txt)
echo "$HPO"
```
After extracting the HPO IDs
```bash
mkdir -p ~/rare_disease_hackathon/exomiser/results
cd ~/rare_disease_hackathon/exomiser

VCF="/Users/gouri/rare_disease_hackathon/filtered/WGS_EX2312012.filtered.vcf.gz"
PID="WGS_EX2312012"
HPO=$(cat ~/rare_disease_hackathon/hpo_ids.txt)
```
Create the .yml file
```bash
cat > ~/rare_disease_hackathon/exomiser/$PID.yml <<EOF
---
analysis:
  genomeAssembly: hg38
  vcf: $VCF
  ped:
  proband:
  hpoIds: $HPO
  inheritanceModes: {AUTOSOMAL_DOMINANT: 0.1, AUTOSOMAL_RECESSIVE_HOM_ALT: 0.1, AUTOSOMAL_RECESSIVE_COMP_HET: 2.0, X_DOMINANT: 0.1, X_RECESSIVE_HOM_ALT: 0.1, X_RECESSIVE_COMP_HET: 2.0, MITOCHONDRIAL: 0.2}
  analysisMode: PASS_ONLY
  frequencySources: [UK10K, GNOMAD_E_AFR, GNOMAD_E_AMR, GNOMAD_E_ASJ, GNOMAD_E_EAS, GNOMAD_E_FIN, GNOMAD_E_NFE, GNOMAD_E_SAS, GNOMAD_E_OTH, GNOMAD_G_AFR, GNOMAD_G_AMR, GNOMAD_G_ASJ, GNOMAD_G_EAS, GNOMAD_G_FIN, GNOMAD_G_NFE, GNOMAD_G_SAS, GNOMAD_G_OTH]
  pathogenicitySources: [REVEL, MVP, ALPHA_MISSENSE, SPLICE_AI]
  steps: [
    failedVariantFilter: {},
    variantEffectFilter: {remove: [FIVE_PRIME_UTR_EXON_VARIANT, FIVE_PRIME_UTR_INTRON_VARIANT, THREE_PRIME_UTR_EXON_VARIANT, THREE_PRIME_UTR_INTRON_VARIANT, NON_CODING_TRANSCRIPT_EXON_VARIANT, NON_CODING_TRANSCRIPT_INTRON_VARIANT, CODING_TRANSCRIPT_INTRON_VARIANT, UPSTREAM_GENE_VARIANT, DOWNSTREAM_GENE_VARIANT, INTERGENIC_VARIANT, REGULATORY_REGION_VARIANT]},
    frequencyFilter: {maxFrequency: 2.0},
    pathogenicityFilter: {keepNonPathogenic: true},
    inheritanceFilter: {},
    omimPrioritiser: {},
    hiPhivePrioritiser: {}
  ]
outputOptions:
  outputContributingVariantsOnly: false
  numGenes: 0
  outputDirectory: /Users/gouri/rare_disease_hackathon/exomiser/results
  outputFileName: $PID
  outputFormats: [HTML, JSON, TSV_GENE, TSV_VARIANT, VCF]
EOF
```
Check
```bash
grep -E "vcf:|hpoIds:|outputFileName:" $PID.yml
```
The above line should output the full VCF file path, the list of HP IDs and `WGS_EX2312012`
