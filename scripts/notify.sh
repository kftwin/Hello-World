#!/usr/bin/env bash
# notify.sh — shared notification helper for all agents
#
# Two modes:
#
#   1. Status ping (short text, all channels):
#        bash scripts/notify.sh <agent> <message> [emoji_tag] [priority]
#
#   2. Full digest delivery (Telegram document + TL;DR text):
#        bash scripts/notify.sh send_digest <file_path> <date>
#
# Env vars (set in ~/.bashrc or export before running):
#   NTFY_TOPIC           — ntfy.sh topic name  (status pings only)
#   TELEGRAM_BOT_TOKEN   — Telegram bot token from @BotFather
#   TELEGRAM_CHAT_ID     — your Telegram chat ID
#
# Telegram setup (2 min):
#   1. Message @BotFather on Telegram → /newbot → copy token
#   2. Message your new bot once (any text)
#   3. curl https://api.telegram.org/bot<TOKEN>/getUpdates → find "chat":{"id":...}
#   4. export TELEGRAM_BOT_TOKEN="..." TELEGRAM_CHAT_ID="..."

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Mode: send_digest ─────────────────────────────────────────────────────────
# Sends the full digest file to Telegram as a document, plus a TL;DR text msg.

if [[ "${1:-}" == "send_digest" ]]; then
  FILE="${2:-}"
  DATE="${3:-$(date +%Y-%m-%d)}"

  if [[ -z "$FILE" || ! -f "$FILE" ]]; then
    echo "[notify] send_digest: file not found: $FILE"
    exit 1
  fi

  if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
    echo "[notify] send_digest: TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID not set — skipping."
    echo "  See scripts/notify.sh header for setup instructions."
    exit 0
  fi

  TG_API="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}"

  # 1. Extract TL;DR bullets from digest
  TLDR=$(awk '/^## TL;DR/,/^---/' "$FILE" \
    | grep '^-' \
    | sed 's/^- /• /' \
    | head -5)

  # 2. Send TL;DR as text message first
  PREVIEW="📋 *Daily Digest — ${DATE}*

${TLDR:-No TL;DR found in digest.}

_Full digest attached below ↓_"

  curl -s -X POST "${TG_API}/sendMessage" \
    -F "chat_id=${TELEGRAM_CHAT_ID}" \
    -F "text=${PREVIEW}" \
    -F "parse_mode=Markdown" > /dev/null

  # 3. Send full digest as a document (opens inline on Android)
  curl -s -X POST "${TG_API}/sendDocument" \
    -F "chat_id=${TELEGRAM_CHAT_ID}" \
    -F "document=@${FILE};filename=digest-${DATE}.md" \
    -F "caption=🤖 Full digest for ${DATE}" > /dev/null

  echo "[notify] Telegram digest sent for ${DATE}"
  exit 0
fi

# ── Mode: status ping ─────────────────────────────────────────────────────────

AGENT="${1:-system}"
MESSAGE="${2:-No message}"
EMOJI="${3:-robot}"
PRIORITY="${4:-default}"

# ntfy.sh — short push notification (agent status pings)
if [[ -n "${NTFY_TOPIC:-}" ]]; then
  curl -s \
    -H "Title: [${AGENT}] ${MESSAGE}" \
    -H "Priority: ${PRIORITY}" \
    -H "Tags: ${EMOJI}" \
    -d "${MESSAGE}" \
    "https://ntfy.sh/${NTFY_TOPIC}" > /dev/null
fi

# Telegram — short text ping
if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
  TEXT="*[${AGENT}]* ${MESSAGE}"
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -F "chat_id=${TELEGRAM_CHAT_ID}" \
    -F "text=${TEXT}" \
    -F "parse_mode=Markdown" > /dev/null
fi

echo "[notify] [${AGENT}] ${MESSAGE}"
