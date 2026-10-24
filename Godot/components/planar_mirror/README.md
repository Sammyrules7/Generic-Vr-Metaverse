# Planar Mirror

Instance `planar_mirror.tscn` into a world and position/rotate/scale the root so
`MirrorGlass` sits where the mirror should be. The visible face is the plane's
front; the shader culls the back. Keep the glass as a +Y-facing PlaneMesh in
its local space, as provided by the component.

The reflection uses an off-axis frustum fitted to the visible glass from the
reflected eye position. Its camera has a positive determinant and stays aligned
to the glass rather than copying the viewer's head rotation. Texture coordinates
come from the glass mesh, not SCREEN_UV, so asymmetric headset projections do not
flip or warp the reflection when turning.

Desktop uses one reflection pass. OpenXR/WebXR use distinct eye positions from
XRInterface and two ordinary SubViewports; the shader selects the matching
texture using VIEW_INDEX. The XR origin transform is applied exactly once.
All views use `max_viewport_size` (default 2048x2048), independently of the
browser/desktop window size. Targets match the glass aspect ratio and fit that
quality limit. Reflection viewports explicitly disable VRS, reduced 3D render
scale and screen-space AA; sampling uses the full-resolution texture level. Each visible stereo mirror
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


Close-up quality follows the visible portion of the mirror, independently per
eye. The glass polygon is clipped against each source eye frustum; a padded UV
rectangle concentrates the fixed pixel budget there. The camera frustum fits
that region and the shader remaps full-glass UVs into it. This avoids spending
most pixels on off-screen edges when looking closely at the center. Equal
normalized crop extents preserve the original glass/target aspect and avoid
reallocating textures on head motion. The reflected camera retains its fixed,
proper-handed basis; crop/UV mapping tests verify alignment while turning.

There is no project-controlled inverted foveation map. Headset compositor
foveation is separate from reflection viewport VRS; this change makes reflection
sampling uniform and prioritizes the visible center geometrically. Debug reports
actual per-eye sizes and crop rectangles. Device acceptance is still needed for
perceived sharpness, boundary stability and the cost of two 2048 scene passes.


Mirror glass reserves visual layer 18. Player cameras include it; reflection
cameras (including the editor preview) exclude it along with first-person layer
19. This prevents rendering/sampling a viewport's own attachment on WebGL, which
can raise framebuffer-feedback errors even when face culling removes fragments.
Other mirror surfaces are excluded too; recursive mirrors are not supported.
