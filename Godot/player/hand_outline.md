# Neutral interaction hands

Optical hands use the original humanoid-rigged hand mesh from the Godot OpenXR
demo, retaining its skin, bind matrices, bone axes, and triangle winding. Asset
provenance and the upstream license are in `hands/README.md` and `hands/LICENSE.md`.
Godot's native `XRHandModifier3D` updates the mesh from tracked joint poses.

`HandOutline` replaces the skin material with a neutral translucent fill and a
light silhouette contour with a darker inner contrast band. All five fingertips get a brighter fill and
outline. The hand fades from fully visible fingers through the palm to an invisible
wrist edge. These masks are baked into a private mesh copy's vertex colors from
the authored rest pose. They stay attached through skinning, translation and
rotation; the shader never compares animated positions to bind-pose coordinates.
Positions, normals, bone weights and skin binds are preserved. The procedural joint shell has been removed.

With an avatar equipped, the raw mesh fades in only near UI. This overlay
disables depth testing so the interaction hand stays readable over offset avatar
hands. Without an avatar, normal depth testing applies. The visual is restricted
to first-person rendering and casts no shadows; mirrors show the avatar's hands.
Controller fallback retains XR Tools' grip-animated mesh with the neutral outline
material and wrist fade, using its own rest-pose bone names.

Tracking tests cover open/curled poses, rotations, transformed origins, world
scaling, tracker replacement and skin bind/normal preservation. Partial position
or orientation data hides the skinned mesh rather than showing a frozen hand.
The visual is inspired by Quest's interaction hands; it uses no Meta assets.
