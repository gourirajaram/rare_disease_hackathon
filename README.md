# rare_disease_hackathon
Repository of my codes for the [MVA Rare Disease Hackathon (Track 1) organised by HuggingFace](https://huggingface.co/spaces/SageBio/rare-disease-real-kid-mva-hackathon-2026) 2026. <br> <br>
### Compute requirements <br>
Run on MacOS - Apple M5, 16 GB RAM 
##### Pipeline ran successfully with full scores: Rank points-100, F-max-1.0
### Reference Genome build check and other details for the .vcf file
1) Run `installations.sh` to install necessary tools <br> 
2) Run `vcf_file_check.sh` to perform preliminary checks on the .vcf file such as reference build check, and chromosome naming convention.<br>
<br><br>
Results are saved to `vcf_check_outputs.txt`, and a timestamped log of each run is saved in `logs/`.This has been deleted from public forum as per the hackathon rules.<br>
### Quality control of .vcf file
3) Run `vcf_normalize.sh` to split multiallelic sites into biallelic sites, trim and left align variants <br> 
4) Run `vcf_qc.sh` to filter for variants that cross the `DP>=10`, `GQ>=20` and `FILTER=PASS` thresholds<br>
### Run [Exomiser](https://exomiser.readthedocs.io/en/latest/installation.html#configuring-the-data-directory)
5) Details in the `exomiser` folder <br>
6) Outputs saved in the `exomiser` folder <br> <br>

Claude Opus 5.5, and Gemini 3 models  were prompted to assist with coding. <br>
