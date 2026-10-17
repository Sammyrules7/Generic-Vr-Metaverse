# Moon Garden

A small moonlit garden terrace: forty-metre floor, four perimeter walls, eight
planters with glowing beacons, benches and a single moonlight. The floor, sky
and environment are saved in `moon_garden.tscn`; the planters, trees, benches,
walls and beacons are generated at runtime by `moon_garden.gd`.

## Light baking

Not lightmap-baked. The lighting itself would bake cleanly (one static
directional light plus ambient, no omnis, no flicker), but the garden
geometry is runtime-generated, and Godot lightmaps bake only against scene
contents saved in the editor. Porting the script-built meshes into the saved
scene would be the prerequisite for baking; until then the world is
realtime-lit, which is trivially cheap for its size.
