#!/usr/bin/env bash
set -euo pipefail

# Score a list of repos (JSON array from collector) and output sorted array.
# Adjusted to use stargazersCount field as returned by gh.

INFILE=${1:-data/raw_repos.json}
OUTFILE=${2:-data/scored_repos.json}

now_epoch=$(date +%s)

jq --arg now "$now_epoch" '
  map(
    ($now|tonumber) as $now_num
    | (.pushedAt // .createdAt) as $ts
    | ($ts|fromdateiso8601) as $pushed
    | (($now_num - ($pushed|floor)) / 86400) as $age_days
    | .score = (
        (([0, 30 - $age_days] | max) / 30) * 50
        + (.stargazersCount // 0) * 1
        + (if (.language // "") != "" then 2 else 0 end)
      )
  )
  | sort_by(-.score)
' "$INFILE" > "$OUTFILE"

jq . "$OUTFILE"
