#!/usr/bin/env bash
# Source from CI scripts; preserve the command's exit status without logging args.
ci_timed() {
  local label="$1" started=$SECONDS status
  shift
  if "$@"; then status=0; else status=$?; fi
  printf 'CI timing: %s: %ss (exit %s)\n' "$label" "$((SECONDS - started))" "$status"
  return "$status"
}
