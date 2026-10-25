# Neutral interaction hands

Optical hands use `NeutralHandVisual`: joint-sized rounded segments and a palm
shell, with a translucent neutral tint and a brighter outline at each fingertip.
Geometry follows joint positions directly. It has no texture, imported skin,
handedness flip or wrist-basis correction. Joint radii come from the tracker,
with bounded defaults when unavailable. Three instanced batches draw each hand.

The visual follows the same reference-space transform and world scale as UI
contact points. It hides immediately on missing/invalid joint positions. Joint
orientations are not required for this representation.

With an avatar equipped, the shell fades in only near UI. That overlay disables
depth testing to remain readable over avatar hands. Without an avatar, the shell
respects normal depth testing. Both variants are first-person-only and cast no
shadows. Avatar hands continue to appear in mirrors and to other players.

Controller fallback retains XR Tools' grip-animated mesh, using the same neutral
outline material. Controllers do not provide optical fingertip positions.

`tracked_hand_test.gd` checks contact-point alignment across curls, transformed
origins, scale changes, position-only tracking and tracker replacement. Dummy
headless rendering does not retain MultiMesh instance buffers; a real WebGL
run additionally checks the uploaded joint positions and fingertip weights.
