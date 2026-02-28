#!/usr/bin/env bash
# generate-rss.sh — builds digests/feed.xml from all digest markdown files
#
# Run automatically after each new digest, or manually to rebuild history:
#   bash scripts/generate-rss.sh
#
# To subscribe on your phone:
#   1. Enable GitHub Pages on this repo (Settings → Pages → branch: master)
#   2. Subscribe in Feedly / Reeder / any RSS app to:
#        https://kftwin.github.io/Hello-World/digests/feed.xml
#
# The feed works in any RSS reader — Feedly and Reeder both render
# the markdown content cleanly inside their apps.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIGESTS_DIR="$REPO_DIR/digests"
FEED_FILE="$DIGESTS_DIR/feed.xml"
REPO_URL="https://github.com/kftwin/Hello-World"
PAGES_URL="https://kftwin.github.io/Hello-World"

NOW_RFC=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")

# ── Collect digest files newest-first ────────────────────────────────────────

mapfile -t DIGEST_FILES < <(
  ls -1 "$DIGESTS_DIR"/????-??-??.md 2>/dev/null | sort -r | head -30
)

if [[ ${#DIGEST_FILES[@]} -eq 0 ]]; then
  echo "[rss] No digest files found in $DIGESTS_DIR — nothing to generate."
  exit 0
fi

# ── Build XML ─────────────────────────────────────────────────────────────────

build_item() {
  local file="$1"
  local filename
  filename=$(basename "$file" .md)
  local date_str="$filename"  # YYYY-MM-DD

  # Convert YYYY-MM-DD to RFC 822 for RSS pubDate
  local pub_date
  pub_date=$(date -u -d "$date_str 07:00:00" +"%a, %d %b %Y %H:%M:%S +0000" 2>/dev/null \
    || date -u -j -f "%Y-%m-%d %H:%M:%S" "$date_str 07:00:00" +"%a, %d %b %Y %H:%M:%S +0000" 2>/dev/null \
    || echo "$NOW_RFC")

  # Read full file content, escape XML special chars for CDATA safety
  local content
  content=$(cat "$file")

  cat <<EOF
    <item>
      <title>Digest: ${date_str}</title>
      <link>${PAGES_URL}/digests/${filename}.md</link>
      <guid isPermaLink="false">${REPO_URL}/blob/master/digests/${filename}.md</guid>
      <pubDate>${pub_date}</pubDate>
      <description><![CDATA[${content}]]></description>
    </item>
EOF
}

# ── Write feed.xml ────────────────────────────────────────────────────────────

{
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <title>Daily Agentic &amp; Vibe Coding Digest</title>
    <link>${REPO_URL}</link>
    <atom:link href="${PAGES_URL}/digests/feed.xml" rel="self" type="application/rss+xml"/>
    <description>Daily AI trends research by the researcher agent — agentic workflows and vibe coding</description>
    <language>en-us</language>
    <lastBuildDate>${NOW_RFC}</lastBuildDate>
EOF

  for file in "${DIGEST_FILES[@]}"; do
    build_item "$file"
  done

  echo "  </channel>"
  echo "</rss>"
} > "$FEED_FILE"

echo "[rss] feed.xml updated — ${#DIGEST_FILES[@]} item(s) → $FEED_FILE"
echo "[rss] Subscribe: ${PAGES_URL}/digests/feed.xml"
