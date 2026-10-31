#!/usr/bin/env python3
"""Extract a CC0 humanoid clip into humanoid direction tracks for the avatar rig.

Source: Quaternius Universal Animation Library (CC0 1.0), standard/free version,
as redistributed in J-Ponzo/gltf-universal-animation-library commit e24c23c.
Select a named clip from the pinned source; the original file is not shipped.
"""
import argparse
import statistics
import json, struct, math, hashlib

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source_gltf", help="Pinned Quaternius AnimationLibrary_Godot_Standard.gltf")
parser.add_argument("source_bin", help="Its matching glTF buffer")
parser.add_argument("output", help="Destination JSON direction tracks")
parser.add_argument("--animation", default="Idle_Loop", choices=["Idle_Loop", "Walk_Loop", "Jog_Fwd_Loop"], help="Animation to extract (default: Idle_Loop)")
args = parser.parse_args()
SRC, BIN, OUT = args.source_gltf, args.source_bin, args.output
expected = {SRC: "0ff075c7ad6855c5c2c37a171592ee8f0d6ab2f58259e2be77a9b63dd8027765",
            BIN: "6e65377d81558333c4093dbb144a48fd19019343d82b1a3a7992a98ec0e0543c"}
for path, digest in expected.items():
    with open(path, "rb") as source:
        if hashlib.sha256(source.read()).hexdigest() != digest:
            parser.error("Source hash does not match the pinned CC0 pack: " + path)
HZ = 30.0

j = json.load(open(SRC))
b = open(BIN, "rb").read()


def read_acc(i):
    acc = j["accessors"][i]
    bv = j["bufferViews"][acc["bufferView"]]
    off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    n = acc["count"]
    comps = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[acc["type"]]
    fmt = {5126: "f", 5123: "H", 5125: "I"}[acc["componentType"]]
    vals = struct.unpack_from("<" + fmt * (n * comps), b, off)
    return [vals[k * comps:(k + 1) * comps] for k in range(n)]


def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz)


def qrot(q, v):
    x, y, z, w = q
    vx, vy, vz = v
    tx = 2 * (y * vz - z * vy)
    ty = 2 * (z * vx - x * vz)
    tz = 2 * (x * vy - y * vx)
    return (vx + w * tx + (y * tz - z * ty),
            vy + w * ty + (z * tx - x * tz),
            vz + w * tz + (x * ty - y * tx))


def qnorm(q):
    l = math.sqrt(sum(c * c for c in q))
    return tuple(c / l for c in q)


def qslerp(a, bt, t):
    d = sum(x * y for x, y in zip(a, bt))
    if d < 0:
        bt = tuple(-x for x in bt)
        d = -d
    if d > 0.9995:
        return qnorm(tuple(a[i] + t * (bt[i] - a[i]) for i in range(4)))
    th = math.acos(max(-1.0, min(1.0, d)))
    s = math.sin(th)
    return qnorm(tuple((math.sin((1 - t) * th) * a[i] + math.sin(t * th) * bt[i]) / s for i in range(4)))


nodes = j["nodes"]
parent = {}
for i, n in enumerate(nodes):
    for c in n.get("children", []):
        parent[c] = i

anim = next(a for a in j["animations"] if a["name"] == args.animation)
chans = {}
for ch in anim["channels"]:
    ti = ch["target"]["node"]
    path = ch["target"]["path"]
    sm = anim["samplers"][ch["sampler"]]
    times = [v[0] for v in read_acc(sm["input"])]
    vals = read_acc(sm["output"])
    chans[(ti, path)] = (times, vals)

DURATION = max(times[-1] for times, _ in chans.values())
print("duration", DURATION)


def sample(i, path, t, default):
    key = (i, path)
    if key not in chans:
        return default
    times, vals = chans[key]
    if t <= times[0]:
        return vals[0]
    if t >= times[-1]:
        return vals[-1]
    for k in range(1, len(times)):
        if t <= times[k]:
            u = (t - times[k - 1]) / (times[k] - times[k - 1])
            if path == "rotation":
                return qslerp(vals[k - 1], vals[k], u)
            return tuple(vals[k - 1][c] + (vals[k][c] - vals[k - 1][c]) * u for c in range(len(vals[k])))
    return vals[-1]


def world(i, t, animated=True):
    chain = []
    while i is not None:
        chain.append(i)
        i = parent.get(i)
    chain.reverse()
    pos = (0.0, 0.0, 0.0)
    rot = (0.0, 0.0, 0.0, 1.0)
    for idx in chain:
        n = nodes[idx]
        tr = sample(idx, "translation", t, tuple(n.get("translation", [0, 0, 0]))) if animated else tuple(n.get("translation", [0, 0, 0]))
        rr = sample(idx, "rotation", t, tuple(n.get("rotation", [0, 0, 0, 1]))) if animated else tuple(n.get("rotation", [0, 0, 0, 1]))
        rp = qrot(rot, tr)
        pos = tuple(pos[k] + rp[k] for k in range(3))
        rot = qnorm(qmul(rot, rr))
    return pos, rot


def idx(name):
    for k, n in enumerate(nodes):
        if n["name"] == name:
            return k
    raise KeyError(name)


TRACKS = [
    ("Hips", "DEF-hips", "DEF-spine.001"),
    ("Spine", "DEF-spine.001", "DEF-spine.002"),
    ("Chest", "DEF-spine.002", "DEF-spine.003"),
    ("UpperChest", "DEF-spine.003", "DEF-neck"),
    ("LeftShoulder", "DEF-shoulder.L", "DEF-upper_arm.L"),
    ("RightShoulder", "DEF-shoulder.R", "DEF-upper_arm.R"),
    ("LeftUpperLeg", "DEF-thigh.L", "DEF-shin.L"),
    ("LeftLowerLeg", "DEF-shin.L", "DEF-foot.L"),
    ("LeftFoot", "DEF-foot.L", "DEF-toe.L"),
    ("RightUpperLeg", "DEF-thigh.R", "DEF-shin.R"),
    ("RightLowerLeg", "DEF-shin.R", "DEF-foot.R"),
    ("RightFoot", "DEF-foot.R", "DEF-toe.R"),
]
WRISTS = [("left", "DEF-upper_arm.L", "DEF-hand.L"), ("right", "DEF-upper_arm.R", "DEF-hand.R")]

rest_world = {}
for _, bone, child in TRACKS:
    rest_world[bone] = world(idx(bone), 0.0)[0]
    rest_world[child] = world(idx(child), 0.0)[0]
arm_len = {}
for side, upper, hand in WRISTS:
    p0 = world(idx(upper), 0.0)[0]
    p1 = world(idx(hand), 0.0)[0]
    arm_len[side] = math.sqrt(sum((p1[k] - p0[k]) ** 2 for k in range(3)))
    if args.animation != "Idle_Loop":
        # Jogging elbows are bent: shoulder-to-wrist distance would exaggerate
        # the normalized hand reach. Use the two physical segment lengths.
        elbow = world(idx("DEF-forearm.L" if side == "left" else "DEF-forearm.R"), 0.0)[0]
        arm_len[side] = sum(math.dist(a, c) for a, c in [(p0, elbow), (elbow, p1)])

steps = int(round(DURATION * HZ))
count = steps + 1
tracks = {}
wrists = {side: [] for side, _, _ in WRISTS}


def unit(v):
    l = math.sqrt(sum(c * c for c in v))
    return [v[k] / l for k in range(3)] if l > 1e-8 else [0.0, 1.0, 0.0]


# Align locomotion loops at left-foot forward contact before blending walk/jog.
phase_offset = 0.0
if args.animation != "Idle_Loop":
    phase_offset = max((DURATION * i / 240 for i in range(240)),
                       key=lambda t: world(idx("DEF-foot.L"), t)[0][2])
for step in range(count):
    t = min(DURATION, step / HZ) if args.animation == "Idle_Loop" else (phase_offset + DURATION * step / steps) % DURATION
    for name, bone, child in TRACKS:
        p = world(idx(bone), t)[0]
        c = world(idx(child), t)[0]
        tracks.setdefault(name, []).append(unit(tuple(c[k] - p[k] for k in range(3))))
    for side, upper, hand in WRISTS:
        p = world(idx(upper), t)[0]
        h = world(idx(hand), t)[0]
        wrists[side].append([round((h[k] - p[k]) / arm_len[side], 4) for k in range(3)])

# Keep the JSON compact.
for name in tracks:
    tracks[name] = [[round(v, 4) for v in row] for row in tracks[name]]

out = {
    "format": 1,
    "id": "quaternius_universal_" + args.animation.lower(),
    "duration": DURATION,
    "sample_count": count,
    "sample_hz": HZ,
    "source": {
        "author": "Quaternius",
        "pack": "Universal Animation Library (standard/free edition)",
        "page": "https://quaternius.com/packs/universalanimationlibrary.html",
        "license": "CC0-1.0",
        "redistribution": "https://github.com/J-Ponzo/gltf-universal-animation-library",
        "redistribution_commit": "e24c23cf2a1323488a3faa226ea7ea21f644b73e",
        "source_file": "glTF/AnimationLibrary_Godot_Standard.gltf",
        "source_sha256": hashlib.sha256(open(SRC, "rb").read()).hexdigest(),
        "animation": args.animation,
    },
    "tracks": {name: {"mean": [round(sum(row[k] for row in rows) / len(rows), 4) for k in range(3)], "frames": rows} for name, rows in tracks.items()},
    "wrists": wrists,
}
if args.animation != "Idle_Loop":
    out["source"]["phase_offset_seconds"] = phase_offset
    # In-place stance feet travel backwards at the intended ground speed.
    # Estimate that speed from low, backwards-moving ankle samples, excluding
    # the airborne return. Median rejects contact/turnaround outliers.
    velocities = []
    leg_lengths = []
    intervals = 240
    dt = DURATION / intervals
    for side in ["L", "R"]:
        points = [world(idx("DEF-foot." + side), i * dt)[0] for i in range(intervals + 1)]
        low = min(p[1] for p in points)
        high = max(p[1] for p in points)
        for a, c in zip(points, points[1:]):
            speed = (a[2] - c[2]) / dt
            if max(a[1], c[1]) < low + (high - low) * 0.2 and speed > 0:
                velocities.append(speed)
        hip = world(idx("DEF-thigh." + side), 0.0, False)[0]
        knee = world(idx("DEF-shin." + side), 0.0, False)[0]
        ankle = world(idx("DEF-foot." + side), 0.0, False)[0]
        leg_lengths.append(math.dist(hip, knee) + math.dist(knee, ankle))
    out["stride_per_leg_length"] = statistics.median(velocities) * DURATION / statistics.mean(leg_lengths)
    # Locomotion must retain authored knee flexion, rather than centering the
    # shin around a straight leg and making half the cycle hyperextend.
    for name, bone, child in TRACKS:
        p = world(idx(bone), 0.0, False)[0]
        c = world(idx(child), 0.0, False)[0]
        out["tracks"][name]["reference"] = [round(v, 4) for v in unit(tuple(c[k] - p[k] for k in range(3)))]
with open(OUT, "w") as f:
    json.dump(out, f, separators=(",", ":"))
print("wrote", OUT, len(open(OUT, "rb").read()), "bytes, samples", count)
