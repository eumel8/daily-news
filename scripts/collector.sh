#!/usr/bin/env bash
set -euo pipefail

QUERIES_FILE="config/queries.json"
LIMIT=30
OUTFILE="data/raw_repos.json"
TMP_COMBINED="/tmp/_combined.json"
mkdir -p data
rm -f "$TMP_COMBINED"

echo "[]" > "$OUTFILE"

for q in $(jq -r '.[]' "$QUERIES_FILE"); do
  echo "Searching: $q" >&2
  TMP="/tmp/_res.json"
  if ! gh search repos "$q" --limit "$LIMIT" \
    --json name,fullName,description,url,createdAt,pushedAt,stargazersCount,owner,language,updatedAt,forksCount \
    > "$TMP" 2>/dev/null; then
      echo "gh search failed for: $q" >&2
      continue
  fi

  # Valid JSON and nonempty?
  if ! jq empty "$TMP" 2>/dev/null; then
    echo "Invalid JSON returned, skipping: $q" >&2
    continue
  fi
  if [ "$(jq length "$TMP")" -eq 0 ]; then
    echo "No results for $q" >&2
    continue
  fi

  # Append tagged objects
  jq --arg query "$q" '.[] | . + {__query: $query}' "$TMP" >> "$TMP_COMBINED"
done

# Combine and deduplicate safely
if [ -s "$TMP_COMBINED" ]; then
  # Ensure valid array even if file has multiple concatenated objects
  jq -s 'unique_by(.url)' "$TMP_COMBINED" > "$OUTFILE" || {
    echo "jq combine failed, writing empty output" >&2
    echo "[]" > "$OUTFILE"
  }
else
  echo "No combined results found" >&2
  echo "[]" > "$OUTFILE"
fi

COUNT=$(jq length "$OUTFILE" 2>/dev/null || echo 0)
echo "Collected $COUNT repos" >&2
jq . "$OUTFILE"

