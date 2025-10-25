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

