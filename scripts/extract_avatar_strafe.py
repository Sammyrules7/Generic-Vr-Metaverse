#!/usr/bin/env python3
"""100STYLE neutral sidestep extraction. Source credit: Ian Mason, CC BY 4.0.
Root translation is measured for stride length but never stored as animation.
"""
import re, math, json, hashlib
from pathlib import Path
import argparse
parser = argparse.ArgumentParser(description='Extract two looped neutral sidesteps from the CC-BY-4.0 100STYLE capture')
parser.add_argument('source', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
raw = args.source.read_bytes()
if hashlib.sha256(raw).hexdigest() != '07225ded6df11c4eb97a7b42e6121a9e985ae7e8d0f56f9ca971429f9c507ad9':
    parser.error('Source does not match the pinned Neutral_SW.bvh')
text = raw.decode()
tokens = iter(re.findall('[^\\s{}]+|[{}]', text.split('MOTION')[0]))
nodes = []
channel = 0
assert next(tokens) == 'HIERARCHY'

def parse(parent):
    global channel
    name = next(tokens)
    assert next(tokens) == '{'
    i = len(nodes)
    n = {'name': name, 'parent': parent, 'channels': []}
    nodes.append(n)
    while True:
        tok = next(tokens)
        if tok == '}':
            break
        if tok == 'OFFSET':
            n['offset'] = [float(next(tokens)) for _ in range(3)]
        elif tok == 'CHANNELS':
            count = int(next(tokens))
            n['channels'] = [(next(tokens), channel + k) for k in range(count)]
            channel += count
        elif tok == 'JOINT':
            parse(i)
        elif tok == 'End':
            assert next(tokens) == 'Site'
            assert next(tokens) == '{'
            assert next(tokens) == 'OFFSET'
            end = [float(next(tokens)) for _ in range(3)]
            assert next(tokens) == '}'
            n['end'] = end
        else:
            raise ValueError(tok)
assert next(tokens) == 'ROOT'
parse(-1)
lines = text.split('MOTION')[1].strip().splitlines()
dt = float(lines[1].split(':')[1])
rows = [[float(v) for v in r.split()] for r in lines[2:]]
by = {n['name']: i for i, n in enumerate(nodes)}

def add(a, b):
    return tuple((a[k] + b[k] for k in range(3)))

def sub(a, b):
    return tuple((a[k] - b[k] for k in range(3)))

def mul(a, s):
    return tuple((v * s for v in a))

def dot(a, b):
    return sum((x * y for x, y in zip(a, b)))

def norm(a):
    return mul(a, 1 / max(1e-10, math.sqrt(dot(a, a))))

def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])

def qm(a, b):
    x, y, z, w = a
    u, v, t, s = b
    return (w * u + x * s + y * t - z * v, w * v - x * t + y * s + z * u, w * t + x * v - y * u + z * s, w * s - x * u - y * v - z * t)

def qr(q, v):
    x, y, z, w = q
    t = mul(cross((x, y, z), v), 2)
    return add(v, add(mul(t, w), cross((x, y, z), t)))

def world(row):
    ps = []
    qs = []
    for n in nodes:
        q = (0, 0, 0, 1)
        p = n['offset'][:]
        for name, c in n['channels']:
            if name.endswith('position'):
                p['XYZ'.index(name[0])] += row[c]
            else:
                a = math.radians(row[c]) / 2
                axis = [0, 0, 0]
                axis['XYZ'.index(name[0])] = math.sin(a)
                q = qm(q, (*axis, math.cos(a)))
        par = n['parent']
        if par >= 0:
            p = add(ps[par], qr(qs[par], p))
            q = qm(qs[par], q)
        ps.append(p)
        qs.append(q)
    return ps
poses = [world(row) for row in rows]

def axes(ps):
    lateral = sub(ps[by['LeftHip']], ps[by['RightHip']])
    lateral = norm((lateral[0], 0, lateral[2]))
    return (lateral, (0, 1, 0), cross(lateral, (0, 1, 0)))

def canonical(v, ax):
    return tuple((dot(v, a) for a in ax))
TRACKS = [('Hips', 'Hips', 'Chest'), ('Spine', 'Chest', 'Chest2'), ('Chest', 'Chest2', 'Chest3'), ('UpperChest', 'Chest3', 'Chest4'), ('LeftShoulder', 'LeftCollar', 'LeftShoulder'), ('RightShoulder', 'RightCollar', 'RightShoulder'), ('LeftUpperLeg', 'LeftHip', 'LeftKnee'), ('LeftLowerLeg', 'LeftKnee', 'LeftAnkle'), ('LeftFoot', 'LeftAnkle', 'LeftToe'), ('RightUpperLeg', 'RightHip', 'RightKnee'), ('RightLowerLeg', 'RightKnee', 'RightAnkle'), ('RightFoot', 'RightAnkle', 'RightToe')]
rest = world([0.0] * channel)
rest_axes = axes(rest)
leg_length = sum((math.dist(rest[by[a]], rest[by[b]]) for a, b in [('LeftHip', 'LeftKnee'), ('LeftKnee', 'LeftAnkle')]))
args.output.mkdir(parents=True, exist_ok=True)
for side, start, end in [('left', 816, 894), ('right', 1949, 2022)]:
    duration = (end - start) * dt
    track_rows = {name: [] for name, _, _ in TRACKS}
    wrists = {side: [] for side in ['left', 'right']}
    for frame in range(start, end + 1):
        ps = poses[frame]
        ax = axes(ps)
        for name, bone, child in TRACKS:
            track_rows[name].append(norm(canonical(sub(ps[by[child]], ps[by[bone]]), ax)))
        for hand, label in [('Left', 'left'), ('Right', 'right')]:
            upper, elbow, wrist = [by[hand + n] for n in ['Shoulder', 'Elbow', 'Wrist']]
            arm = math.dist(rest[upper], rest[elbow]) + math.dist(rest[elbow], rest[wrist])
            wrists[label].append(mul(canonical(sub(ps[wrist], ps[upper]), ax), 1 / arm))

    # Align all directions to a left-foot contact before diagonal blending.
    # Choose the most extended left ankle among its low/contact samples.
    ankle_samples = []
    for frame in range(start, end):
        ps = poses[frame]
        ankle_samples.append(canonical(sub(ps[by['LeftAnkle']], ps[0]), axes(ps)))
    low = min(v[1] for v in ankle_samples)
    high = max(v[1] for v in ankle_samples)
    candidates = [i for i, v in enumerate(ankle_samples) if v[1] <= low + (high - low) * 0.3]
    contact_phase = max(candidates, key=lambda i: ankle_samples[i][0])
    def close_loop(values, unit):
        correction = sub(values[0], values[-1])
        result = []
        for i, value in enumerate(values):
            t = i / (len(values) - 1)
            t = t * t * (3 - 2 * t)
            row = add(value, mul(correction, t))
            result.append([round(v, 5) for v in (norm(row) if unit else row)])
        periodic = result[:-1]
        periodic = periodic[contact_phase:] + periodic[:contact_phase]
        return periodic + [periodic[0]]
    tracks = {}
    for name, bone, child in TRACKS:
        frames = close_loop(track_rows[name], True)
        reference = norm(canonical(sub(rest[by[child]], rest[by[bone]]), rest_axes))
        tracks[name] = {'mean': reference, 'reference': reference, 'frames': frames}
    displacement = sub(poses[end][0], poses[start][0])
    stride = abs(dot(displacement, axes(poses[start])[0])) / leg_length
    out = {'format': 1, 'id': '100style_neutral_strafe_' + side, 'duration': duration, 'sample_count': end - start + 1, 'sample_hz': 1 / dt, 'stride_per_leg_length': stride, 'source': {'author': 'Ian Mason', 'pack': '100STYLE', 'page': 'https://www.ianxmason.com/100style/', 'license': 'CC-BY-4.0', 'source_file': 'Neutral_SW.bvh', 'source_url': 'https://drive.google.com/uc?export=download&id=1HzUccloKCjQgpObQ0ZXTEDW7-RllNwHX', 'source_sha256': hashlib.sha256(raw).hexdigest(), 'frame_start': start, 'frame_end': end, 'contact_phase_frame': contact_phase, 'animation': 'Neutral_SW_' + side, 'changes': 'Trimmed one cycle; removed root translation and heading; retargetable direction/wrist tracks; smooth endpoint correction'}, 'tracks': tracks, 'wrists': {k: close_loop(v, False) for k, v in wrists.items()}}
    path = args.output / (out['id'] + '.json')
    path.write_text(json.dumps(out, separators=(',', ':')))
    print(path, 'duration', duration, 'stride/leg', stride)
