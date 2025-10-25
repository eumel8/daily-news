#!/usr/bin/env bash
set -euo pipefail

QUERIES_FILE="config/queries.json"
LIMIT=30
OUTFILE="data/raw_repos.json"
mkdir -p data

jq -n '[]' > "$OUTFILE"

for q in $(jq -r '.[]' "$QUERIES_FILE"); do
  echo "Searching: $q" >&2
  TMP="/tmp/_res.json"
  gh search repos "$q" --limit "$LIMIT" \
    --json name,fullName,description,url,createdAt,pushedAt,stargazersCount,owner,language,updatedAt,forksCount \
    > "$TMP" || { echo "Search failed: $q" >&2; continue; }

  if [ ! -s "$TMP" ]; then
    echo "No results for $q" >&2
    continue
  fi

  jq --arg query "$q" '.[] | . + {__query: $query}' "$TMP" >> /tmp/_combined.json
done

if [ -f /tmp/_combined.json ]; then
  jq -s 'unique_by(.url)' /tmp/_combined.json > "$OUTFILE"
  rm -f /tmp/_combined.json
else
  echo "No combined results" >&2
  jq -n '[]' > "$OUTFILE"
fi

echo "Collected $(jq length "$OUTFILE") repos" >&2
jq . "$OUTFILE"

