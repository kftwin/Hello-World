#!/usr/bin/env bash
# setup-cron.sh
# Installs a daily cron job to run the researcher agent at 7:00 AM UTC.
#
# Usage:
#   bash scripts/setup-cron.sh
#   bash scripts/setup-cron.sh --remove   # remove the cron job

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_DIR/scripts/daily-digest.sh"
CRON_MARKER="# researcher-agent-daily-digest"
# Runs at 7:00 AM UTC every day
CRON_ENTRY="0 7 * * * bash $SCRIPT >> $REPO_DIR/digests/.log 2>&1 $CRON_MARKER"

if [[ "${1:-}" == "--remove" ]]; then
  echo "Removing researcher agent cron job..."
  crontab -l 2>/dev/null | grep -v "$CRON_MARKER" | crontab -
  echo "Done. Cron job removed."
  exit 0
fi

# Check if already installed
if crontab -l 2>/dev/null | grep -q "$CRON_MARKER"; then
  echo "Cron job already installed:"
  crontab -l | grep "$CRON_MARKER"
  exit 0
fi

# Make script executable
chmod +x "$SCRIPT"

# Add to crontab
(crontab -l 2>/dev/null; echo "$CRON_ENTRY") | crontab -

echo "Cron job installed. Researcher agent will run daily at 7:00 AM UTC."
echo ""
echo "Entry added:"
echo "  $CRON_ENTRY"
echo ""
echo "To remove: bash scripts/setup-cron.sh --remove"
echo "To run now: bash scripts/daily-digest.sh"
