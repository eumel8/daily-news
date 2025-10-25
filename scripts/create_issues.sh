#!/usr/bin/env bash
set -euo pipefail

# Create GitHub issues in THIS repository for discovered repos.
# Each issue contains information about a discovered repository.
# Uses GITHUB_REPOSITORY (owner/repo) and GITHUB_TOKEN env available in Actions.

SCORED_FILE=${1:-data/scored_repos.json}
STATE_FILE=${2:-state.json}
MAX=10

if [ -z "${GITHUB_REPOSITORY:-}" ]; then
  echo "GITHUB_REPOSITORY not set. This should be set automatically in GitHub Actions." >&2
  echo "If running locally, set: export GITHUB_REPOSITORY=owner/repo" >&2
  exit 1
fi

TOKEN=${GITHUB_TOKEN:-}
if [ -z "$TOKEN" ]; then
  echo "GITHUB_TOKEN not set. Provide a token with repo scope." >&2
  exit 1
fi

mkdir -p data

# Initialize state
if [ ! -f "$STATE_FILE" ]; then
  echo '{"seen": []}' > "$STATE_FILE"
fi

seen_urls=$(jq -r '.seen[]?' "$STATE_FILE" 2>/dev/null || true)

count=0

jq -c '.[]' "$SCORED_FILE" | while read -r repo; do
  url=$(echo "$repo" | jq -r '.url')
  fullName=$(echo "$repo" | jq -r '.fullName // .name')
  desc=$(echo "$repo" | jq -r '.description // "(no description)"')
  score=$(echo "$repo" | jq -r '.score')
  pushedAt=$(echo "$repo" | jq -r '.pushedAt // .createdAt')

  if echo "$seen_urls" | grep -qx "$url"; then
    continue
  fi

  if [ $count -ge $MAX ]; then
    break
  fi

  title="New repo: $fullName — score $(printf "%.1f" "$score")"
  body="Repository: $url

Description: $desc

Pushed: $pushedAt

Score: $score

Automatically discovered by github-daily-new-repos-issues."

  # Create issue in THIS repository (not in the discovered repo)
  # The issue will contain information ABOUT the discovered repo
  api_url="https://api.github.com/repos/${GITHUB_REPOSITORY}/issues"
  payload=$(jq -n --arg t "$title" --arg b "$body" '{title: $t, body: $b, labels: ["new-repo"]}')

  echo "Creating issue for $url" >&2
  resp=$(curl -sS -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json" "$api_url" -d "$payload")

  issue_url=$(echo "$resp" | jq -r '.html_url // empty')
  if [ -n "$issue_url" ]; then
    echo "$url" >> /tmp/created_urls.txt
    echo "Created: $issue_url" >&2
  else
    echo "Failed to create issue for $url: $resp" >&2
  fi

  count=$((count+1))
done

# update state
if [ -f /tmp/created_urls.txt ]; then
  while read -r l; do
    jq --arg v "$l" '.seen += [$v]' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
  done < /tmp/created_urls.txt
fi

# compact state
jq '{seen: (.seen | unique)}' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

