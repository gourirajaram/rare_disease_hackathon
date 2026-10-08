#!/bin/bash
# install required VCF analysis tools for MacOS
set -e
# Install Homebrew if it's missing (asks for your Mac password)
if ! command -v brew >/dev/null 2>&1; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add brew to PATH (Apple Silicon Macs use /opt/homebrew, Intel Macs use /usr/local)
    if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    else
        eval "$(/usr/local/bin/brew shellenv)"
    fi
fi
# Install required tools
echo "Installing bcftools, htslib, samtools"
brew install bcftools htslib samtools

# Check if installation works
echo ""
echo "Checking tools:"
for tool in bcftools bgzip tabix htsfile samtools; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "  $tool  OK"
    else
        echo "  $tool  MISSING"
    fi
done
echo "Done"


