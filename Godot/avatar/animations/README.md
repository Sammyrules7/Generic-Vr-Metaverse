# Avatar animation data

`quaternius_universal_idle_loop.json` supplies standing motion.
`quaternius_universal_walk_loop.json` and `quaternius_universal_jog_fwd_loop.json`
supply desktop locomotion. These are derived direction/wrist tracks (about
27 KB idle, 16 KB walk and 12 KB jog), not source glTF files. `AvatarRigDriver`
also uses the idle for restrained untracked-VR leg motion.

## Provenance

| Item | Value |
| --- | --- |
| Author | Quaternius |
| Pack | [Universal Animation Library](https://quaternius.com/packs/universalanimationlibrary.html) (standard/free edition) |
| Animations | `Idle_Loop` (2.5 s / 76 samples), `Walk_Loop` (1.333 s / 41 samples), `Jog_Fwd_Loop` (0.917 s / 29 samples) |
| License | [CC0 1.0](LICENSE.txt) (public domain dedication) |
| Redistribution | [J-Ponzo/gltf-universal-animation-library](https://github.com/J-Ponzo/gltf-universal-animation-library) |
| Redistribution commit | `e24c23cf2a1323488a3faa226ea7ea21f644b73e` |
| Source file | `glTF/AnimationLibrary_Godot_Standard.gltf` |
| Source glTF SHA-256 | `0ff075c7ad6855c5c2c37a171592ee8f0d6ab2f58259e2be77a9b63dd8027765` |
| Source glTF buffer SHA-256 | `6e65377d81558333c4093dbb144a48fd19019343d82b1a3a7992a98ec0e0543c` |

The original pack (about 4 MB of glTF plus buffers) is **not** part of this
repository. Only the extracted tracks and the license text are shipped.
CC0 imposes no attribution requirement; the provenance above is kept so the
data can be re-derived and reviewed.

## What was extracted

`Idle_Loop`, `Walk_Loop` (1.333 s) and `Jog_Fwd_Loop` (0.917 s) from that file. For each of the twelve humanoid bones the
source skeleton's world-space child direction was sampled at 30 Hz:

`Hips`, `Spine`, `Chest`, `UpperChest`, `LeftShoulder`, `RightShoulder`,
`LeftUpperLeg`, `LeftLowerLeg`, `LeftFoot`, `RightUpperLeg`, `RightLowerLeg`,
`RightFoot`.

For each side the hand offset relative to the upper arm was also sampled and
divided by that side's arm length, so it can be reused on avatars with
different proportions.

No root translation, scale, head, neck, finger or mesh data is stored. Nothing from
the source rig's rest pose or bone roll is stored either.

## Why it is directions, not rotations

Storing source local rotations would make every avatar inherit the source
character's A-pose, stance width and bone axes. Instead the driver computes a
swing from each track's mean direction to the sampled direction and applies that
swing on top of the target VRM's own rest direction. Static stance, proportions
and bone roll therefore stay local, while the timing and weight shift of the
clip remain.

The file stores the mean as the arithmetic mean of the sampled unit directions;
the runtime normalizes it before use. Samples are interpolated linearly between
frames, then normalized.

## Runtime mapping

- Desktop: torso, shoulders, legs and feet follow the clip; hands get
  clip-derived wrist targets for the existing two-bone IK, plus a small slow
  overlay so the 2.5 s loop does not read as mechanical.
- Untracked VR: only the legs and feet receive clip motion, at 55% strength.
  Hips, spine, chest and shoulder rest poses are left untouched, so the tracked
  eye anchor and the tracked arm roots do not move. Head, neck and arms never
  receive prerecorded motion in VR.
- A future full-body provider can set `lower_body_tracked`; the fallback then
  stops touching the legs. The driver never reads `XRBodyTracker` itself.
- If the file is missing or invalid, or a rig lacks the expected bones, the
  driver falls back to a small procedural idle and keeps working.

## Desktop locomotion

Walk and jog are authored in-place clips from the same pinned CC0 pack. Both
are aligned to left-foot forward contact before extraction and sampled with
one shared normalized phase, so blending between them does not mix opposite
feet. Cadence follows horizontal movement distance, scaled to the avatar's leg
length. Normal desktop speed (5 world units per second) uses walk at its authored pace.
Walk blends toward jog only between 6 and 7 world units per second;
playback is capped at 110% of authored cadence to avoid frantic stepping.
near zero speed the pose and wrists blend back to idle. Teleports and control
mode changes reset cadence.

Unlike idle's subtle motion around a mean, locomotion retains the source rest
direction as its reference. This preserves authored knee flexion instead of
centering a bent knee around a straight target leg. Wrist offsets use the full
upper/lower-arm segment lengths, so the jog's bent elbows do not inflate reach;
target wrist positions are also clamped to the avatar's arm length.

Backward movement reverses the cycle. Strafing redirects the thigh swing and
hand travel while keeping knee bend in the avatar's forward plane. These are
adaptations of forward clips, not separately authored directional animations.
The existing ground helper still handles contact and releases lifted feet.
The character motor and eye anchor remain authoritative: clips supply no root
motion and never move the player or camera. VR continues to use its existing
restrained idle and tracked poses.

If locomotion data is absent, the rig keeps its idle/rest pose rather than
preventing movement. No additional export filters are needed: existing
`avatar/animations/*.json` entries cover all three assets.

## Regenerating

The pinned source hashes are checked by `scripts/extract_avatar_idle.py` before
it samples `Idle_Loop` (animation index 9). Download the exact redistribution
commit above, then run from the repository root:

```sh
python3 scripts/extract_avatar_idle.py path/to/AnimationLibrary_Godot_Standard.gltf path/to/AnimationLibrary_Godot_Standard.bin /tmp/idle_loop.json
```

For locomotion, use the same pinned inputs and append `--animation Walk_Loop`
or `--animation Jog_Fwd_Loop`, with the corresponding output filename.
The default remains `Idle_Loop` and reproduces the original idle JSON unchanged.

Compare the output with the committed JSON before updating it. The tool uses
only Python's standard library; a different upstream pack requires reviewing
the source hashes, bone mappings and timing.

## Limits

- Feet are kept near their rest placement by keeping the motion small
  (`VR_IDLE_SCALE`), but this is not a foot-planting or root-motion solver.
  Uneven or shifted feet remain possible.
- The clip was authored for a humanoid without fingers; this data adds no
  finger motion.
- Export presets must include `avatar/animations/*.json` and
  `avatar/animations/LICENSE.txt` (or `avatar/animations/*`) via
  `include_filter`, otherwise the idle silently falls back at runtime.
