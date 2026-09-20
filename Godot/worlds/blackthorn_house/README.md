# Blackthorn House

An original, source-modeled single-level manor. The 28 × 24 metre footprint has a central foyer, library, dining room, gallery and social lounge. Three-metre openings form a loop, with no narrow door interactions. Players can simply spend time in the lounge; opting into the game happens at the entry table.

The anonymous paintings, one empty frame and interrupted chess game carry the small amount of implied history. There are no narrative prompts or story screens.

`blackthorn_house.gd` builds architecture and furniture from editable dimensions in metres, batched by material. `house_atmosphere.gd` adds local cosmetic motion and spatial audio. Actual window openings look onto a moonlit garden and iron fence; transparent rain shaders, leaded diamond lights, falling rain and folded cloth make the windows part of the room. The moon and hearth cast shadows; other lights provide soft, gently varying pools of light. Dust motes and embers use capped CPU particle emitters compatible with the web renderer. The grandfather clock has moving hands and a swinging pendulum; the gramophone has an original modeled brass horn and spinning record.

The clock, rain, fire and quiet gramophone waltz use original procedurally generated WAV loops. `audio/generate_audio.gd` contains their editable source; regenerate with `godot --headless --xr-mode off --path Godot --script res://worlds/blackthorn_house/audio/generate_audio.gd`. Audio is spatial and fades with distance. These effects carry no network/game state and stop when the world is freed.

The physical guest book at `GameDisplay` supplies public game status and joining instructions. A private hand card reveals the player's role briefly at round start, then can be opened with Tab or left A/X. It is only instantiated on the owning client's rig. Blackthorn has no persistent game HUD, aim dot or floating pickup text; nearby pickups gain a faint highlight and the gun uses its modeled sight. Platform room/menu controls remain available.

Collision geometry is deliberately simpler than the decorative model. The scene supplies 16 unique starts, 20 clue positions and four knife positions; all game state belongs to the separate `MurderMap` adapter and game mode.

From the repository root:

```sh
godot --headless --xr-mode off --path Godot --script res://worlds/blackthorn_house/validate_map.gd
godot --xr-mode off --path Godot --script res://worlds/blackthorn_house/render_preview.gd
```

The optional validator checks actual physics: unobstructed one-metre-wide avatars, a connected half-metre walkability grid, pickup volumes outside solids, and an unobstructed pickup ray within two metres of reachable floor. The render script saves a 1440 × 900 `preview.png` here and lounge, library, window, guest-book and private-card views in `/tmp`. Render previews with a graphics device, not headless mode. Use `--rendering-method gl_compatibility` to inspect the web-compatible renderer. Physical headset comfort and audio balance still need device review.
