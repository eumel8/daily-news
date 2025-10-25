#!/usr/bin/env bash
set -euo pipefail

QUERIES_FILE="config/queries.json"
LIMIT=30
OUTFILE="data/raw_repos.json"
mkdir -p data
TMP_DIR="/tmp/ghcollector"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# Sammle alle Einzelergebnisse als separate Arrays
i=0
while IFS= read -r q; do
  echo "Searching: $q" >&2
  FILE="$TMP_DIR/q_${i}.json"
  if gh search repos "$q" --limit "$LIMIT" \
      --json name,fullName,description,url,createdAt,pushedAt,stargazersCount,owner,language,updatedAt,forksCount \
      >"$FILE" 2>/dev/null; then
    if jq empty "$FILE" 2>/dev/null; then
      jq --arg query "$q" '[.[] | select(type=="object" and has("url")) | . + {__query: $query}]' "$FILE" >"$TMP_DIR/clean_${i}.json"
    else
      echo "Invalid JSON for query: $q" >&2
      echo "[]" >"$TMP_DIR/clean_${i}.json"
    fi
  else
    echo "gh search failed for: $q" >&2
    echo "[]" >"$TMP_DIR/clean_${i}.json"
  fi
  i=$((i+1))
done < <(jq -r '.[]' "$QUERIES_FILE")

# Kombiniere alle Arrays in eine Liste und entferne Duplikate
if ls "$TMP_DIR"/clean_*.json >/dev/null 2>&1; then
  jq -s 'add | unique_by(.url)' "$TMP_DIR"/clean_*.json >"$OUTFILE" || echo "[]" >"$OUTFILE"
else
  echo "[]" >"$OUTFILE"
fi

COUNT=$(jq length "$OUTFILE" 2>/dev/null || echo 0)
echo "Collected $COUNT repos" >&2
jq . "$OUTFILE"

