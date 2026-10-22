#!/usr/bin/env bash
# Run after Godot's editor import, inside the development shell.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
test_dir="$(mktemp -d)"
server_pid=""
cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf -- "$test_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Isolate preferences and force every autoload away from the production server.
export XDG_DATA_HOME="$test_dir/data" XDG_CONFIG_HOME="$test_dir/config"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME"
export VR_PLATFORM_SERVER_URL=ws://127.0.0.1:1/ws

run_godot() {
  local log="$test_dir/godot.log"
  if ! timeout --kill-after=10s 120s godot --headless --xr-mode off --path Godot "$@" >"$log" 2>&1; then
    cat "$log"
    return 1
  fi
  cat "$log"
  if grep -q 'SCRIPT ERROR:' "$log"; then
    return 1
  fi
}

for suite in movement tracked_hand hand_menu avatar_loading avatar_container avatar_rig avatar_springs voice_codec voice_audience murder_rules murder_presentation murder_session prairie_weather; do
  run_godot --script "res://tests/${suite}_test.gd"
done

run_godot res://UI/tests/avatar_picker_test.tscn

# Bind port zero and discover the selected port from the server's startup log.
# Building first gives cleanup a single owned process rather than go-run children.
(cd Server && CGO_ENABLED=0 go build -o "$test_dir/server" .)
VR_PLATFORM_LISTEN_ADDR=127.0.0.1:0 "$test_dir/server" >"$test_dir/server.log" 2>&1 &
server_pid=$!
if ! endpoint="$(python3 - "$test_dir/server.log" <<'PY'
from pathlib import Path
import re
import sys
import time

log = Path(sys.argv[1])
deadline = time.monotonic() + 10
while time.monotonic() < deadline:
    match = re.search(r'Starting server on (127\.0\.0\.1:[1-9][0-9]*)', log.read_text())
    if match:
        print('ws://' + match[1] + '/ws')
        break
    time.sleep(0.05)
else:
    sys.exit('Local test server did not become ready')
PY
)"; then
  cat "$test_dir/server.log"
  exit 1
fi
export VR_PLATFORM_SERVER_URL="$endpoint"
run_godot res://Networking/tests/network_test.tscn
