#!/usr/bin/env bash

# Request reviewers for a PR, reading line-separated usernames on stdin,
# filtering for valid reviewers before using the API endpoint to request reviews:
# https://docs.github.com/en/rest/pulls/review-requests?apiVersion=2022-11-28#request-reviewers-for-a-pull-request

set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' exit

log() {
    echo "$@" >&2
}

effect() {
    if [[ -n "${DRY_MODE:-}" ]]; then
        log "Skipping in dry mode:" "${@@Q}"
    else
        "$@"
    fi
}

if (( "$#" < 3 )); then
    log "Usage: $0 BASE_REPO PR_NUMBER PR_AUTHOR"
    exit 1
fi

baseRepo=$1
prNumber=$2
prAuthor=$3

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' exit

declare -A users=()
while read -r handle && [[ -n "$handle" ]]; do
    users[${handle,,}]=
done

# Cannot request a review from the author
if [[ -v users[${prAuthor,,}] ]]; then
    log "One or more files are owned by the PR author, ignoring"
    unset 'users[${prAuthor,,}]'
fi

# A graphql query to get all reviewers of a PR, including both users and teams
# on behalf of which a review was done
all_reviewers_query='
query($owner: String!, $repo: String!, $pr: Int!, $endCursor: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      reviews(first: 100, after: $endCursor) {
        nodes {
          author {
            login
          }
          onBehalfOf(first: 100) {
            nodes {
              combinedSlug
            }
          }
        }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
  }
}
'
# A jq script to extract individuals and teams from the response to above query,
# and combine them into a uniform list. The way to tell them apart is that teams
# will have a slash in the name.
combine_reviewers='
.data.repository.pullRequest.reviews.nodes
  | map([ .author.login ] + (.onBehalfOf.nodes | map(.combinedSlug)))
  | flatten
  | .[]
'

owner="${baseRepo%/*}"
repo="${baseRepo#*/}"

gh api graphql \
    -H "Accept: application/vnd.github+json" \
    --paginate \
    -f query="$all_reviewers_query" \
    -F owner="$owner" \
    -F repo="$repo" \
    -F pr=$prNumber \
    | jq -r "$combine_reviewers" \
    > "$tmp/already-reviewed-by"

# And we don't want to rerequest reviews from people or teams who already reviewed
while read -r user; do
    if [[ -v users[${user,,}] ]]; then
        log "User or team $user is a potential reviewer, but has already left a review, ignoring"
        unset 'users[${user,,}]'
    fi
done < "$tmp/already-reviewed-by"

for user in "${!users[@]}"; do
    if [[ "$user" =~ "/" ]]; then
        if ! [[ "$user" =~ "$owner/" ]]; then
            log "Team $user is not part of the $owner org, skipping"
            unset 'users[$user]'
        fi
    else
        if ! gh api \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "/repos/$baseRepo/collaborators/$user" >&2; then
            log "User $user is not a repository collaborator, probably missed the automated invite to the maintainers team (see <https://github.com/NixOS/nixpkgs/issues/234293>), ignoring"
            unset 'users[$user]'
        fi
    fi
done

if [[ "${#users[@]}" -gt 10 ]]; then
    log "Too many reviewers (${!users[*]}), skipping review requests"
    exit 0
fi

for user in "${!users[@]}"; do
    if [[ "$user" =~ "/" ]]; then
        team="${user#*/}"
        log "Requesting review from team $team (full slug: $user)"
        field="team_reviewers[]=$team"
    else
        log "Requesting review from user $user"
        field="reviewers[]=$user"
    fi

    if ! response=$(effect gh api \
            --method POST \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "/repos/$baseRepo/pulls/$prNumber/requested_reviewers" \
            -f "$field"); then
        log "Failed to request review from $user: $response"
    fi
done
