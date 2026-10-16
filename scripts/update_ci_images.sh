#!/usr/bin/env bash
set -euo pipefail

# Server changes need only the server closure. Toolchain/image changes rebuild
# all images together so Nix evaluates the flake once and schedules shared work.
scope="${1:-all}"
case "$scope" in server|all) ;; *) echo 'Expected server or all' >&2; exit 1 ;; esac
: "${ATTIC_CACHE:?}"
definitions=(
  'server-image|vr-platform-server|cluster/server/deployment.yaml'
)
if [[ "$scope" == all ]]; then
  definitions+=(
    'godot-ci-image|vr-platform-godot-ci|.forgejo/workflows/Build-and-release.yaml'
    'godot-web-ci-image|vr-platform-godot-web-ci|.forgejo/workflows/Web-preview.yaml'
    'web-publish-ci-image|vr-platform-web-publish-ci|.forgejo/workflows/Worker-deploy.yaml'
    'cleanup-ci-image|vr-platform-cleanup-ci|.forgejo/workflows/Web-preview-cleanup.yaml'
    'builder-ci-image|vr-platform-builder-ci|.forgejo/workflows/Server-container.yaml'
  )
fi

packages=()
for definition in "${definitions[@]}"; do
  IFS='|' read -r package _ _ <<< "$definition"
  packages+=(".#$package")
done
output="$(nix build --no-link --print-out-paths "${packages[@]}")"
mapfile -t paths <<< "$output"
nix run .#attic-client -- push "$ATTIC_CACHE" "${paths[@]}"

for definition in "${definitions[@]}"; do
  IFS='|' read -r package image files <<< "$definition"
  image_path=''
  for path in "${paths[@]}"; do
    if [[ "$path" == /nix/store/*-nix-image-"$image".tar ]]; then
      image_path="$path"
      break
    fi
  done
  if [[ -z "$image_path" ]]; then
    echo "No image output found for $package" >&2
    exit 1
  fi
  read -r -a destinations <<< "$files"
  for file in "${destinations[@]}"; do
    pattern="image: nix:0/nix/store/[^ ]+-nix-image-$image.tar"
    # Fail if a workflow rename or changed format would silently miss a pin.
    grep -Eq "$pattern" "$file"
    sed -i -E "s|$pattern|image: nix:0$image_path|" "$file"
  done
done
