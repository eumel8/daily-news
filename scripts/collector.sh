#!/usr/bin/env bash
set -euo pipefail

QUERIES_FILE="config/queries.json"
LIMIT=30
OUTFILE="data/raw_repos.json"
STATE_FILE="state.json"
RETENTION_DAYS=${RETENTION_DAYS:-30}  # Keep repos from last N days, configurable via env var
mkdir -p data
TMP_DIR="/tmp/ghcollector"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# Load existing data to avoid re-collecting the same repos
EXISTING_URLS=""
EXISTING_COUNT=0
if [ -f "$OUTFILE" ]; then
  EXISTING_URLS=$(jq -r '.[].url // empty' "$OUTFILE" 2>/dev/null || true)
  if [ -n "$EXISTING_URLS" ]; then
    EXISTING_COUNT=$(echo "$EXISTING_URLS" | wc -l | tr -d ' ')
    echo "Loaded $EXISTING_COUNT existing repo URLs from $OUTFILE" >&2
  else
    echo "No existing repos in $OUTFILE" >&2
  fi
fi

# Also load URLs from state file (repos with created issues)
if [ -f "$STATE_FILE" ]; then
  STATE_URLS=$(jq -r '.seen[]? // empty' "$STATE_FILE" 2>/dev/null || true)
  if [ -n "$STATE_URLS" ]; then
    STATE_COUNT=$(echo "$STATE_URLS" | wc -l | tr -d ' ')
    EXISTING_URLS=$(printf "%s\n%s" "$EXISTING_URLS" "$STATE_URLS" | sort -u)
    echo "Added $STATE_COUNT URLs from state file" >&2
  fi
fi

if [ -n "$EXISTING_URLS" ]; then
  TOTAL_EXISTING=$(echo "$EXISTING_URLS" | wc -l | tr -d ' ')
  echo "Total existing URLs to filter: $TOTAL_EXISTING" >&2
else
  echo "No existing URLs to filter" >&2
fi

# Calculate yesterday's date in YYYY-MM-DD format
# Works on both Linux (date -d) and macOS (date -v)
YESTERDAY=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d 2>/dev/null)
echo "Using date filter: created:>$YESTERDAY" >&2

# Sammle alle Einzelergebnisse als separate Arrays
i=0
while IFS= read -r q; do
  # Replace {{YESTERDAY}} placeholder with actual date
  q=$(echo "$q" | sed "s/{{YESTERDAY}}/$YESTERDAY/g")
  echo "Searching: $q" >&2
  FILE="$TMP_DIR/q_${i}.json"
  if gh search repos "$q" --limit "$LIMIT" \
      --json name,fullName,description,url,createdAt,pushedAt,stargazersCount,owner,language,updatedAt,forksCount \
      >"$FILE" 2>/dev/null; then
    if jq -e 'type == "array"' "$FILE" >/dev/null 2>&1; then
      if jq --arg query "$q" '[.[] | select(type=="object" and has("url")) | . + {__query: $query}]' "$FILE" >"$TMP_DIR/clean_${i}.json" 2>/dev/null; then
        : # Success
      else
        echo "Failed to process results for query: $q" >&2
        echo "[]" >"$TMP_DIR/clean_${i}.json"
      fi
    else
      echo "Invalid JSON format (not an array) for query: $q" >&2
      echo "[]" >"$TMP_DIR/clean_${i}.json"
    fi
  else
    echo "gh search failed for: $q" >&2
    echo "[]" >"$TMP_DIR/clean_${i}.json"
  fi
  i=$((i+1))
done < <(jq -r '.[]' "$QUERIES_FILE")

# Kombiniere alle Arrays in eine Liste und entferne Duplikate
NEW_REPOS_FILE="$TMP_DIR/new_repos.json"
if ls "$TMP_DIR"/clean_*.json >/dev/null 2>&1; then
  jq -s 'add | unique_by(.url)' "$TMP_DIR"/clean_*.json >"$NEW_REPOS_FILE" || echo "[]" >"$NEW_REPOS_FILE"
else
  echo "[]" >"$NEW_REPOS_FILE"
fi

# Filter out repos that already exist
if [ -n "$EXISTING_URLS" ] && [ "$(jq length "$NEW_REPOS_FILE")" -gt 0 ]; then
  echo "$EXISTING_URLS" > "$TMP_DIR/existing_urls.txt"
  # Create a jq filter to exclude existing URLs
  FILTERED_NEW=$(jq --slurpfile existing <(echo "$EXISTING_URLS" | jq -R . | jq -s .) '
    map(select(.url as $url | ($existing[0] | map(. == $url) | any) | not))
  ' "$NEW_REPOS_FILE")
  echo "$FILTERED_NEW" > "$NEW_REPOS_FILE"
  NEW_COUNT=$(echo "$FILTERED_NEW" | jq length)
  echo "Found $NEW_COUNT truly new repos (after filtering)" >&2
else
  NEW_COUNT=$(jq length "$NEW_REPOS_FILE" 2>/dev/null || echo 0)
  echo "Found $NEW_COUNT new repos (no existing data to filter)" >&2
fi

# Merge new repos with existing data (keep historical data)
if [ -f "$OUTFILE" ] && [ "$(jq length "$OUTFILE" 2>/dev/null || echo 0)" -gt 0 ]; then
  jq -s 'add | unique_by(.url)' "$OUTFILE" "$NEW_REPOS_FILE" > "$TMP_DIR/merged.json"
  mv "$TMP_DIR/merged.json" "$OUTFILE"
  echo "Merged with existing data" >&2
else
  cp "$NEW_REPOS_FILE" "$OUTFILE"
  echo "Created new data file" >&2
fi

# Prune old entries to prevent unlimited growth
CUTOFF_DATE=$(date -d "$RETENTION_DAYS days ago" +%Y-%m-%d 2>/dev/null || date -v-${RETENTION_DAYS}d +%Y-%m-%d 2>/dev/null)
CUTOFF_EPOCH=$(date -d "$CUTOFF_DATE" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$CUTOFF_DATE" +%s 2>/dev/null)
echo "Pruning repos older than $CUTOFF_DATE (keeping last $RETENTION_DAYS days)" >&2

BEFORE_PRUNE=$(jq length "$OUTFILE" 2>/dev/null || echo 0)
jq --arg cutoff "$CUTOFF_EPOCH" '
  map(
    select(
      (.pushedAt // .createdAt // .updatedAt) as $ts
      | ($ts | fromdateiso8601) >= ($cutoff | tonumber)
    )
  )
' "$OUTFILE" > "$TMP_DIR/pruned.json"
mv "$TMP_DIR/pruned.json" "$OUTFILE"

AFTER_PRUNE=$(jq length "$OUTFILE" 2>/dev/null || echo 0)
PRUNED_COUNT=$((BEFORE_PRUNE - AFTER_PRUNE))
if [ $PRUNED_COUNT -gt 0 ]; then
  echo "Pruned $PRUNED_COUNT old repos" >&2
fi

TOTAL_COUNT=$(jq length "$OUTFILE" 2>/dev/null || echo 0)
echo "Total repos in database: $TOTAL_COUNT (including $NEW_COUNT new, $PRUNED_COUNT pruned)" >&2

# Output only the new repos for this run (for pipeline processing)
jq . "$NEW_REPOS_FILE"
