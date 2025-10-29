# github-daily-new-repos-issues

Bash-based collector that searches GitHub for fresh repos matching queries and opens GitHub Issues (one per new repo) in this repository daily. Designed to provide diverse, interesting daily news digests from millions of GitHub repositories.

## Features

- 🔄 **Smart State Management**: Tracks seen repos in git to prevent duplicates across runs
- 📊 **Intelligent Scoring**: Multi-factor scoring algorithm that balances recency, popularity, and diversity
- 🎲 **Randomization**: Adds variety to results to prevent the same repos appearing daily
- 🌈 **Diverse Queries**: Searches across multiple languages, topics, and criteria
- 📈 **Detailed Reports**: Issues include score breakdowns and comprehensive repo info

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

- Edit `MAX=10` in `scripts/create_issues.sh` to change number of daily issues
- Adjust scoring weights in `scripts/scorer.sh` for different priorities
- Modify search queries in `config/queries.json` for your interests

## How It Works

1. **Collector** (`scripts/collector.sh`): Searches GitHub using queries, collects unique repos
2. **Scorer** (`scripts/scorer.sh`): Applies multi-factor scoring algorithm with diversity features
3. **Issue Creator** (`scripts/create_issues.sh`): Creates formatted issues for top repos, updates state
4. **State Persistence**: Workflow commits `state.json` back to repo to track seen repos

## Security

- Uses `${{ secrets.GITHUB_TOKEN }}` in Actions to create issues
- No external API calls except to GitHub
- State file tracked in git for transparency

