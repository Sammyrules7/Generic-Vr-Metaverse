#!/usr/bin/env bash
set -euo pipefail

# Publish all objects before moving the small directory pointer. Existing builds
# are retained so a pinned browser can finish fetching its original JS/WASM/PCK.
: "${GARAGE_BUCKET:?}" "${GARAGE_ENDPOINT:?}" "${BUILD_COMMIT:?}" "${EXPORT_DIR:?}"
[[ "$BUILD_COMMIT" =~ ^[0-9a-f]{40}$ ]]
[[ "${1:-}" == channels/main || "${1:-}" =~ ^branches/[a-z0-9][a-z0-9-]*$ ]]
prefix="s3://$GARAGE_BUCKET/$1"
build_prefix="$prefix/builds/$BUILD_COMMIT"
pointer_file="$(mktemp)"
trap 'rm -f "$pointer_file"' EXIT
printf '%s\n' "$BUILD_COMMIT" > "$pointer_file"
s3() { s5cmd --endpoint-url "$GARAGE_ENDPOINT" "$@"; }

# A completed commit is immutable even when its workflow is rerun.
if ! s3 ls "$build_prefix/complete.txt" >/dev/null; then
  s3 sync "$EXPORT_DIR/" "$build_prefix/assets/"
  s3 cp --include "*.wasm" --content-type application/wasm "$EXPORT_DIR/" "$build_prefix/assets/"
  s3 cp --include "*.pck" --content-type application/octet-stream "$EXPORT_DIR/" "$build_prefix/assets/"
  s3 cp --content-type text/plain "$pointer_file" "$build_prefix/complete.txt"
fi
s3 cp --content-type text/plain --cache-control no-cache "$pointer_file" "$prefix/commit.txt"
