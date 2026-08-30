#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mkdir -p "$repo_dir/Server/protocol" "$repo_dir/Godot/Networking/Generated"

run_protoc() {
	protoc "$@"
}
if ! command -v protoc >/dev/null 2>&1; then
	if ! command -v nix-shell >/dev/null 2>&1; then
		printf 'protoc (or nix-shell) is required to regenerate protocol code.\n' >&2
		exit 1
	fi
	run_protoc() {
		local command
		printf -v command '%q ' protoc "$@"
		nix-shell -p protobuf protoc-gen-go --run "$command"
	}
fi

run_protoc \
	--proto_path="$repo_dir/Protocol" \
	--go_out="$repo_dir/Server/protocol" \
	--go_opt=paths=source_relative \
	"$repo_dir/Protocol/packets.proto"

(
	cd "$repo_dir/Godot"
	"$(command -v godot4 || command -v godot)" --headless --path . \
		-s addons/godobuf/godobuf_cmdln.gd \
		--input="$repo_dir/Protocol/packets.proto" \
		--output="$repo_dir/Godot/Networking/Generated/Packets.gd"
)
