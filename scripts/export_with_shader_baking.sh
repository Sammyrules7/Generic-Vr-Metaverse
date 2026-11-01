#!/usr/bin/env bash
# A headless Godot export silently skips shader baking. Supply an X11 display
# and a Vulkan rendering device instead; the CI image uses Mesa lavapipe.
set -euo pipefail

if (( $# == 0 )); then
  echo "Usage: $0 <Godot export arguments>" >&2
  exit 2
fi
for argument in "$@"; do
  if [[ "$argument" == --headless ]]; then
    echo "Shader baking requires a rendering device; --headless is not supported." >&2
    exit 2
  fi
done
if ! command -v xvfb-run >/dev/null; then
  echo "Shader baking requires xvfb-run. Refresh the native CI image first." >&2
  exit 1
fi
export_log="$(mktemp)"
trap 'rm -f "$export_log"' EXIT
xvfb-run -a -s "-screen 0 1280x720x24" godot \
  --display-driver x11 --rendering-driver vulkan --audio-driver Dummy --xr-mode off --verbose "$@" 2>&1 | tee "$export_log"
# Do not publish a successful-looking export that silently skipped baking.
if ! grep -Eq 'Storing File: res://\.godot/shader_cache/.*\.vulkan\.cache' "$export_log"; then
  echo "Export did not include baked Vulkan shaders. Check the renderer and shader_baker/enabled preset option." >&2
  exit 1
fi
