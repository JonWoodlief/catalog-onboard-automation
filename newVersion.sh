#!/bin/sh

set -e

ibmcloud target -g Default

tgzurl="$1"
version="$2"
catalog="$3"
offering="$4"

echo "get most recent version of offering"
oldVersion=$(ibmcloud catalog offering get -c "$catalog" -o "$offering" --output json | jq -r '.kinds[].versions[].version' | sort | tail -n 1)
ibmcloud catalog offering get -c "$catalog" -o "$offering" --output json > offering.json

echo "import new version"
ibmcloud catalog offering import-version --zipurl "$tgzurl" --target-version "$version" --catalog "$catalog" --offering "$offering"

echo "get offering json"
ibmcloud catalog offering get -c "$catalog" -o "$offering" --output json > offering.json

echo "pull the config from previous version"
echo "{\"configuration\": \n" > config.json
cat offering.json | jq -e --arg version "$oldVersion" '.kinds[] | select(.format_kind=="terraform").versions[] | select(.version==$version).configuration' >> config.json
echo "\n }" >> config.json

echo "edit json to add config from previous version to new version"
cat offering.json | jq --arg version "$version" --argfile values config.json '.kinds[] | select(.format_kind=="terraform").versions[] | select(.version==$version) += $values' > versions.json
cat offering.json | jq --slurpfile values versions.json '.kinds[] | select(.format_kind=="terraform").versions = $values' > kinds.json
cat offering.json | jq --slurpfile values kinds.json '.kinds = $values' > updatedoffering.json

echo "update new version"
ibmcloud catalog offering update -c "$catalog" -o "$offering" --updated-offering updatedoffering.json

echo "get updated version"
ibmcloud catalog offering get -c "$catalog" -o "$offering" --output json > newoffering.json

echo "validate version"
versionLocator=$(cat newoffering.json | jq -r --arg version "$version" '.kinds[] | select(.format_kind=="terraform").versions[] | select(.version==$version).version_locator')
echo "$versionLocator"
ibmcloud catalog offering validate --vl "$versionLocator" --override-values override.json

echo "publishing to account"
ibmcloud catalog offering get -c "$catalog" -o "$offering" --output json > newoffering.json
ibmcloud catalog offering account --vl "$versionLocator"
