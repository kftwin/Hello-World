#!/usr/bin/env bash
# daily-digest.sh
# Runs the researcher subagent in headless mode to produce today's digest,
# then pushes a summary to your phone via ntfy.sh (free push notifications).
#
# Setup:
#   1. Install "ntfy" app on Android (https://ntfy.sh)
#   2. Subscribe to your private topic: ntfy.sh/YOUR_TOPIC
#   3. Set NTFY_TOPIC in your environment or .env.local:
#        export NTFY_TOPIC="my-digest-abc123"
#
# Usage:
#   bash scripts/daily-digest.sh              # today's digest
#   bash scripts/daily-digest.sh 2026-03-01   # specific date

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATE="${1:-$(date +%Y-%m-%d)}"
OUTPUT_FILE="$REPO_DIR/digests/$DATE.md"
LOG_FILE="$REPO_DIR/digests/.log"

echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Starting researcher agent for $DATE" | tee -a "$LOG_FILE"

# Skip if digest already exists for today
if [[ -f "$OUTPUT_FILE" ]]; then
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Digest already exists at $OUTPUT_FILE — skipping." | tee -a "$LOG_FILE"
  exit 0
fi

# Run the researcher agent in headless mode
# The agent reads its instructions from .claude/agents/researcher.md
claude -p \
  "You are the researcher agent. Today's date is $DATE.
  Research the top trends in agentic workflows and vibe coding.
  Save your digest to: $OUTPUT_FILE
  Follow the format and quality bar defined in your system prompt." \
  --allowedTools "WebSearch,WebFetch,Write,Bash" \
  --output-format text \
  2>> "$LOG_FILE"

if [[ -f "$OUTPUT_FILE" ]]; then
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Digest written to $OUTPUT_FILE" | tee -a "$LOG_FILE"
else
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] ERROR: Digest not found at $OUTPUT_FILE" | tee -a "$LOG_FILE"
  exit 1
fi

# ── Phone notification via ntfy.sh ──────────────────────────────────────────
# Requires: export NTFY_TOPIC="your-private-topic" (set in ~/.bashrc or .env.local)
# Android: install ntfy app → subscribe to ntfy.sh/$NTFY_TOPIC
# iOS:     install ntfy app → subscribe to ntfy.sh/$NTFY_TOPIC
if [[ -n "${NTFY_TOPIC:-}" ]]; then
  # Extract TL;DR section for the push notification body
  TLDR=$(awk '/^## TL;DR/,/^---/' "$OUTPUT_FILE" \
    | grep '^-' \
    | sed 's/^- /• /' \
    | head -5 \
    | tr '\n' ' ')

  curl -s \
    -H "Title: 🤖 Daily Digest — $DATE" \
    -H "Priority: default" \
    -H "Tags: robot,newspaper" \
    -d "${TLDR:-See digest for $DATE}" \
    "https://ntfy.sh/$NTFY_TOPIC" >> "$LOG_FILE" 2>&1

  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Push notification sent to ntfy.sh/$NTFY_TOPIC" | tee -a "$LOG_FILE"
else
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] NTFY_TOPIC not set — skipping phone notification." | tee -a "$LOG_FILE"
  echo "  To enable: export NTFY_TOPIC=your-private-topic"
fi
