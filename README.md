# rare_disease_hackathon
Repository of my codes for the [MVA Rare Disease Hackathon organised by HuggingFace](https://huggingface.co/spaces/SageBio/rare-disease-real-kid-mva-hackathon-2026) 2026 <br>
`outputs` folder contains output files for the scripts<br>
### Reference Genome build check and other details for the .vcf file
1) Run `installations.sh` to install necessary tools <br> 
2) Run `vcf_file_check.sh` to perform the following checks on the .vcf file <br>
i) **Format and compression:** confirms the file is a valid VCF compressed with bgzip, and rebuilds the `.tbi` index with bcftools <br>
ii) **File validity:** reads the entire file to make sure it has no structural errors, and counts the total number of variant records <br>
iii) **Header:** reports the VCF version, the variant caller used, the reference file recorded, and which INFO and FORMAT fields are present (checking for GT, DP, GQ and AD) <br>
iv) **Reference build:** identifies whether the data was called against GRCh37/hg19 or GRCh38/hg38 using the chromosome 1 length in the header (with an optional REF-allele check against a reference FASTA) <br>
v) **Chromosome naming:** shows the number of variants per chromosome, detects the naming style (`chr1` vs `1`), and flags any main chromosomes with no variants <br>
vi) **Samples:** lists the sample names and identifies whether the file is single-sample, a possible trio, or multi-sample <br>

Results are saved to `vcf_check_outputs.txt`, and a timestamped log of each run is saved in `logs/`.<br>
### Quality control of .vcf file
3) Run `vcf_normalize.sh` to split multiallelic sites into biallelic sites, trim and left align variants <br> 
4) Run `vcf_qc.sh` to filter for variants that cross the `DP>=10`, `GQ>=20` and `FILTER=PASS` thresholds<br>
### Run [Exomiser](https://exomiser.readthedocs.io/en/latest/installation.html#configuring-the-data-directory)
5) Details in the `exomiser` folder <br>
6) Outputs saved in the `exomiser` folder <br>
