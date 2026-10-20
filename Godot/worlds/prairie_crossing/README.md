# Prairie Crossing

One prairie ravine world with local Daylight, Rain, and Night Lights presets.
The weather station beside arrival has three physical buttons. Desktop users
aim and click a button, or press E within reach to cycle. VR controllers aim at
the button and pull the trigger; optical hands can touch with the right index
finger. There is no screen overlay. Weather changes affect only your own view.

The landscape is generated deterministically and batches geometry by material.
Rain/night effects are reused; lighting, materials, lamps, and audio transition
between presets and restore on return to daylight.

## Light baking

Prairie Crossing is realtime-lit by design and does not use LightmapGI. The
terrain, trees, grass, pylons and buildings are all generated at runtime by
`prairie_crossing.gd`, which Godot lightmaps cannot bake (baking happens
against scene contents saved in the editor). More importantly, the interactive
Daylight/Rain/Night presets tween the sun, lamps, sky and material colors at
runtime; a baked lightmap would freeze one preset and break the others. It is
an open outdoor scene where a directional sun plus ambient provides the look.

The world is registered in the current client catalog and server allowlist.
Run `res://tests/prairie_weather_test.gd` headlessly to check physical button
ray selection, repeated switching, and daylight restoration. Controller alignment,
fingertip comfort, and performance still require a headset session.
