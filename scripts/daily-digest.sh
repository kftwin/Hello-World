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
STATUS_FILE="$REPO_DIR/status/agents.json"

log() { echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" | tee -a "$LOG_FILE"; }

update_status() {
  local status="$1" message="$2" output="${3:-}"
  local now; now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  python3 -c "
import json
with open('$STATUS_FILE') as f:
    d = json.load(f)
d['last_updated'] = '$now'
r = d['agents'].setdefault('researcher', {})
r['status'] = '$status'
r['message'] = '$message'
r['last_run'] = '$now'
r['pid'] = None
if '$output':
    r['last_output'] = '$output'
with open('$STATUS_FILE', 'w') as f:
    json.dump(d, f, indent=2)
" 2>/dev/null || true
}

notify() { bash "$REPO_DIR/scripts/notify.sh" "$@" 2>/dev/null || true; }

# ── Start ────────────────────────────────────────────────────────────────────

log "Starting researcher agent for $DATE"
update_status "running" "Researching trends for $DATE"
notify "researcher" "Starting daily research for $DATE" "hourglass_flowing_sand"

# Skip if digest already exists for today
if [[ -f "$OUTPUT_FILE" ]]; then
  log "Digest already exists at $OUTPUT_FILE — skipping."
  update_status "done" "Digest already existed for $DATE" "$OUTPUT_FILE"
  exit 0
fi

# ── Run agent ────────────────────────────────────────────────────────────────

notify "researcher" "Searching web for agentic & vibe coding trends..." "mag"

claude -p \
  "You are the researcher agent. Today's date is $DATE.
  Research the top trends in agentic workflows and vibe coding.
  Save your digest to: $OUTPUT_FILE
  Follow the format and quality bar defined in your system prompt." \
  --allowedTools "WebSearch,WebFetch,Write,Bash" \
  --output-format text \
  2>> "$LOG_FILE"

# ── Check output ─────────────────────────────────────────────────────────────

if [[ -f "$OUTPUT_FILE" ]]; then
  log "Digest written to $OUTPUT_FILE"
  update_status "done" "Digest complete for $DATE" "$OUTPUT_FILE"
  notify "researcher" "Digest ready for $DATE — see digests/$DATE.md" "white_check_mark" "high"
else
  log "ERROR: Digest not found at $OUTPUT_FILE"
  update_status "error" "Digest file not created for $DATE"
  notify "researcher" "ERROR: Digest failed for $DATE — check logs" "x" "urgent"
  exit 1
fi

# ── Phone push (ntfy TL;DR) ──────────────────────────────────────────────────
# Android/iOS: install ntfy app → subscribe to ntfy.sh/$NTFY_TOPIC
if [[ -n "${NTFY_TOPIC:-}" ]]; then
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

  log "Push notification sent to ntfy.sh/$NTFY_TOPIC"
else
  log "NTFY_TOPIC not set — skipping phone notification."
  echo "  To enable: export NTFY_TOPIC=your-private-topic"
fi
