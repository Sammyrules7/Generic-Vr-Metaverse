# Starlight Observatory

A second home world: a moonlit alpine terrace, an open brass observatory dome,
a telescope, curved lounge seating, and an interactive constellation globe.
Aurora curtains and a galactic dust band frame snow-capped ridges and distant
beacon outposts. Slow cloud drift and gold/cyan particles animate the setting.
All models and shaders are original to this project. The existing floating island
and default startup scene are unchanged.

## Explore

Open `res://observatory/preview.tscn` in Godot and press **F6**. This is an offline
preview with its own controller; no signaling server or room is required.

From the repository root, force desktop mode with:

```sh
godot --path Godot --xr-mode off res://observatory/preview.tscn -- --desktop
```

| Input | Action |
| --- | --- |
| WASD / arrow keys | Walk |
| Mouse | Look |
| Escape / left click | Release / capture mouse |
| E near the globe | Cycle three constellations |
| R near the globe | Pause / resume rotation |
| XR left stick | Walk relative to headset heading |
| XR right stick | 30-degree snap turn |
| XR trigger near the globe | Cycle constellations |
| XR grip near the globe | Pause / resume rotation |

For XR, run the preview without the `--xr-mode off` and `--desktop` flags, with an
active OpenXR runtime. The preview uses controller input and simple hand markers;
it does not implement hand-tracking locomotion. Keyboard and XR interactions are
limited to a 4.2-meter radius around the globe.

## Use with the platform

`res://MainObservatory.tscn` provides the existing room selector and player-spawn
structure with this world. Run that scene to use the current networking flow;
it requires the same services as `Main.tscn`. All participants must launch the
observatory entry scene: the current room protocol does not negotiate a world ID.
Live multi-client behavior has not been tested for this scene.

`res://observatory/observatory.tscn` is the reusable world. It includes a direct
`SpawnPoint` child and recovers locally owned characters that fall below the world.
The globe's selection and rotation are local visual preferences, not synchronized
multiplayer state. The telescope and seats are scenery, with no telescope-view or
avatar-seating behavior.

## Edit and rebuild

The native scene exposes its atmosphere, lights, signs, and globe in Godot's tree.
The architecture is imported from `assets/observatory.glb`.

The editable Blender source is `tools/observatory/starlight_observatory.blend`
at the repository root. It retains separate objects. `build_assets.py` regenerates
that source and batches the GLB by material, separating colliding geometry.
Running it overwrites manual edits to the generated Blender file. For manual art
edits, export the GLB directly from Blender instead, preserving `-col` suffixes.

To regenerate everything from the scripts, run these commands from the repository
root in order:

```sh
nix shell nixpkgs#blender -c blender --background --python tools/observatory/build_assets.py
godot --headless --xr-mode off --path Godot --editor --import --quit
godot --headless --xr-mode off --path Godot --script "$PWD/tools/observatory/build_scene.gd"
```

The final command overwrites `observatory.tscn`; update `build_scene.gd` to keep
native scene changes reproducible. Blender is only required to rebuild the art.

## Validation and rendering

```sh
godot --headless --xr-mode off --path Godot --fixed-fps 60 --script "$PWD/tools/observatory/verify_scene.gd" -- --desktop
```

This checks floor coverage, spawn settling, walking to the globe, pedestal and
railing collisions, keyboard interaction, simulated XR trigger/grip input,
interaction range, and fall recovery. It exits nonzero on a failed check.

To also render three 1600×1000 views into `/tmp/observatory-*.png`, omit
`--headless` and append `--capture`. Reviewed images are in
`tools/observatory/previews/` at the repository root.

Tested with Godot 4.7.2, Blender 5.2.1, and desktop Vulkan Forward+ rendering.
Lighting uses cool, shadowed moonlight, two shadowed local lights around the globe
and dome, and smaller unshadowed lights at the tables and perimeter lanterns.
Lower ambient fill and SSAO give the seating and architecture stronger contact
shadows. These are realtime effects; no lightmap bake or external textures are
required. The sky shader stays static to avoid updating its reflection cubemap
every frame, while the cloud shader drifts slowly. Two seeded GPU particle
emitters provide 100 small, softly fading motes with gentle turbulence.

Exported architecture uses five static collision bodies, material batching, and
generated import LODs. The two distant beacon outposts are background scenery.
Lighting and particles are native, editable nodes in `observatory.tscn`; their
reproducible settings live in `build_scene.gd`. For a lighter render, disable SSAO
in `NightAtmosphere`, disable shadows on `GlobeAmberBounce` and `DomeWarmKey`, or
reduce the `amount` on `LoungeFireflies` and `ObservatoryStardust`.

Physical headset comfort, standalone headset performance, and mobile rendering
remain unverified. Desktop startup can report the host's missing `xdg-user-dir`
utility and Jolt's ignored shape solver-bias warning; these did not prevent the
scene checks or rendering.
