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
- The reflection pass is capped at 1024x1024 and stops when the camera is behind
  the mirror or the glass is outside the view; close-up views use a frustum/OBB
  test so the last frame does not freeze.
- `ReflectCamera` uses `avatar/avatar_mirror_camera.gd` to reflect the full-body
  avatar layer while hiding the first-person layer. Remove that script from the
  component if it is used without the avatar system.
