# Moonlit Grotto

An open rocky island sanctuary with a waterfall behind a quartz shrine, a contained lagoon, a continuous stone causeway, glowcap mushrooms, warm arrival lanterns, and a star-filled sky above distant sea stacks. The cascade has falling droplets, impact spray, mist, and a spatial sound loop.

## Explore

Choose **Moonlit Grotto** in the lobby to create a networked room. For an offline
walkthrough, open `preview.tscn`; click to capture the mouse, use WASD to walk,
Space to jump, Esc to release the mouse, R to reset, and B to return to the lobby.

Alternatively, open `preview.tscn` in Godot and press F6, or run from the repository root:

```sh
godot --path Godot --xr-mode off res://worlds/moonlit_grotto/preview.tscn
```

The world scene is `worlds/moonlit_grotto/moonlit_grotto.tscn`. Its models,
shaders, audio, scripts, and authoring tools live beside it. Its direct
`SpawnPoint` child lets the shared room flow load and spawn players in the world.

## Authoring

The committed `.tscn` contains editable, named scene nodes, materials, and static collision. It does not generate geometry during gameplay. All new models and audio are original, reproducible assets; no downloads or Blender installation are needed to play.

From the repository root, regenerate with:

```sh
nix shell nixpkgs#blender -c blender -b -t 2 --python Godot/worlds/moonlit_grotto/tools/model_grotto.py
nix shell nixpkgs#python3 -c python3 Godot/worlds/moonlit_grotto/tools/make_water_audio.py
nix shell nixpkgs#ffmpeg -c ffmpeg -y -i Godot/worlds/moonlit_grotto/audio/waterfall.wav -c:a libvorbis -q:a 3 Godot/worlds/moonlit_grotto/audio/waterfall.ogg
godot --headless --xr-mode off --path Godot --editor --import
godot --headless --xr-mode off --path Godot --script res://worlds/moonlit_grotto/tools/build_grotto.gd
```

Regeneration overwrites `moonlit_grotto.tscn`; make lasting layout changes in `tools/build_grotto.gd` and geology changes in `tools/model_grotto.py`. The Blender exporter uses a fixed seed and exports GLB. The sound generator uses Python's standard library. The authoring tool detaches the imported scene before packing to avoid duplicate imported children.

## Rendering and validation

- Seven shaders plus a shared noise include: stationary mottled limestone, irregular water, waterfall ribbons, impact rings, soft particles, a cratered moon, and a procedural night sky with stars, clouds, and a galactic band. Rock materials do not scroll or project an animated pattern across dry surfaces.
- Lagoon water is clipped to the island basin; the surrounding sea sits lower. Waves and normals use warped noise, with distant normal detail reduced to avoid horizon shimmer. Highlights follow the scene lighting. No planar reflections, screen-space refraction, or depth textures are used.
- 592 particles across five emitters, with explicit zero-alpha and zero-scale lifetime endpoints and generous culling bounds. The cascade has dedicated falling droplets and ballistic impact spray. Only the directional moonlight casts shadows. Fog is regular depth fog.
- The moon disc, sky halo, and shadow-casting directional light share one direction. Crystals use outward clockwise winding and generated outward normals.
- The island foundation provides the basin floor, and a continuous low rocky rim marks and contains the lagoon. Flattened stone tops allow walking along the causeway. Players who leave the island are restored to its spawn transform.
- Checked on Godot 4.7.2 Forward+ using an AMD Radeon 760M. Actual headset rendering and standalone Quest performance have not been tested; profile before targeting a headset performance budget.

Run traversal, recovery, lobby transitions, crystal normals, moon alignment, particle fade endpoints, and perimeter collision checks:

```sh
godot --headless --xr-mode off --path Godot --script res://worlds/moonlit_grotto/tools/verify_grotto.gd
```

Capture a 1440×900 image (requires a graphics display):

```sh
godot --xr-mode off --path Godot --script res://worlds/moonlit_grotto/tools/capture.gd
```

The capture defaults to `/tmp/moonlit-grotto.png`; set `GROTTO_CAPTURE_PATH` to override it. Set `GROTTO_CAPTURE_VIEW=overview` for an elevated island view and `GROTTO_CAPTURE_SECONDS=14` to inspect a later particle cycle. `--xr-mode off` is only a desktop validation flag; project OpenXR settings are unchanged.
