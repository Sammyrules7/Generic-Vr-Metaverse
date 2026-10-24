# Planar Mirror

Instance `planar_mirror.tscn` into a world and position/rotate/scale the root so
`MirrorGlass` sits where the mirror should be. The visible face is the plane's
front; the shader culls the back. Keep the glass as a +Y-facing PlaneMesh in
its local space, as provided by the component.

The reflection uses an off-axis frustum fitted to the glass edges from the
reflected eye position. Its camera has a positive determinant and stays aligned
to the glass rather than copying the viewer's head rotation. Texture coordinates
come from the glass mesh, not SCREEN_UV, so asymmetric headset projections do not
flip or warp the reflection when turning.

Desktop uses one reflection pass. OpenXR/WebXR use distinct eye positions from
XRInterface and two ordinary SubViewports; the shader selects the matching
texture using VIEW_INDEX. The XR origin transform is applied exactly once.
All views use `max_viewport_size` (default 1920x1920). XR sizes its reflections
from the headset render target instead of the smaller browser/desktop mirror
window. Targets match the glass aspect ratio and fit that quality limit. Each visible stereo mirror
requires two scene passes, so profile on the target headset.

Back-facing and off-screen mirrors stop rendering. Stereo visibility tests use
both XR eye frustums. The near plane sits on the glass to reject geometry behind
it. The full-body avatar layer is included and the first-person layer excluded.
Editor preview uses an internal unsaved viewport; runtime instances own separate
material and texture resources.

Headless tests verify reflection positions, frustum/UV alignment, eye separation,
rotation stability, visibility and quality limits. Stereo appearance and GPU
cost still require a real OpenXR/WebXR device test.

GLES emits VIEW_INDEX as an unsigned integer despite its shader-language type.
The shader explicitly converts it to a float in the vertex stage and passes it
to fragment, avoiding an unsigned-versus-signed comparison rejected by WebGL.
Shader changes require an actual GLES/WebGL render check: headless projection
tests and export success do not validate driver shader compilation.
