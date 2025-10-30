# github-daily-new-repos-issues

Bash-based collector that searches GitHub for fresh repos matching queries and opens GitHub Issues (one per new repo) in this repository daily. Designed to provide diverse, interesting daily news digests from millions of GitHub repositories.

## Features

- 🔄 **Smart State Management**: Tracks seen repos in git to prevent duplicates across runs
- 🗃️ **Persistent Data Storage**: Maintains historical database of all discovered repos with automatic deduplication
- 🧹 **Automatic Pruning**: Configurable retention period (default 30 days) prevents data files from growing indefinitely
- 📊 **Intelligent Scoring**: Multi-factor scoring algorithm that balances recency, popularity, and diversity
- 🎲 **Randomization**: Adds variety to results to prevent the same repos appearing daily
- 🌈 **Diverse Queries**: Searches across multiple languages, topics, and criteria
- 📈 **Detailed Reports**: Issues include score breakdowns and comprehensive repo info
- 🚫 **Duplicate Prevention**: Filters repos against both historical data and state file to ensure truly new discoveries

## Requirements

- GitHub CLI `gh` (v2+)
- `jq`
- `curl`
- A runner with network access (GitHub Actions recommended)

## Install

1. Commit this repo to GitHub
2. Enable Actions - Workflow `.github/workflows/daily.yml` runs daily at 07:00 UTC
3. The workflow will automatically commit state files back to track seen repos

## Configuration

### Queries (`config/queries.json`)

Add or modify search queries. Supports:
- Topic-based searches: `topic:kubernetes language:go created:>{{YESTERDAY}}`
- Star/activity filters: `language:rust stars:>3 pushed:>{{YESTERDAY}}`
- Multiple languages and topics for diversity

The `{{YESTERDAY}}` placeholder is automatically replaced with yesterday's date.

### Scoring Algorithm (`scripts/scorer.sh`)

The scoring algorithm uses multiple factors:

1. **Recency Score (max 50 points)**: Exponential decay favoring very fresh repos
   - Repos < 6 hours old: 50 points
   - Repos < 24 hours old: 35-50 points
   - Older repos: decreasing score

2. **Star Score (max 30 points)**: Logarithmic scale to prevent dominance
   - Caps at 30 points to give newer repos a chance
   - 0-5 stars: 2 points each
   - 5-20 stars: 1 point each
   - 20+ stars: logarithmic scaling

3. **Activity Score**: Forks (max 10 points) + language (5 points) + description (3 points)

4. **Randomization (-10 to +10 points)**: Adds variety using repo URL as seed

### Customization

- **Number of daily issues**: Edit `MAX=10` in `scripts/create_issues.sh`
- **Scoring weights**: Adjust values in `scripts/scorer.sh` for different priorities
- **Search queries**: Modify `config/queries.json` for your interests
- **Data retention**: Set `RETENTION_DAYS` environment variable (default: 30 days)
  - In GitHub Actions workflow: Add `RETENTION_DAYS: 60` to env vars
  - When running locally: `export RETENTION_DAYS=60 && ./scripts/runner.sh`
  - Lower values keep data files smaller; higher values prevent rediscovering recently seen repos

## How It Works

1. **Collector** (`scripts/collector.sh`):
   - Loads existing repos from `data/raw_repos.json` and `state.json`
   - Searches GitHub using configured queries
   - Filters out previously discovered repos (deduplication)
   - Merges new discoveries with historical data
   - Prunes repos older than retention period (default: 30 days)
   - Outputs only truly new repos for scoring

2. **Scorer** (`scripts/scorer.sh`): Applies multi-factor scoring algorithm with diversity features to new repos

3. **Issue Creator** (`scripts/create_issues.sh`): Creates formatted issues for top-scored repos, updates state

4. **State Persistence**: Workflow commits both `state.json` and `data/` back to repo for next run

### Deduplication Strategy

The collector implements a multi-layered deduplication approach:
- **Historical data** (`data/raw_repos.json`): All repos ever discovered (pruned by age)
- **State file** (`state.json`): Repos for which issues have been created
- **Current run**: Deduplicates within the current search results

This ensures that repos are only discovered once and never re-processed, even across multiple runs.

## Security

- Uses `${{ secrets.GITHUB_TOKEN }}` in Actions to create issues
- No external API calls except to GitHub
- State file tracked in git for transparency

