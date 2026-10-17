# Briarwick Manor

A second, independent murder-mystery map: painted timber and plaster, arched windows,
blue-hour gardens and candlelit rooms. Quaternius's Fantasy Props showcase supplied
the visual reference: textured wood, rounded furniture details and warm light against
cool shadows. Its overt magic was deliberately left out. An abandoned bag, a letter
on the bed and a small music box suggest a household without explaining its history.

Open **briarwick_manor.tscn** in Godot. All architecture, kit instances, collisions,
furniture, lights, sound sources and particles are saved in the scene and visible in
the editor. There is no runtime world generator. The named room groups can be moved
and edited normally; imported models remain reusable glTF scene instances.

The 24 × 24 m interior has a central entrance hall, library, dining room, winter
gallery and guest parlour. Six open arches form two circulation loops. Window panes
have collision, and the exterior gardens are scenery. Sixteen player starts, twenty
clue positions and four knife positions feed the shared MurderMap adapter. The
guestbook is supplied at GameDisplay by the existing local presentation system.
Roles, ghosts, rounds and networking remain in the shared game mode.

## Furnishings

Look at a nearby object and press **F** on desktop, or point a controller and press
**B/Y** in VR. Brass plates attached to the objects indicate the control. The input
router requires enabled player controls, checks distance and line of sight, and
operates only one furnishing per press. It does not reuse murder-game buttons.

- Five candlesticks can be snuffed and relit, with animated wick flames, faint sparks,
  a short smoke plume and flickering local light.
- Sixteen windows have colored leaded glass, moving rain streaks and folded curtains;
  aim at the brass pull cord to draw or reopen them.
- The guest parlour music box can be stopped and restarted; its winding key moves
  while it plays the original waltz.
- The winter gallery's brass orrery can be set turning or brought to rest.

These are **local decorative interactions**: other players' furnishings are unaffected,
and the state resets when leaving the map. They do not change clues, collision routes,
roles or round outcomes. Curtains and moving effects are excluded from lightmap baking;
the switchable candle lights use Bake Disabled so a snuffed flame has no baked glow.
Static architecture and the main room lighting remain ready to bake.

## Light baking

1. Open the scene with the Forward+ or Mobile renderer.
2. Select the root-level **LightmapGI** node and choose **Bake Lightmaps**; save the
   generated lightmap data beside the scene. `briarwick_manor.lmbake` (with its
   `.exr` data texture) is included in the repo; rebake after changes.
3. Imported meshes already use **Static Lightmaps** and a 0.3 m import texel size.
   Primitive meshes have UV2 enabled and GI Mode Static. Retain the `.gltf.import`
   and `.unwrap_cache` files when committing; reimports preserve the UV2 layout.
4. Interior lights use Static baking; the moon uses Dynamic baking. A low-resolution
   sky supplies ambient reflections. The optional live reflection probe was removed
   after reproducing a seven-texture teardown leak with this Godot build. Tune lights
   and rebake after changing the layout.

The realtime lighting is a usable unbaked preview. Baked lightmaps should improve
the soft interior bounce and reduce the cost of the static lights. Dust, players and
game props remain dynamic. The existing original rain and waltz recordings are
referenced from Blackthorn's audio folder and play softly from spatial sources.

Godot reference: https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_lightmap_gi.html

## Authoring utility

`build_scene.gd` was used once to kitbash and save the scene. It is **not attached**
to the map. Prefer editing the saved scene; rerunning this command replaces those edits:

```sh
godot --headless --path Godot --xr-mode off --script res://worlds/briarwick_manor/build_scene.gd
```

Visual review (no unit tests):

```sh
godot --path Godot --xr-mode off --script res://worlds/briarwick_manor/render_preview.gd
```

This captures six room views in `/tmp/briarwick-*.png`, refreshes the catalog preview,
and captures before/after images of all four interaction types using the actual desktop
player and F input. It is a visual smoke run; no unit test suite is invoked.
The map is registered in `world_registry.tres` and the signaling server's world allowlist.

## Assets and provenance

Both kits are **CC0 1.0**, by **Quaternius**. Only a selection from their free Standard
editions is included. Original license notices are in each assets subdirectory.
No paid models, source projects or reference screenshots are bundled.

| Kit | Original page | Download used |
| --- | --- | --- |
| Fantasy Props MegaKit | https://quaternius.com/packs/fantasypropsmegakit.html | https://opengameart.org/sites/default/files/fantasy_props_megakitstandard.zip |
| Medieval Village MegaKit | https://quaternius.com/packs/medievalvillagemegakit.html | https://opengameart.org/sites/default/files/medieval_village_megakitstandard.zip |

The downloaded glTF texture paths were made local, with trilinear sampling. Texture
imports enable mipmaps, VRAM compression and a 2048-pixel limit to avoid distant
shimmer and excessive runtime memory use. The village normal maps use the
supplied Godot/Unity variants. Only referenced textures are retained. Mesh geometry
and painted textures otherwise remain the artist's originals. Rugs, simple garden
backdrops and the layout are original Godot scene work.

License: https://creativecommons.org/publicdomain/zero/1.0/
