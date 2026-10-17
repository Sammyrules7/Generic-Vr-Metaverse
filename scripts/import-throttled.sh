#!/usr/bin/env bash
# Throttled Godot asset import, for machines that have shown instability
# (hard kernel freezes) during the CPU-heavy VRAM recompress phase of
# `godot --editor --import`.
#
# Mitigations applied on top of a plain import run:
#   - runs at lowest scheduling priority (SCHED_IDLE via `nice -n 19`) so the
#     kernel can evict it at the first sign of interactive load,
#   - is capped by a systemd-run CPUQuota (default 6x100%) so it cannot fan
#     out to every physical core and max out the thermal-power envelope,
#   - stays headless with the dummy renderer: no GPU work at all — the game
#     assets' heavy CPU compression (BPTC on large lightmap .exr atlases) is
#     what we are throttling.
#
# Usage: scripts/import-throttled.sh [CPU_CORES]
#   CPU_CORES is the reactor CPUQuota expressed in whole cores (default 6).
#
# Prefer letting CI import (`.forgejo/workflows/Delivery-checks.yaml`) when
# possible; only run this locally after agreeing on the risk, and interrupt
# (Ctrl-C / `pkill -f 'editor --import'`) at any time — imports are restartable
# and resume from their per-file cache.
set -euo pipefail

CORES="${1:-6}"
QUOTA="${CORES}00%"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run() {
    if command -v systemd-run >/dev/null 2>&1 && systemd-run --user --scope true 2>/dev/null; then
        systemd-run --user --scope \
            -p CPUQuota="$QUOTA" \
            -p MemoryMax=6G \
            nice -n 19 godot --headless --xr-mode off --editor --import --path "$REPO_ROOT/Godot"
    else
        # No usable per-user systemd: fall back to nice alone.
        nice -n 19 godot --headless --xr-mode off --editor --import --path "$REPO_ROOT/Godot"
    fi
}

echo "Throttled Godot import: controller CPUQuota=$QUOTA, nice 19, headless/dummy renderer."
echo "First-time imports can take a while (the observatory lightmap atlas is the slowest)."
run
