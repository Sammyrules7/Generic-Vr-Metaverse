# Starlight Observatory

A mountaintop observatory over a sea of clouds: entrance hall, lounge, dome
floor with a rotating star globe, and outer terraces. Architecture, collision,
furniture and lights are saved in `observatory.tscn` (the GLB instance with
editable children); shaders drive the sky, cloud sea and wind streaks. Preview
renders live in `tools/previews/`.

Run `res://worlds/starlight_observatory/tools/verify_scene.gd` headlessly to
check walkability, static bodies, globe interactions and input focus. The world
is registered in `worlds/world_registry.tres` by path.

## Light baking

The scene is now LightmapGI-ready (prepared by `tools/prepare_lightmaps.gd`,
which is preserved for reproducibility):

- The architecture GLB imports with **Lightmap** baking and generated UV2
  (`meshes/light_baking=2`, 0.2 m texel unwrap; the resulting
  `observatory.glb.unwrap_cache` is committed so reimports keep the UV2
  layout).
- The twenty static lantern/telegraph lights use **Bake Static**; Moonlight
  stays **Dynamic** so the terraces keep realtime moon shadows.
- Everything animated or self-luminous is excluded (`GI Mode Disabled`):
  the rotating star globe subtree (orbits, constellations, globe stars), the
  sea of clouds, and the four particle systems. The four hidden `-col` trimesh
  meshes inside the architecture instance are baked too: excluding them would
  need editable-instance overrides that duplicate the whole GLB into the
  scene, and they are duplicates of visible surfaces inside solid geometry,
  so baking them is harmless.
- A root-level **LightmapGI** node (texel scale 1.0) is present.

The scene ships pre-baked: `observatory.lmbake` (with its `.exr` data texture)
was generated with the Forward+ renderer on this setup, using Quality **High**,
**4** bounce passes, the built-in **denoiser** and **Shadowmask: Replace**, with
directional capture **off** (the Moonlight stays realtime, so baking it would
double the atlas for a shadow the engine already draws — without it the data
texture is ~16 MB instead of ~54 MB). **SDFGI is disabled** here: the bake is
the indirect-lighting source; keeping both was double GI and read washed out.
The flat night ambient stays enabled at low energy to tint the bake. Rebake
after layout changes: open the scene with the Forward+ renderer, select the
root-level **LightmapGI** node and choose **Bake Lightmaps**, keeping the
default `observatory.lmbake` name beside the scene.
