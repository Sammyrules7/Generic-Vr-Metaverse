# Prairie Crossing

A stylized interpretation of the supplied prairie-ravine photos, including the rainy paths and nighttime pylon silhouettes. Sage meadow, silver shrubs, conifers, wooden fences, and ridge houses surround a compact bench overlook. The layout is inspired by the photos rather than a surveyed recreation of a confirmed location.

Three versions are available in the room's world picker:

- **Prairie Crossing · Rain** — overcast light, drifting rain, quiet rain ambience, mist, wet paths, and rippling puddles.
- **Prairie Crossing · Daylight** — soft prairie colors and broad low-poly clouds.
- **Prairie Crossing · Night Lights** — a dark blue sky, pylon silhouettes, distant warm neighborhood lights, and subtle lights around the clearing.

Each version uses the same geometry and spawn. The fenced bench clearing is approximately 24 × 29 meters; the surrounding ravine, switchback, and meadow loop are scenery. The world is scaled to 80%, while the player and headset retain their normal physical scale. Perimeter collision contains movement, and out-of-bounds recovery returns the local player to arrival.

## Local preview

Run without a signaling server:

```sh
godot --path Godot --xr-mode off res://worlds/prairie_crossing/preview.tscn -- --desktop
```

Add `--weather=night` or `--weather=daylight` after `--desktop` for the other moods. WASD / arrows move, mouse looks, Escape releases the cursor. For the existing VR preview controller, omit `--xr-mode off` and `--desktop`; left stick moves and right stick snap turns.

`prairie_crossing.tscn` is the rainy scene. `daylight.tscn` and `night.tscn` inherit it and override the exported `weather_preset`. `weather.gd` configures the atmosphere after geometry generation.

All geometry and rain audio are generated locally with fixed seeds. Geometry is batched by material; meadow blades, rain, and distant clouds do not cast shadows. Distant night lights use a MultiMesh and only three nearby lamps use real lights. No external assets or network downloads are required. Physical VR hardware performance has not been measured.

## Validation and thumbnails

Check spawn scale, walking to the bench, all four perimeter colliders, and recovery:

```sh
godot --headless --xr-mode off --path Godot --script res://worlds/prairie_crossing/verify.gd -- --desktop
```

Capture each mood with a graphical renderer:

```sh
godot --xr-mode off --path Godot --script res://worlds/prairie_crossing/capture.gd
```

This saves arrival and bench screenshots to `/tmp/prairie-{rain,daylight,night}-{arrival,bench}.png` and updates the three picker thumbnails in `worlds/previews/`.
