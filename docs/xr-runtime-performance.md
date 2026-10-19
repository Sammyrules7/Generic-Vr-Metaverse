# XR rendering and world startup

The web export enables threads. `ResourceLoader.load_threaded_request()` loads
resources in the background, but `PackedScene.instantiate()`, entering the scene
tree, scripts' `_ready()` methods, and initial GPU uploads/shader compilation
can still block frames. Startup now logs resource, instantiation, tree entry,
and preparation durations separately. These CPU timings do not measure the
first rendered frame or headset GPU frame time.

Blackthorn supports cancellable preparation with a 4 ms cooperative work budget,
including windows, bookshelves and mesh batches. The budget is checked between
operations; an individual mesh commit can exceed it. Prairie already uses
incremental preparation. Particle effects fill naturally rather than simulating
up to 13 seconds in one startup frame. Resource failures produce an error rather
than falling back to an unbounded synchronous load.

Four worlds ship LightmapGI data: Floating Island, Moonlit Grotto, Starlight
Observatory and Briarwick Manor. Blackthorn, Moon Garden and Prairie still use
real-time lighting. A static baked light also continues to illuminate dynamic
avatars and unbaked objects; disabling all scene lights would change their
appearance. See [Godot's LightmapGI documentation](https://docs.godotengine.org/en/stable/classes/class_lightmapgi.html).

While XR is active, the runtime uses 2x MSAA without an additional FXAA pass,
disables SSAO/SSIL/SSR, volumetric fog and glow, caps directional shadow distance
at 25 m, and fades baked positional lights from 16 to 24 m (preserving any
stricter authored fades). Lightmaps remain enabled. Desktop settings are restored
on XR exit. Ordinary fog and the procedural weather controller remain active;
environment resources used by the authored scenes are preserved. These are
quality/performance defaults; headset frame times still need measurement.

Optical meshes now refresh their palm anchor from joint data each frame, including
when joints recover before the default pose signal. A registered optical tracker
with temporarily missing data suppresses the controller fallback and its stale
ray. Recovery and tracker replacement are covered by the hand and lobby tests.

Validation uses `scripts/check_runtime.sh`, the lobby test and the world-loading
test. Headless tests verify behavior, geometry/collision equivalence and yielding;
they cannot establish a Quest WebXR FPS result or eliminate GPU startup stalls.
