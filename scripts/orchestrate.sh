#!/usr/bin/env bash
# orchestrate.sh — control panel for all background agents
#
# Commands:
#   start [agent]   Launch agent(s) in the background
#   stop  [agent]   Stop running agent(s)
#   status          Show live status of all agents
#   logs  [agent]   Tail agent logs
#   run   <agent>   Run an agent now (foreground, blocking)
#
# Examples:
#   bash scripts/orchestrate.sh start            # start all agents
#   bash scripts/orchestrate.sh start researcher
#   bash scripts/orchestrate.sh status
#   bash scripts/orchestrate.sh logs researcher
#   bash scripts/orchestrate.sh stop

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATUS_FILE="$REPO_DIR/status/agents.json"
PID_DIR="$REPO_DIR/status/pids"
LOG_DIR="$REPO_DIR/digests"

mkdir -p "$PID_DIR"

# ── Helpers ───────────────────────────────────────────────────────────────────

update_status() {
  local agent="$1" status="$2" message="$3"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Simple in-place JSON update without jq dependency
  python3 -c "
import json, sys
with open('$STATUS_FILE') as f:
    d = json.load(f)
d['last_updated'] = '$now'
d['agents'].setdefault('$agent', {})
d['agents']['$agent']['status'] = '$status'
d['agents']['$agent']['message'] = '$message'
d['agents']['$agent']['last_run'] = '$now'
with open('$STATUS_FILE', 'w') as f:
    json.dump(d, f, indent=2)
" 2>/dev/null || true
}

is_running() {
  local agent="$1"
  local pid_file="$PID_DIR/$agent.pid"
  if [[ -f "$pid_file" ]]; then
    local pid
    pid=$(cat "$pid_file")
    if kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
    rm -f "$pid_file"
  fi
  return 1
}

# ── Commands ──────────────────────────────────────────────────────────────────

cmd_start() {
  local target="${1:-all}"

  start_researcher() {
    if is_running "researcher"; then
      echo "  researcher: already running (pid $(cat "$PID_DIR/researcher.pid"))"
      return
    fi
    echo "  Starting researcher..."
    bash "$REPO_DIR/scripts/notify.sh" "orchestrator" "Starting researcher agent" "rocket" &>/dev/null || true
    bash "$REPO_DIR/scripts/daily-digest.sh" >> "$LOG_DIR/.log" 2>&1 &
    local pid=$!
    echo "$pid" > "$PID_DIR/researcher.pid"
    update_status "researcher" "running" "Started (pid $pid)"
    echo "  researcher: started (pid $pid)"
    echo "  researcher: tailing logs → digests/.log"
  }

  echo "=== orchestrate: start ==="
  case "$target" in
    all | researcher) start_researcher ;;
    *) echo "Unknown agent: $target"; exit 1 ;;
  esac
  echo ""
  echo "Run 'bash scripts/orchestrate.sh status' to monitor."
}

cmd_stop() {
  local target="${1:-all}"

  stop_agent() {
    local agent="$1"
    local pid_file="$PID_DIR/$agent.pid"
    if [[ -f "$pid_file" ]]; then
      local pid
      pid=$(cat "$pid_file")
      if kill "$pid" 2>/dev/null; then
        echo "  $agent: stopped (pid $pid)"
        update_status "$agent" "idle" "Stopped manually"
        bash "$REPO_DIR/scripts/notify.sh" "orchestrator" "$agent stopped" "stop_sign" &>/dev/null || true
      else
        echo "  $agent: not running"
      fi
      rm -f "$pid_file"
    else
      echo "  $agent: not running"
    fi
  }

  echo "=== orchestrate: stop ==="
  case "$target" in
    all)
      for pid_file in "$PID_DIR"/*.pid; do
        [[ -f "$pid_file" ]] || continue
        agent=$(basename "$pid_file" .pid)
        stop_agent "$agent"
      done
      ;;
    *) stop_agent "$target" ;;
  esac
}

cmd_status() {
  echo "=== Agent Status Board =========================="
  echo ""

  # Read agents.json
  if [[ ! -f "$STATUS_FILE" ]]; then
    echo "  No status file found at $STATUS_FILE"
    exit 1
  fi

  python3 -c "
import json, os, datetime

with open('$STATUS_FILE') as f:
    d = json.load(f)

updated = d.get('last_updated', 'never')
print(f'  Last updated: {updated}')
print()

status_icons = {
    'idle':    '⏸  idle   ',
    'running': '🔄 running',
    'done':    '✅ done   ',
    'error':   '❌ error  ',
}

for name, info in d.get('agents', {}).items():
    status = info.get('status', 'unknown')
    icon = status_icons.get(status, '❓ unknown')
    message = info.get('message', '')
    last_run = info.get('last_run', 'never')
    last_output = info.get('last_output', '')
    next_run = info.get('next_run', '')
    pid = info.get('pid', '')

    print(f'  {icon}  [{name}]')
    print(f'           message:  {message}')
    print(f'           last run: {last_run}')
    if last_output:
        print(f'           output:   {last_output}')
    if next_run:
        print(f'           next:     {next_run}')
    if pid:
        print(f'           pid:      {pid}')
    print()
" 2>/dev/null

  # Cross-check with live pids
  echo "  Live processes:"
  for pid_file in "$PID_DIR"/*.pid 2>/dev/null; do
    [[ -f "$pid_file" ]] || continue
    agent=$(basename "$pid_file" .pid)
    pid=$(cat "$pid_file")
    if kill -0 "$pid" 2>/dev/null; then
      echo "    ✅ $agent running (pid $pid)"
    else
      echo "    ❌ $agent pid $pid dead (stale)"
      rm -f "$pid_file"
    fi
  done
  echo ""
  echo "  Cron jobs:"
  crontab -l 2>/dev/null | grep "researcher-agent" || echo "    (none installed — run: bash scripts/setup-cron.sh)"
  echo "================================================="
}

cmd_logs() {
  local agent="${1:-}"
  local log="$LOG_DIR/.log"
  echo "=== Logs: $log ==="
  if [[ -f "$log" ]]; then
    tail -50 "$log"
  else
    echo "  No log file yet."
  fi
}

cmd_run() {
  local agent="${1:-}"
  case "$agent" in
    researcher)
      echo "Running researcher now (foreground)..."
      bash "$REPO_DIR/scripts/notify.sh" "orchestrator" "Manual run: researcher" "runner" &>/dev/null || true
      bash "$REPO_DIR/scripts/daily-digest.sh"
      ;;
    "")
      echo "Usage: orchestrate.sh run <agent>"
      echo "Agents: researcher"
      exit 1
      ;;
    *)
      echo "Unknown agent: $agent"
      exit 1
      ;;
  esac
}

cmd_help() {
  cat <<'EOF'
orchestrate.sh — agent control panel

  start [agent]    Launch agent(s) in the background (default: all)
  stop  [agent]    Stop running agent(s)           (default: all)
  status           Live status of all agents
  logs  [agent]    Tail agent logs
  run   <agent>    Run agent now (foreground)

Agents: researcher

Environment:
  NTFY_TOPIC            ntfy.sh topic for phone push notifications
  TELEGRAM_BOT_TOKEN    Telegram bot token
  TELEGRAM_CHAT_ID      Telegram chat ID

Examples:
  bash scripts/orchestrate.sh start
  bash scripts/orchestrate.sh status
  bash scripts/orchestrate.sh run researcher
  bash scripts/orchestrate.sh logs
  bash scripts/orchestrate.sh stop
EOF
}

# ── Dispatch ─────────────────────────────────────────────────────────────────

CMD="${1:-help}"
shift || true

case "$CMD" in
  start)  cmd_start "$@" ;;
  stop)   cmd_stop "$@" ;;
  status) cmd_status ;;
  logs)   cmd_logs "$@" ;;
  run)    cmd_run "$@" ;;
  help|--help|-h) cmd_help ;;
  *)
    echo "Unknown command: $CMD"
    cmd_help
    exit 1
    ;;
esac
