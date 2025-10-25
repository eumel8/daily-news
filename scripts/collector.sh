#!/usr/bin/env bash
set -euo pipefail

# Collect repos for each query and output unified JSON array
# Requires: gh, jq

QUERIES_FILE="config/queries.json"
LIMIT=30
OUTFILE="data/raw_repos.json"
mkdir -p data

jq -n '[]' > "$OUTFILE"

for q in $(jq -r '.[]' "$QUERIES_FILE"); do
  echo "Searching: $q" >&2
  # gh search repos accepts query string; use --json for structured output.
  gh search repos "$q" --limit "$LIMIT" --json name,description,url,createdAt,pushedAt,stargazersCount,owner,language,topics --jq '.[]' \
    | jq --arg query "$q" '. + {__query: $query}' > /tmp/_search_results.json

  if [ -s /tmp/_search_results.json ]; then
    jq -s 'add' /tmp/_search_results.json /dev/null 2>/dev/null || true
  fi

  # append each object to OUTFILE array
  if [ -f /tmp/_search_results.json ]; then
    jq -s '[.[0]] + (.[1] // [])' <(jq -s '.[0]' "$OUTFILE") /tmp/_search_results.json > "$OUTFILE.tmp" || true
    mv "$OUTFILE.tmp" "$OUTFILE"
    rm -f /tmp/_search_results.json
  fi
done

# normalize (unique by url)
jq 'unique_by(.url)' "$OUTFILE" > "$OUTFILE.tmp" && mv "$OUTFILE.tmp" "$OUTFILE"

echo "Collected $(jq length "$OUTFILE") repos" >&2
jq . "$OUTFILE"
