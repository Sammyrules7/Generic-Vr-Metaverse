# Moonlit Grotto

A moonlit limestone grotto with a lagoon, waterfall falls, glowcap shores and
a crystal shrine. The scene is self-contained: `tools/build_grotto.gd` flattened
the GLB geology into inline meshes, so everything renders without external
asset references. Landscape, props, collision and lights were saved once; the
generator is retained for provenance and should not be re-run casually.

Run `res://worlds/moonlit_grotto/tools/verify_grotto.gd` headlessly to check
moon direction, shadow flags, walkability and player recovery. The world is
registered in `worlds/world_registry.tres` by path.

## Light baking

The scene is now LightmapGI-ready (prepared by `tools/prepare_lightmaps.gd`,
which is preserved for reproducibility):

- All 336 static meshes carry generated UV2 (0.2 m texel unwrap applied
  per-instance over the inline geology and props).
- All nine lights use **Bake Static** — the scene has no scripted, flickering
  or moving lights. The directional **Moonlight** is kept `enabled = false`:
  its realtime contribution was a stray streak lighting the cave mouth's
  interior from outside; the night sky ambient carries the exterior instead.
- Animated or additive surfaces are excluded from baking (`GI Mode Disabled`):
  the stillwater and open sea, three waterfall curtains, the cascade ripples,
  the moon disc and the five mote particle systems. Emissive crystals,
  glowcaps and lantern flames remain included as static light sources.
- A root-level **LightmapGI** node (directional, texel scale 1.0) is present.

The scene ships pre-baked: `moonlit_grotto.lmbake` (with its `.exr` data texture)
was generated with the Forward+ renderer on this setup, using Quality **High**,
**4** bounce passes, the built-in **denoiser**, baking **Shadowmask: Replace**,
and directional capture on (a small 512×10240 atlas). Shadowmask has no visible
role here while Moonlight is disabled, so it costs nothing extra. Rebake after
layout changes: open the scene with the Forward+ renderer, select the root-level
**LightmapGI** node and choose **Bake Lightmaps**, keeping the default
`moonlit_grotto.lmbake` name beside the scene. Realtime lighting remains a
usable preview while retuning lights.
