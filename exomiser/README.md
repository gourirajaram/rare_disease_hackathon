Scripts and requirements to run [Exomiser](https://exomiser.readthedocs.io/en/latest/installation.html#quick-start-overview) on the WGS data <br>

### Requirements
For MacOS
```bash
brew install exomiser/tap/exomiser
# for java requirements
brew list | grep -i jdk
sudo ln -sfn $(brew --prefix openjdk)/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk.jdk
echo 'export PATH="$(brew --prefix openjdk)/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
java -version
```
### Data downloads
Refer to https://github.com/exomiser/Exomiser/discussions/640 for latest data download.<br>
Note that this takes several hours.<br>
Create exomiser's home folder.
```bash
exomiser --version
ls ~/.exomiser
# this creates an application.properties settings file and an empty data folder
# to speed up data download
brew install aria2
cd ~/.exomiser/data
cat > data_download_urls.txt <<EOF
heredoc> https://g-879a9f.f5dc97.75bc.dn.glob.us/data/2602_phenotype.zip
heredoc> https://g-879a9f.f5dc97.75bc.dn.glob.us/data/2602_hg38.zip
heredoc> EOF
caffeinate -i aria2c -x 16 -s 16 -j 2 -c -i data_download_urls.txt
```
Unzip the data files
```bash
cd ~/.exomiser/data
nohup caffeinate -i sh -c 'unzip -o 2602_phenotype.zip && unzip -o 2602_hg38.zip' > unzip.log 2>&1 &
```
Delete the zip files to free up space
```bash
   rm ~/.exomiser/data/2602_hg38.zip ~/.exomiser/data/2602_phenotype.zip
```
Edit the config
```bash
   nano ~/.exomiser/application.properties
```
Edits to be made <br>
- Under the `### hg19 assembly ###`, comment out the hg19 line by adding # <br>
- Under the `### hg38 assembly ###`, remove the # and change existing number to 2602 <br>
- Under the `### phenotypes ###`, change the existing number to 2602 <br>
Save in nano by Ctrl+O and Ctrl+X <br>
```bash
grep -n "data-directory" ~/.exomiser/application.properties
grep -E "^exomiser\.(data-directory|hg19\.data-version|hg38\.data-version|phenotype\.data-version)" ~/.exomiser/application.properties
```
You should see exactly i.e the exomiser.data-directory should be uncommented
```bash
exomiser.data-directory=/Users/gouri/.exomiser/data
exomiser.hg38.data-version=2602
exomiser.phenotype.data-version=2602
```
other option
```bash
sed -i '' '26s|.*|exomiser.data-directory=/Users/gouri/.exomiser/data|' ~/.exomiser/application.properties
sed -n '26p' ~/.exomiser/application.properties
```
### Run exomiser
```bash
export JAVA_TOOL_OPTIONS="-Xmx12g"
nohup caffeinate -i exomiser analyse --analysis $PID.yml > $PID.log 2>&1 &
tail -f $PID.log
```
### Output
Stored in `results` folder in the `exomiser` folder as per the .yml file
