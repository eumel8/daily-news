#!/usr/bin/env bash
set -euo pipefail

QUERIES_FILE="config/queries.json"
LIMIT=30
OUTFILE="data/raw_repos.json"
mkdir -p data /tmp/ghsearch
rm -f /tmp/ghsearch/*.json

echo "[]" > "$OUTFILE"

# 1. Sammle für jede Query eigene Datei
i=0
for q in $(jq -r '.[]' "$QUERIES_FILE"); do
  echo "Searching: $q" >&2
  TMP="/tmp/ghsearch/query_${i}.json"
  if gh search repos "$q" --limit "$LIMIT" \
      --json name,fullName,description,url,createdAt,pushedAt,stargazersCount,owner,language,updatedAt,forksCount \
      > "$TMP" 2>/dev/null; then
    if jq empty "$TMP" 2>/dev/null && [ "$(jq length "$TMP")" -gt 0 ]; then
      jq --arg query "$q" '.[] | . + {__query: $query}' "$TMP" > "/tmp/ghsearch/items_${i}.json"
    else
      echo "No results for $q" >&2
    fi
  else
    echo "Search failed for $q" >&2
  fi
  i=$((i+1))
done

# 2. Fasse alle Items zu einem Array zusammen
if ls /tmp/ghsearch/items_*.json >/dev/null 2>&1; then
  jq -s 'add | unique_by(.url)' /tmp/ghsearch/items_*.json > "$OUTFILE"
else
  echo "[]" > "$OUTFILE"
fi

# 3. Ausgabe
COUNT=$(jq length "$OUTFILE" 2>/dev/null || echo 0)
echo "Collected $COUNT repos" >&2
jq . "$OUTFILE"

