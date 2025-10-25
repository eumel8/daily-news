# Repo: github-daily-new-repos-issues
# Purpose: Collect newest relevant GitHub repos and create daily issues with results.

# File: README.md
cat > README.md <<'README'
# github-daily-new-repos-issues

Bash-based collector that searches GitHub for fresh repos matching queries and opens GitHub Issues (one per new repo) in this repository daily.

Requirements
- GitHub CLI `gh` (v2+)
- `jq`
- `curl`
- A runner with network access (GitHub Actions recommended)

Install
- Commit this repo to GitHub.
- Enable Actions. Workflow `.github/workflows/daily.yml` runs daily and posts issues here.

Configuration
- Edit `config/queries.json` to add/remove search queries.
- Adjust scoring in `scripts/scorer.sh` if needed.

Security
- Uses `${{ secrets.GITHUB_TOKEN }}` in Actions to create issues.

README

README

# File: .gitignore
cat > .gitignore <<'GITIGNORE'
state.json
*.log
GITIGNORE

# File: config/queries.json
mkdir -p config
cat > config/queries.json <<'JSON'
[
  "topic:kubernetes language:go created:>2025-01-01", 
  "topic:observability language:go created:>2025-01-01",
  "topic:prometheus language:go created:>2025-01-01",
  "topic:terraform language:hcl created:>2025-01-01"
]
JSON

# File: scripts/collector.sh
mkdir -p scripts
cat > scripts/collector.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

# Collect repos for each query and output unified JSON array
# Requires: gh, jq
# NOTE: gh's available JSON fields vary. Use fields confirmed available by the user's gh.

QUERIES_FILE="config/queries.json"
LIMIT=30
OUTFILE="data/raw_repos.json"
mkdir -p data

jq -n '[]' > "$OUTFILE"

auth_check() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "gh CLI not found" >&2
    exit 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq not found" >&2
    exit 1
  fi
}

auth_check

for q in $(jq -r '.[]' "$QUERIES_FILE"); do
  echo "Searching: $q" >&2
  # Use fields that are available per gh output
  # available fields: name, fullName, description, url, createdAt, pushedAt, stargazersCount, owner, language, updatedAt, forksCount, size
  gh search repos "$q" --limit "$LIMIT" --json name,fullName,description,url,createdAt,pushedAt,stargazersCount,owner,language,updatedAt,forksCount --jq '.[]' \
    > /tmp/_search_results.json || true

  if [ -s /tmp/_search_results.json ]; then
    # attach query metadata
    jq --arg query "$q" '. + {__query: $query}' /tmp/_search_results.json > /tmp/_search_results_tagged.json

    # append to OUTFILE array
    jq -s '.[0] + [.[1]] | add' <(jq -s '.' "$OUTFILE") /tmp/_search_results_tagged.json > "$OUTFILE.tmp" 2>/dev/null || jq -s '.[0] + .[1]' <(jq -s '.' "$OUTFILE") /tmp/_search_results_tagged.json > "$OUTFILE.tmp"
    mv "$OUTFILE.tmp" "$OUTFILE"
    rm -f /tmp/_search_results.json /tmp/_search_results_tagged.json
  else
    echo "No results for query: $q" >&2
  fi
done

# normalize (unique by url)
jq 'unique_by(.url)' "$OUTFILE" > "$OUTFILE.tmp" && mv "$OUTFILE.tmp" "$OUTFILE"

echo "Collected $(jq length "$OUTFILE") repos" >&2
jq . "$OUTFILE"
BASH
chmod +x scripts/collector.sh

# File: scripts/scorer.sh
cat > scripts/scorer.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

# Score a list of repos (JSON array from collector) and output sorted array.
# Adjusted to use stargazersCount field as returned by gh.

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
        + (.stargazersCount // 0) * 1
        + ((.language // "") != "") * 2
      )
  )
  | sort_by(-.score)
' "$INFILE" > "$OUTFILE"

jq . "$OUTFILE"
BASH
chmod +x scripts/scorer.sh

# File: scripts/create_issues.sh
cat > scripts/create_issues.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

# Create GitHub issues for new repos.
# Uses GITHUB_REPOSITORY (owner/repo) and GITHUB_TOKEN env available in Actions.

SCORED_FILE=${1:-data/scored_repos.json}
STATE_FILE=${2:-state.json}
MAX=10

if [ -z "${GITHUB_REPOSITORY:-}" ]; then
  echo "GITHUB_REPOSITORY not set. Set TARGET_REPO env or run inside Actions." >&2
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

  # Create issue via API
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

BASH
chmod +x scripts/create_issues.sh

# File: scripts/runner.sh
cat > scripts/runner.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

# Run full pipeline
scripts/collector.sh
scripts/scorer.sh
scripts/create_issues.sh data/scored_repos.json state.json

BASH
chmod +x scripts/runner.sh

# File: .github/workflows/daily.yml
mkdir -p .github/workflows
cat > .github/workflows/daily.yml <<'YML'
name: Daily new-repos -> issues

on:
  schedule:
    - cron: '0 7 * * *' # daily at 07:00 UTC
  workflow_dispatch:

jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y jq curl
          gh --version || true
      - name: Authenticate gh (optional)
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          echo "Authenticating gh"
          echo $GITHUB_TOKEN | gh auth login --with-token || true
      - name: Run pipeline
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GITHUB_REPOSITORY: ${{ github.repository }}
        run: |
          ./scripts/runner.sh
YML

# Initial empty state
cat > state.json <<'STATE'
{"seen": []}
STATE

# Make a default git commit ready
git init -q
git add .
git commit -m "Initial commit: daily new repos collector (updated fields)" -q

# Print short ready message
cat > .ready <<'TXT'
Scaffold created and collector/scorer adjusted to gh available fields. Edit config/queries.json to refine searches.
TXT

echo "Scaffold created and fixed."

