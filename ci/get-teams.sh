#!/usr/bin/env bash

set -euo pipefail

ORG=$1
REPO=$2

# Takes a list of teams as JSON input, returns
processTeams() {
  eval "local -A teams=($(jq -r '.[] | "[\(.slug | @sh)]=\(.description | @sh)"'))"
  for slug in "${!teams[@]}"; do
    echo >&2 "Processing team $slug"
    jq -n '{ key: $slug, value: { description: $description, members: ($members | map(.login)), maintainers: ($maintainers | map(.login)) } }' \
      --arg slug "$slug" \
      --arg description "${teams[$slug]}" \
      --slurpfile members <(gh api --paginate /orgs/"$ORG"/teams/"$slug"/members --jq '.[]') \
      --slurpfile maintainers <(gh api --method=GET --paginate /orgs/"$ORG"/teams/"$slug"/members -f role=maintainer --jq '.[]')
    gh api --paginate /orgs/"$ORG"/teams/"$slug"/teams | processTeams
  done
}

gh api --paginate /repos/"$ORG"/"$REPO"/teams | processTeams | jq --slurp from_entries
