#!/usr/bin/env bash
set -euo pipefail

# Score a list of repos (JSON array from collector) and output sorted array.
# Simple heuristic:
# - recency score from pushedAt (days)
# - star score
# - topic match bonus

INFILE=${1:-data/raw_repos.json}
OUTFILE=${2:-data/scored_repos.json}

now_epoch=$(date +%s)

jq --arg now "$now_epoch" '
  map(
    . as $r |
    (
      ($now|tonumber) as $now
      | ($r.pushedAt // $r.createdAt) as $ts
      | ($ts|fromdateiso8601) as $pushed
      | ($now - ($pushed|floor)) / 86400 as $age_days
    )
    | .score = (
        (max(0; 30 - $age_days) / 30) * 50
        + (.stargazerCount // 0) * 1
        + ((.topics | length) * 2)
      )
  )
  | sort_by(-.score)
' "$INFILE" > "$OUTFILE"

jq . "$OUTFILE"
