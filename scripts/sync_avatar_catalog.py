#!/usr/bin/env python3
"""Snapshot every public VRM in Open Source Avatars; never download models.
Usage: python3 scripts/sync_avatar_catalog.py [upstream commit/ref]
The snapshot keeps multiplayer IDs/URLs identical across clients of this build.
"""
import hashlib
import json
from pathlib import Path
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_REVISION = '0f9a1b2fd99894736563d55b2c9dc9125700d081'


def fetch_json(base, path):
    with urllib.request.urlopen(base + path, timeout=60) as response:
        return json.load(response)


def main():
    revision = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_REVISION
    base = f'https://raw.githubusercontent.com/ToxSam/open-source-avatars/{revision}/data/'
    projects = fetch_json(base, 'projects.json')
    projects = [p for p in projects if p.get('is_public', True)]
    existing = json.loads((ROOT / 'Godot/avatar/catalog.json').read_text())
    pinned = {e['id']: e for e in existing if e.get('sha256')}
    bundled = [e for e in existing if e.get('bundled_path')]
    result = list(bundled)
    seen = {e['id'] for e in result}
    with ThreadPoolExecutor(max_workers=6) as pool:
        data = list(pool.map(lambda p: fetch_json(base, p['avatar_data_file']), projects))
    for project, avatars in zip(projects, data):
        for avatar in avatars:
            url = avatar.get('model_file_url', '')
            if (not avatar.get('is_public', True) or avatar.get('is_draft', False)
                    or str(avatar.get('format', 'VRM')).upper() != 'VRM'
                    or not url.startswith('https://')):
                continue
            original_id = str(avatar['id'])
            previous = pinned.get(original_id, {})
            avatar_id = original_id if previous else 'osa-' + hashlib.sha256((project['id'] + ':' + original_id).encode()).hexdigest()[:40]
            if avatar_id in seen:
                continue
            seen.add(avatar_id)
            entry = {
                'id': avatar_id, 'title': avatar.get('name', original_id),
                'url': url, 'collection': project['name'], 'collection_id': project['id'],
                'creator': project.get('creator_id', ''), 'license': project.get('license', ''),
                'attribution': f"{project.get('creator_id', '')} · {project['name']} · {project.get('license', '')}",
                'source': 'https://opensourceavatars.com',
                'thumbnail_url': avatar.get('thumbnail_url', ''),
                'upstream_id': original_id,
            }
            if previous.get('url') == url:
                entry.update({k: previous[k] for k in ('sha256', 'size_bytes')})
            result.append(entry)
    output = ROOT / 'Godot/avatar/catalog.json'
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    (ROOT / 'Godot/avatar/catalog_source.json').write_text(json.dumps({
        'repository': 'https://github.com/ToxSam/open-source-avatars',
        'revision': revision, 'license': 'CC0-1.0 (registry metadata; models retain collection licenses)',
        'collections': len(projects), 'avatars': len(result) - len(bundled),
    }, indent=2) + '\n')
    print(f'{len(result)} avatars including bundled models, {len(projects)} collections')


if __name__ == '__main__':
    main()
