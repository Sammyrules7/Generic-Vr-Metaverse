# Neutral interaction hands

Optical hands use the original humanoid-rigged hand mesh from the Godot OpenXR
demo, retaining its skin, bind matrices, bone axes, and triangle winding. Asset
provenance and the upstream license are in `hands/README.md` and `hands/LICENSE.md`.
Godot's native `XRHandModifier3D` updates the mesh from tracked joint poses.

`HandOutline` replaces the skin material with a neutral translucent fill and a
view-angle silhouette highlight. All five fingertips get a brighter fill and
outline. Their mask is measured against the authored rest-pose tip bones before
skinning, so it follows finger deformation without tracking-space offsets or
per-frame shader position uploads. The procedural joint shell has been removed.

With an avatar equipped, the raw mesh fades in only near UI. This overlay
disables depth testing so the interaction hand stays readable over offset avatar
hands. Without an avatar, normal depth testing applies. The visual is restricted
to first-person rendering and casts no shadows; mirrors show the avatar's hands.
Controller fallback retains XR Tools' grip-animated mesh with the neutral outline
material, without the optical fingertip mask.

Tracking tests cover open/curled poses, rotations, transformed origins, world
scaling, tracker replacement and skin bind/normal preservation. Partial position
or orientation data hides the skinned mesh rather than showing a frozen hand.
The visual is inspired by Quest's interaction hands; it uses no Meta assets.
