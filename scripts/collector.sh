#!/usr/bin/env bash
set -euo pipefail

# Collect repos for each query and output unified JSON array
# Requires: gh, jq
# NOTE: gh's available JSON fields vary. Use fields confirmed available by the user's gh.

QUERIES_FILE="config/queries.json"
LIMIT=30
OUTFILE="data/raw_repos.json"
mkdir -p data

jq -n '[]' > "$OUTFILE"

auth_check() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "gh CLI not found" >&2
    exit 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq not found" >&2
    exit 1
  fi
}

auth_check

for q in $(jq -r '.[]' "$QUERIES_FILE"); do
  echo "Searching: $q" >&2
  # Use fields that are available per gh output
  # available fields: name, fullName, description, url, createdAt, pushedAt, stargazersCount, owner, language, updatedAt, forksCount, size
  gh search repos "$q" --limit "$LIMIT" --json name,fullName,description,url,createdAt,pushedAt,stargazersCount,owner,language,updatedAt,forksCount --jq '.[]' \
    > /tmp/_search_results.json || true

  if [ -s /tmp/_search_results.json ]; then
    # attach query metadata
    jq --arg query "$q" '. + {__query: $query}' /tmp/_search_results.json > /tmp/_search_results_tagged.json

    # append to OUTFILE array
    jq -s '.[0] + [.[1]] | add' <(jq -s '.' "$OUTFILE") /tmp/_search_results_tagged.json > "$OUTFILE.tmp" 2>/dev/null || jq -s '.[0] + .[1]' <(jq -s '.' "$OUTFILE") /tmp/_search_results_tagged.json > "$OUTFILE.tmp"
    mv "$OUTFILE.tmp" "$OUTFILE"
    rm -f /tmp/_search_results.json /tmp/_search_results_tagged.json
  else
    echo "No results for query: $q" >&2
  fi
done

# normalize (unique by url)
jq 'unique_by(.url)' "$OUTFILE" > "$OUTFILE.tmp" && mv "$OUTFILE.tmp" "$OUTFILE"

echo "Collected $(jq length "$OUTFILE") repos" >&2
jq . "$OUTFILE"
