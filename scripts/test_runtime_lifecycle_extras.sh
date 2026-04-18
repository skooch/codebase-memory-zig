#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BINARY="${CODEBASE_MEMORY_ZIG_BIN:-$ROOT_DIR/zig-out/bin/cbm}"

if [ ! -x "$BINARY" ]; then
  zig build >/dev/null
fi

TMPDIR="$(mktemp -d)"
TMPDIR="$(cd "$TMPDIR" && pwd -P)"
LIVE_PID=""

cleanup() {
  exec 3>&- 2>/dev/null || true
  if [ -n "$LIVE_PID" ] && kill -0 "$LIVE_PID" 2>/dev/null; then
    kill "$LIVE_PID" 2>/dev/null || true
    wait "$LIVE_PID" 2>/dev/null || true
  fi
  rm -rf "$TMPDIR"
}

trap cleanup EXIT

CACHE_DIR="$TMPDIR/cache"
DB_PATH="$CACHE_DIR/codebase-memory-zig.db"
mkdir -p "$CACHE_DIR"
mkfifo "$TMPDIR/live.in"
exec 3<>"$TMPDIR/live.in"

path_is_open() {
  lsof -Fn -p "$LIVE_PID" 2>/dev/null | grep -F "n$DB_PATH" >/dev/null
}

wait_for_line_count() {
  target="$1"
  waited=0
  while [ "$waited" -lt 50 ]; do
    if [ -f "$TMPDIR/live.out" ]; then
      count="$(awk 'END { print NR + 0 }' "$TMPDIR/live.out")"
      if [ "$count" -ge "$target" ]; then
        return 0
      fi
    fi
    sleep 0.1
    waited=$((waited + 1))
  done
  return 1
}

wait_for_open_state() {
  expected="$1"
  waited=0
  while [ "$waited" -lt 50 ]; do
    if path_is_open; then
      current="open"
    else
      current="closed"
    fi
    if [ "$current" = "$expected" ]; then
      return 0
    fi
    sleep 0.1
    waited=$((waited + 1))
  done
  return 1
}

echo "Testing idle runtime-store eviction and reopen..."
CBM_CACHE_DIR="$CACHE_DIR" \
CBM_IDLE_STORE_TIMEOUT_MS=2000 \
"$BINARY" 3<&- < "$TMPDIR/live.in" > "$TMPDIR/live.out" 2> "$TMPDIR/live.err" &
LIVE_PID=$!

if ! wait_for_open_state open; then
  echo "FAIL: runtime db did not open when the server started"
  exit 1
fi

printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' >&3
printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_projects","arguments":{}}}' >&3

if ! wait_for_line_count 2; then
  echo "FAIL: server did not emit initialize + first tool response"
  exit 1
fi

if ! wait_for_open_state closed; then
  echo "FAIL: runtime db did not close after the idle timeout"
  exit 1
fi

printf '%s\n' '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_projects","arguments":{}}}' >&3

if ! wait_for_open_state open; then
  echo "FAIL: runtime db did not reopen on the next tool call"
  exit 1
fi

if ! wait_for_line_count 3; then
  echo "FAIL: server did not emit the second tool response after idling"
  exit 1
fi

exec 3>&-
kill "$LIVE_PID" 2>/dev/null || true
wait "$LIVE_PID" 2>/dev/null || true
LIVE_PID=""

python3 - "$TMPDIR/live.out" <<'PY'
import json
import sys
from pathlib import Path

responses = []
for raw_line in Path(sys.argv[1]).read_text().splitlines():
    raw_line = raw_line.strip()
    if not raw_line:
        continue
    responses.append(json.loads(raw_line))

if len(responses) != 3:
    raise SystemExit(f"expected 3 responses, got {len(responses)}")

init_resp, first_list, second_list = responses

if "protocolVersion" not in init_resp.get("result", {}):
    raise SystemExit("initialize response missing protocolVersion")

for idx, response in enumerate((first_list, second_list), start=1):
    result = response.get("result", {})
    if "projects" not in result:
      raise SystemExit(f"list_projects response {idx} missing projects field")
PY

echo "OK: idle runtime-store eviction and reopen"
