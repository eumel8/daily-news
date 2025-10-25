#!/usr/bin/env bash
set -euo pipefail

QUERIES_FILE="config/queries.json"
LIMIT=30
OUTFILE="data/raw_repos.json"
TMP_DIR="/tmp/ghsearch"
mkdir -p data "$TMP_DIR"
rm -f "$TMP_DIR"/*

echo "[]" > "$OUTFILE"

i=0
for q in $(jq -r '.[]' "$QUERIES_FILE"); do
  echo "Searching: $q" >&2
  RAW="$TMP_DIR/raw_${i}.json"
  ND="$TMP_DIR/objs_${i}.ndjson"
  ITEMS="$TMP_DIR/items_${i}.json"

  # Run gh search; on error skip
  if ! gh search repos "$q" --limit "$LIMIT" \
      --json name,fullName,description,url,createdAt,pushedAt,stargazersCount,owner,language,updatedAt,forksCount \
      > "$RAW" 2>/dev/null; then
    echo "gh search failed for: $q" >&2
    i=$((i+1)); continue
  fi

  # Validate JSON
  if ! jq empty "$RAW" 2>/dev/null; then
    echo "Invalid JSON for query, skipping: $q" >&2
    i=$((i+1)); continue
  fi

  # Extract only object entries that have a url.
  # Write newline-delimited JSON objects for reliable combining.
  jq -c '.[]? | select(type=="object" and has("url"))' "$RAW" > "$ND" || true

  if [ -s "$ND" ]; then
    # convert ndjson back to a JSON array of objects
    jq -s '.' "$ND" > "$ITEMS"
    echo " -> kept $(jq length "$ITEMS") items for query: $q" >&2
  else
    echo " -> no valid object items for query: $q" >&2
  fi

  i=$((i+1))
done

# Combine all per-query item arrays safely
shopt -s nullglob
ITEM_FILES=("$TMP_DIR"/items_*.json)
if [ "${#ITEM_FILES[@]}" -gt 0 ]; then
  # Ensure each file is valid JSON array before adding
  valid_list=()
  for f in "${ITEM_FILES[@]}"; do
    if jq empty "$f" 2>/dev/null && [ "$(jq length "$f")" -ge 1 ]; then
      valid_list+=("$f")
    else
      echo "Skipping invalid/empty file: $f" >&2
    fi
  done

  if [ "${#valid_list[@]}" -gt 0 ]; then
    jq -s 'add | unique_by(.url)' "${valid_list[@]}" > "$OUTFILE" || { echo "Final jq combine failed" >&2; echo "[]" > "$OUTFILE"; }
  else
    echo "No valid item files to combine" >&2
    echo "[]" > "$OUTFILE"
  fi
else
  echo "No item files found" >&2
  echo "[]" > "$OUTFILE"
fi

COUNT=$(jq length "$OUTFILE" 2>/dev/null || echo 0)
echo "Collected $COUNT repos" >&2
jq . "$OUTFILE"

