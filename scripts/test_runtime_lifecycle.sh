#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BINARY="${CODEBASE_MEMORY_ZIG_BIN:-$ROOT_DIR/zig-out/bin/cbm}"

if [ ! -x "$BINARY" ]; then
  zig build >/dev/null
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "Testing clean shutdown on EOF..."
cat > "$TMPDIR/eof.jsonl" <<'JSONL'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
JSONL

"$BINARY" < "$TMPDIR/eof.jsonl" > "$TMPDIR/eof.out" 2> "$TMPDIR/eof.err" &
EOF_PID=$!
EOF_WAITED=0
while kill -0 "$EOF_PID" 2>/dev/null && [ "$EOF_WAITED" -lt 5 ]; do
  sleep 1
  EOF_WAITED=$((EOF_WAITED + 1))
done
if kill -0 "$EOF_PID" 2>/dev/null; then
  kill "$EOF_PID" 2>/dev/null || true
  wait "$EOF_PID" 2>/dev/null || true
  echo "FAIL: clean EOF shutdown exceeded 5 seconds"
  exit 1
fi
wait "$EOF_PID" 2>/dev/null || true
echo "OK: clean EOF shutdown"

echo "Testing graceful shutdown on SIGTERM..."
mkfifo "$TMPDIR/live.in"
"$BINARY" < "$TMPDIR/live.in" > "$TMPDIR/live.out" 2> "$TMPDIR/live.err" &
LIVE_PID=$!
exec 3>"$TMPDIR/live.in"
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' >&3
sleep 1
kill -TERM "$LIVE_PID"
TERM_WAITED=0
while kill -0 "$LIVE_PID" 2>/dev/null && [ "$TERM_WAITED" -lt 5 ]; do
  sleep 1
  TERM_WAITED=$((TERM_WAITED + 1))
done
exec 3>&-
if kill -0 "$LIVE_PID" 2>/dev/null; then
  kill "$LIVE_PID" 2>/dev/null || true
  wait "$LIVE_PID" 2>/dev/null || true
  echo "FAIL: SIGTERM shutdown exceeded 5 seconds"
  exit 1
fi
wait "$LIVE_PID" 2>/dev/null || true
echo "OK: signal-driven shutdown"

echo "Testing startup update notice..."
cat > "$TMPDIR/update.jsonl" <<'JSONL'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
{"jsonrpc":"2.0","id":3,"method":"tools/list","params":{}}
JSONL

CBM_UPDATE_CHECK_CURRENT=0.0.0 \
CBM_UPDATE_CHECK_LATEST=9.9.9 \
"$BINARY" < "$TMPDIR/update.jsonl" > "$TMPDIR/update.out" 2> "$TMPDIR/update.err"

python3 - "$TMPDIR/update.out" <<'PY'
import json
import sys
from pathlib import Path

decoder = json.JSONDecoder()
text = Path(sys.argv[1]).read_text()
responses = []
idx = 0
while idx < len(text):
    while idx < len(text) and text[idx].isspace():
        idx += 1
    if idx >= len(text):
        break
    response, next_idx = decoder.raw_decode(text, idx)
    responses.append(response)
    idx = next_idx

if len(responses) != 3:
    raise SystemExit(f"expected 3 responses, got {len(responses)}")

init_resp, first_tools, second_tools = responses

if "protocolVersion" not in init_resp.get("result", {}):
    raise SystemExit("initialize response missing protocolVersion")

notice = first_tools.get("result", {}).get("update_notice", "")
if "Update available: 0.0.0 -> 9.9.9" not in notice:
    raise SystemExit(f"missing expected update notice: {notice!r}")

if "update_notice" in second_tools.get("result", {}):
    raise SystemExit("update notice should be one-shot and absent on second tools/list response")
PY
echo "OK: startup update notice"

echo "Testing initialized notification stays silent..."
cat > "$TMPDIR/initialized.jsonl" <<'JSONL'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
JSONL

CBM_UPDATE_CHECK_CURRENT=0.0.0 \
CBM_UPDATE_CHECK_LATEST=9.9.9 \
"$BINARY" < "$TMPDIR/initialized.jsonl" > "$TMPDIR/initialized.out" 2> "$TMPDIR/initialized.err"

python3 - "$TMPDIR/initialized.out" <<'PY'
import json
import sys
from pathlib import Path

decoder = json.JSONDecoder()
text = Path(sys.argv[1]).read_text()
responses = []
idx = 0
while idx < len(text):
    while idx < len(text) and text[idx].isspace():
        idx += 1
    if idx >= len(text):
        break
    response, next_idx = decoder.raw_decode(text, idx)
    responses.append(response)
    idx = next_idx

if len(responses) != 2:
    raise SystemExit(f"expected 2 responses, got {len(responses)}")

init_resp, tools_resp = responses

if "protocolVersion" not in init_resp.get("result", {}):
    raise SystemExit("initialize response missing protocolVersion")

notice = tools_resp.get("result", {}).get("update_notice", "")
if "Update available: 0.0.0 -> 9.9.9" not in notice:
    raise SystemExit(f"missing expected update notice after initialized notification: {notice!r}")
PY
echo "OK: initialized notification stays silent"
