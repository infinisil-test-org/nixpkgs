#!/usr/bin/env bash

# Requests reviews for a PR after verifying that the base branch is correct

set -euo pipefail
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' exit
SCRIPT_DIR=$(dirname "$0")

log() {
    echo "$@" >&2
}

if (( $# < 3 )); then
    log "Usage: $0 GITHUB_REPO PR_NUMBER OWNERS_FILE"
    exit 1
fi
baseRepo=$1
prNumber=$2
ownersFile=$3

log "Fetching PR info"
prInfo=$(gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "/repos/$baseRepo/pulls/$prNumber")

baseBranch=$(jq -r .base.ref <<< "$prInfo")
log "Base branch: $baseBranch"
prRepo=$(jq -r .head.repo.full_name <<< "$prInfo")
log "PR repo: $prRepo"
prBranch=$(jq -r .head.ref <<< "$prInfo")
log "PR branch: $prBranch"
prAuthor=$(jq -r .user.login <<< "$prInfo")
log "PR author: $prAuthor"

extraArgs=()
if pwdRepo=$(git rev-parse --show-toplevel 2>/dev/null); then
    # Speedup for local runs
    extraArgs+=(--reference-if-able "$pwdRepo")
fi

log "Fetching Nixpkgs commit history"
git clone --bare --filter=tree:0 --no-tags --origin upstream "${extraArgs[@]}" https://github.com/"$baseRepo".git "$tmp"/nixpkgs.git

log "Fetching the PR commit history"
# Fetch the PR
git -C "$tmp/nixpkgs.git" remote add fork https://github.com/"$prRepo".git
# Make sure we only fetch the commit history, nothing else
git -C "$tmp/nixpkgs.git" config remote.fork.promisor true
git -C "$tmp/nixpkgs.git" config remote.fork.partialclonefilter tree:0

# This should not conflict with any refs in Nixpkgs
headRef=refs/remotes/fork/pr
# Only fetch into a remote ref, because the local ref namespace is used by Nixpkgs, don't want any conflicts
git -C "$tmp/nixpkgs.git" fetch --no-tags fork "$prBranch":"$headRef"

log "Checking correctness of the base branch"
"$SCRIPT_DIR"/verify-base-branch.sh "$tmp/nixpkgs.git" "$headRef" "$baseRepo" "$baseBranch" "$prRepo" "$prBranch"

log "Getting code owners to request reviews from"
"$SCRIPT_DIR"/get-reviewers.sh "$tmp/nixpkgs.git" "$baseBranch" "$headRef" "$ownersFile" "$prAuthor" > "$tmp/reviewers.json"

log "Requesting reviews from: $(<"$tmp/reviewers.json")"

if ! response=$(gh api \
    --method POST \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "/repos/$baseRepo/pulls/$prNumber/requested_reviewers" \
    --input "$tmp/reviewers.json"); then
    log "Failed to request reviews: $response"
    exit 1
fi

log "Successfully requested reviews"
