# Planar Mirror

Instance `planar_mirror.tscn` into a world and position/rotate/scale the root so
`MirrorGlass` sits where the mirror should be. The visible face is the plane's
front; the shader culls the back.

- Runtime follows the active player/XR camera, reflects its full pose across the
  glass plane, and samples the result in screen space.
- The editor follows the main 3D view camera, so the mirror previews without
  running the game.
- Each runtime instance duplicates `planar_mirror.tres`, so multiple mirrors do
  not fight over the same `SubViewport` texture.
- The reflection pass is capped at 1920x1920 (without exceeding the main viewport) and stops when the camera is behind
  the mirror or the glass is outside the view; close-up views use a frustum/OBB
  test so the last frame does not freeze.
- `ReflectCamera` uses `avatar/avatar_mirror_camera.gd` to reflect the full-body
  avatar layer while hiding the first-person layer. Remove that script from the
  component if it is used without the avatar system.

Set `max_viewport_size` on each mirror to trade sharpness for GPU cost. A cap of
1024x1024 restores the previous budget; 1920x1920 allows a full 1080p reflection.
At a 1920x1080 window this changes the reflection from 1024x576 to 1920x1080,
about 3.5 times the pixels for that pass. Geometry is still rendered once per
visible mirror; total frame cost depends on the scene and hardware.
