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
compressed_file=""
trap 'rm -f -- "$pointer_file" "$compressed_file"' EXIT
printf '%s\n' "$BUILD_COMMIT" > "$pointer_file"
s3() { s5cmd --endpoint-url "$GARAGE_ENDPOINT" "$@"; }

test -s "$EXPORT_DIR/delivery-identity.txt"

# Retention: per-commit builds are immutable snapshots, which previously
# filled the Garage bucket to its size quota. Keep only the branch pointer
# target, the incoming build, and the few newest completed builds; prune the
# rest ahead of the upload so this build always has available space. Partial
# snapshots from failed runs carry no complete.txt and are pruned with them.
keep_newest=3
pointer_commit=""
if s3 ls "$prefix/commit.txt" >/dev/null 2>&1; then
  pointer_commit="$(s3 cat "$prefix/commit.txt" | tr -d '[:space:]' || true)"
fi
[[ "$pointer_commit" =~ ^[0-9a-f]{40}$ ]] || pointer_commit=""
recent="$(s3 ls "$prefix/builds/*/complete.txt" 2>/dev/null | awk '$NF ~ /\/complete\.txt$/')"
if [[ -z "$(printf '%s' "$recent" | tr -d '[:space:]')" ]]; then
  echo "Could not list completed builds; keeping every snapshot" >&2
else
  keep=" $BUILD_COMMIT $pointer_commit"
  while read -r sha; do
    keep="$keep $sha"
  done < <(printf '%s\n' "$recent" | sort -r | sed -E 's|.*/builds/([0-9a-f]{40})/complete\.txt.*|\1|' | head -n "$keep_newest" | sort -u)
  # s5cmd lists pseudo-directories as regular rows whose URL ends in "/"; the
  # keep-set exception keeps any build that is neither recent nor referenced.
  s3 ls "$prefix/builds/" 2>/dev/null | awk '{print $NF}' | \
    sed -nE 's|.*builds/([0-9a-f]{40})/?$|\1|p' | while read -r sha; do
    [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || continue
    case "$keep" in *" $sha "*) continue ;; esac
    echo "Pruning old web preview build $sha"
    s3 rm "$prefix/builds/$sha/*" || true
  done || true
fi

# A completed commit is immutable even when its workflow is rerun.
if s3 ls "$build_prefix/complete.txt" >/dev/null; then
  remote_identity="$(s3 cat "$build_prefix/assets/delivery-identity.txt")"
  if [[ "$remote_identity" != "$(cat "$EXPORT_DIR/delivery-identity.txt")" ]]; then
    echo "Refusing to reuse commit with a different endpoint/toolchain identity" >&2
    exit 1
  fi
else
  # Keep originals for byte-range requests; full downloads use precompressed
  # siblings. Compress at publication time rather than spending Worker CPU.
  while IFS= read -r -d '' asset; do
    if [[ ! -f "$asset.gz" || "$asset" -nt "$asset.gz" ]]; then
      compressed_file="$(mktemp "$asset.gz.XXXXXX")"
      gzip -n -6 -c "$asset" > "$compressed_file"
      mv "$compressed_file" "$asset.gz"
      compressed_file=""
    fi
  done < <(find "$EXPORT_DIR" -type f \( -name '*.pck' -o -name '*.wasm' -o -name '*.js' \) -print0)
  s3 sync "$EXPORT_DIR/" "$build_prefix/assets/"
  s3 cp --include "*.wasm" --content-type application/wasm "$EXPORT_DIR/" "$build_prefix/assets/"
  s3 cp --include "*.pck" --content-type application/octet-stream "$EXPORT_DIR/" "$build_prefix/assets/"
  s3 cp --content-type text/plain "$pointer_file" "$build_prefix/complete.txt"
fi
s3 cp --content-type text/plain --cache-control no-cache "$pointer_file" "$prefix/commit.txt"
