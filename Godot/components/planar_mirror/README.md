# Planar Mirror

Instance `planar_mirror.tscn` into a world. Keep its +Y-facing PlaneMesh;
position/rotate/scale the root to place the glass. Each runtime instance owns
its material and viewports. Editor preview uses a separate unsaved viewport.

Reflected eyes use proper-handed off-axis cameras aligned to the glass. The
near plane stays on the glass, rejecting geometry behind it. World-space crop
rectangles map directly to glass UVs, independently per XR eye; head rotation
does not alter the camera basis or warp/flip the result.

At a distance, each eye renders one full-glass capture at `max_viewport_size`
(default 2048x2048, fitted to glass aspect). This preserves the original distant
clarity and pass count. The low-resolution overview is disabled then.

Close to the glass, a half-size overview supplies peripheral coverage, while a
full-resolution square detail capture follows the gaze intersection on the
mirror. Its physical side is four times perpendicular eye distance, with a 4 cm
minimum. Turning changes the patch center, not its extent or allocation, keeping
the same texels per meter even for wide glass and near-grazing views. The shader
softly blends patch edges over the overview. A distance hysteresis band switches
between full-glass and close detail targets without oscillation during head bob.
This replaces the old visible-bounds crop and turn-dependent resolution tiers,
which spread pixels across increasingly wide regions as the head turned.

The close path uses two scene passes per eye, with a narrower detail frustum;
the distant path uses one. There are no texture readbacks or GPU blits. All
reflection targets disable VRS/reduced render scale. Device profiling is still
needed: extra geometry submissions can matter on standalone headsets even when
fragment cost is bounded. Back-facing/off-screen mirrors stop every pass.

Layer 17 is local UI, 18 mirror surfaces, 19 first-person body/hands, and 20 the
full local avatar. Reflection cameras exclude 17/18/19 and include 20. Reflection
viewports additionally use a zero canvas cull mask, excluding all 2D UI. This also
prevents WebGL framebuffer feedback and recursive mirrors. Player cameras include
17/18 and choose their appropriate first-person body visibility.

GLES emits VIEW_INDEX as an unsigned integer. The glass shader converts it to
float in vertex and passes it to fragment, avoiding signed/unsigned comparison
errors. Headless tests cover UV/projection agreement, eye separation, wide-glass
texel density through turns, culling and allocation. Shader changes additionally
require an actual WebGL/GLES render; headset appearance requires device review.
