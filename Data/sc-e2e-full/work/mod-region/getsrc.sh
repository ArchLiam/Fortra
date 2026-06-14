#!/bin/zsh
ID="01pWC000001wAzRYAU"
sf data query --use-tooling-api --query "SELECT Body FROM ApexClass WHERE Id='$ID'" -o FortraUAT --json > raw.json
