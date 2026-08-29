#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v nix >/dev/null 2>&1; then
	printf 'nix is required to regenerate protocol code.\n' >&2
	exit 1
fi

nix-shell -p protobuf protoc-gen-go protoc-gen-go-grpc

mkdir -p "$repo_dir/Server/protocol" "$repo_dir/Godot/Networking/Generated"

protoc \
	--proto_path="$repo_dir/Protocol" \
	--go_out="$repo_dir/Server/protocol" \
	--go_opt=paths=source_relative \
	"$repo_dir/Protocol/packets.proto"

(
	cd "$repo_dir/Godot"
	godot4 --headless --path . \
		-s addons/godobuf/godobuf_cmdln.gd \
		--input="$repo_dir/Protocol/packets.proto" \
		--output="$repo_dir/Godot/Networking/Generated/Packets.gd"
)
