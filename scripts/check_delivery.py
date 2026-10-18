#!/usr/bin/env python3
"""Check delivery inputs without requiring a Godot runtime.

The full-editor import in Delivery-checks reimports rebaked lightmap atlases
(BPTC compression) and transiently peaks around 6 GiB, so job pods ask for
7 GiB of memory (runner podspec) and stay off the 8 GiB node; otherwise the
k3s apiserver can die under node memory pressure and every job's exec
websocket drops at once ("websocket: close 1006" mid-reimport).
"""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def check():
    registry = (ROOT / 'Godot/worlds/world_registry.tres').read_text()
    ids = re.findall(r'^id = "([^"]+)"$', registry, re.M)
    # Match the complete map, including the empty struct literals.
    server = (ROOT / 'Server/room.go').read_text().split('var supportedWorlds = map[string]struct{}{', 1)[1].split('\n}', 1)[0]
    assert len(ids) == len(set(ids)), 'Duplicate registry IDs'
    assert set(ids) == set(re.findall(r'"([^"]+)":', server)), 'World allowlist/registry drift'
    for scene in re.findall(r'^scene_path = "res://([^"]+)"$', registry, re.M):
        assert (ROOT / 'Godot' / scene).is_file(), f'Missing registered scene: {scene}'
    manifest = json.loads((ROOT / 'native-libraries.json').read_text())
    for addon in manifest.values():
        actual = {str(p.relative_to(ROOT)) for p in (ROOT / addon['directory']).rglob('*') if p.is_file() and (p.suffix in {'.so', '.dll', '.dylib', '.wasm', '.a'} or '.framework/' in str(p))}
        assert actual == set(addon['sha256']), 'Native library inventory drift'
        for name, digest in addon['sha256'].items():
            assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest, f'Native checksum drift: {name}'
    # Every tracked LFS pointer must be materialized with exactly its recorded bytes.
    names = subprocess.check_output(['git', 'lfs', 'ls-files', '-n'], cwd=ROOT).splitlines()
    for name in filter(None, names):
        path = name.decode()
        pointer = subprocess.check_output(['git', 'show', f'HEAD:{path}'], cwd=ROOT)
        oid = re.search(rb'^oid sha256:([0-9a-f]{64})$', pointer, re.M)
        if oid:
            data = (ROOT / path).read_bytes()
            assert hashlib.sha256(data).hexdigest() == oid[1].decode(), f'LFS checkout missing/corrupt: {path}'
    print('Delivery checks passed: registry, native inventory/checksums, materialized LFS')


if __name__ == '__main__':
    check()
