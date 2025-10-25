#!/usr/bin/env bash
set -euo pipefail

QUERIES_FILE="config/queries.json"
LIMIT=30
OUTFILE="data/raw_repos.json"
mkdir -p data
TMP_FILE="/tmp/_collector.tmp"
> "$TMP_FILE"

echo "[" > "$OUTFILE"
first=1

while IFS= read -r q; do
  [ -z "$q" ] && continue
  echo "Searching: $q" >&2

  if ! gh search repos "$q" --limit "$LIMIT" \
       --json name,fullName,description,url,createdAt,pushedAt,stargazersCount,owner,language,updatedAt,forksCount \
       > "$TMP_FILE" 2>/dev/null; then
    echo "Search failed: $q" >&2
    continue
  fi

  # Prüfe, ob Datei gültiges JSON enthält
  if ! jq empty "$TMP_FILE" 2>/dev/null; then
    echo "Invalid JSON for query: $q" >&2
    continue
  fi

  # Extrahiere Objekte mit URL
  jq -c '.[] | select(type=="object" and has("url"))' "$TMP_FILE" |
  while read -r obj; do
    [ $first -eq 1 ] && first=0 || echo "," >> "$OUTFILE"
    echo "$obj" | jq -c --arg query "$q" '. + {__query: $query}' >> "$OUTFILE"
  done

done < <(jq -r '.[]' "$QUERIES_FILE")

echo "]" >> "$OUTFILE"

# Aufräumen
rm -f "$TMP_FILE"

# Ausgabe prüfen
if jq empty "$OUTFILE" 2>/dev/null; then
  COUNT=$(jq length "$OUTFILE")
  echo "Collected $COUNT repos" >&2
else
  echo "Collector produced invalid JSON, writing empty array" >&2
  echo "[]" > "$OUTFILE"
fi

jq . "$OUTFILE"

