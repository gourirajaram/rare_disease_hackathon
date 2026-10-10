Scripts and requirements to run [Exomiser](https://exomiser.readthedocs.io/en/latest/installation.html#quick-start-overview) on the WGS data <br>
On MacOS <br>
### Requirements

```bash
brew install exomiser/tap/exomiser
# for java requirements
brew list | grep -i jdk
sudo ln -sfn $(brew --prefix openjdk)/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk.jdk
echo 'export PATH="$(brew --prefix openjdk)/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
java -version
```
