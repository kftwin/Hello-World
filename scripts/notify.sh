#!/usr/bin/env bash
# notify.sh — shared notification helper for all agents
#
# Sends to ntfy.sh (push) and optionally Telegram (rich markdown).
# Both channels are opt-in via env vars.
#
# Usage:
#   bash scripts/notify.sh <agent> <message> [emoji_tag] [priority]
#
# Examples:
#   bash scripts/notify.sh "researcher" "Digest ready for 2026-02-28" "white_check_mark"
#   bash scripts/notify.sh "orchestrator" "All agents complete" "tada" "high"
#
# Env vars (set in ~/.bashrc or export before running):
#   NTFY_TOPIC       — ntfy.sh topic name (e.g. my-digest-abc123)
#   TELEGRAM_BOT_TOKEN — Telegram bot token from @BotFather
#   TELEGRAM_CHAT_ID   — your Telegram chat ID

set -euo pipefail

AGENT="${1:-system}"
MESSAGE="${2:-No message}"
EMOJI="${3:-robot}"
PRIORITY="${4:-default}"

# ── ntfy.sh ──────────────────────────────────────────────────────────────────
if [[ -n "${NTFY_TOPIC:-}" ]]; then
  curl -s \
    -H "Title: [${AGENT}] ${MESSAGE}" \
    -H "Priority: ${PRIORITY}" \
    -H "Tags: ${EMOJI}" \
    -d "${MESSAGE}" \
    "https://ntfy.sh/${NTFY_TOPIC}" > /dev/null
fi

# ── Telegram ─────────────────────────────────────────────────────────────────
# Setup: message @BotFather → /newbot → get token
#        then message your bot once → get your chat_id via:
#        curl https://api.telegram.org/bot<TOKEN>/getUpdates
if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
  TEXT="*\[${AGENT}\]* ${MESSAGE}"
  curl -s \
    -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    -d "text=${TEXT}" \
    -d "parse_mode=Markdown" > /dev/null
fi

echo "[notify] [${AGENT}] ${MESSAGE}"
