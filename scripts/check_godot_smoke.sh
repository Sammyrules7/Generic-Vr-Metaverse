#!/usr/bin/env bash
# Focused export-job checks; check_runtime.sh remains the full runtime gate.
# The XR/avatar suites shared by native and web run first. Native also runs the
# loading/container/rig/springs suites and the avatar picker scene.
set -euo pipefail

profile="${1:-}"
case "$profile" in
  native|web) ;;
  *) echo "Usage: $0 native|web" >&2; exit 2 ;;
esac

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_path="${PROJECT_PATH:-$repo_dir/Godot}"

run_godot() {
  godot --headless --xr-mode off --path "$project_path" "$@"
}

for suite in tracked_hand hand_menu touch_approach avatar_custom avatar_transfer avatar_render_profiler avatar_ground_feet; do
  run_godot --script "res://tests/${suite}_test.gd"
done

# Preserve the broader native-export checks without expanding web-preview cost.
if [[ "$profile" == native ]]; then
  for suite in avatar_loading avatar_container avatar_rig avatar_springs; do
    run_godot --script "res://tests/${suite}_test.gd"
  done
fi

run_godot res://UI/tests/lobby_test.tscn
if [[ "$profile" == native ]]; then
  run_godot res://UI/tests/avatar_picker_test.tscn
fi
