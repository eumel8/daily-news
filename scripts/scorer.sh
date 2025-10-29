#!/usr/bin/env bash
set -euo pipefail

# Score a list of repos (JSON array from collector) and output sorted array.
# Enhanced scoring for diversity and freshness.

INFILE=${1:-data/raw_repos.json}
OUTFILE=${2:-data/scored_repos.json}

now_epoch=$(date +%s)

jq --arg now "$now_epoch" '
  map(
    ($now|tonumber) as $now_num
    | (.pushedAt // .createdAt) as $ts
    | ($ts|fromdateiso8601) as $pushed
    | (($now_num - ($pushed|floor)) / 3600) as $age_hours
    | (($now_num - ($pushed|floor)) / 86400) as $age_days

    # Recency score: exponential decay favoring very recent repos
    # Full 50 points for repos < 6 hours old, decaying exponentially after
    | (if $age_hours < 6 then 50
       elif $age_hours < 24 then 50 * (0.7 + (24 - $age_hours) / 24 * 0.3)
       elif $age_days < 3 then 40 * (1 - ($age_days - 1) / 5)
       elif $age_days < 7 then 25 * (1 - ($age_days - 3) / 7)
       else 10
       end) as $recency_score

    # Star score: logarithmic scale to prevent dominance of highly-starred repos
    # Cap at 30 points max
    | (.stargazersCount // 0) as $stars
    | (if $stars == 0 then 0
       elif $stars < 5 then $stars * 2
       elif $stars < 20 then 10 + (($stars - 5) * 1)
       elif $stars < 100 then 25 + ((($stars - 20) | log) * 2)
       else 30
       end) as $star_score

    # Activity score: forks and recent updates
    | ((.forksCount // 0) | if . > 10 then 10 else . end) as $fork_score
    | (if (.language // "") != "" then 5 else 0 end) as $language_bonus
    | (if (.description // "") != "" then 3 else 0 end) as $description_bonus

    # Randomization factor: -10 to +10 points for diversity
    # Using repo URL as seed for deterministic but varied results
    | ((.url | tostring | length) % 21 - 10) as $random_factor

    | .score = ($recency_score + $star_score + $fork_score + $language_bonus + $description_bonus + $random_factor)
    | .score_breakdown = {
        recency: $recency_score,
        stars: $star_score,
        forks: $fork_score,
        language: $language_bonus,
        description: $description_bonus,
        random: $random_factor,
        age_hours: $age_hours
      }
  )
  | sort_by(-.score)
' "$INFILE" > "$OUTFILE"

jq . "$OUTFILE"
