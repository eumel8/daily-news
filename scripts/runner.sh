#!/usr/bin/env bash
set -euo pipefail

# Run full pipeline
scripts/collector.sh
scripts/scorer.sh
scripts/create_issues.sh data/scored_repos.json state.json

