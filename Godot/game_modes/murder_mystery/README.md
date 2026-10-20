# Murder mystery

Blackthorn House is a social world with an optional game. Approach the hall's
game table and interact to join or leave. Three opted-in players start a ten-second
countdown. Participants stay opted in between rounds; visitors can explore without
joining. Late entrants watch as ghosts until the next round. No story screens or
mandatory lore: an interrupted chess game and empty portrait frame
suggest the house's history.

Each four-minute round assigns one murderer, one detective, and bystanders. The
murderer starts with a concealed knife; the detective starts with a concealed gun.
Draw a weapon before using it. Innocents can recover a dropped gun or collect five
clues to earn one. Shooting an innocent kills both the target and the shooter.
The murderer wins when no innocents remain; innocents win by stopping the murderer
or surviving the timer. Results last eight seconds, then the next countdown begins.
The session advances these timers and its snapshot cadence using monotonic elapsed
time, rather than Godot's potentially clamped frame delta. Low frame rates may delay
the next visible update, but do not stretch a ten-second countdown into a minute.

Dead players remain ghosts until the round resets. Living participants cannot see
ghost bodies, names, held items, or shadows. Ghosts see each other and the living,
but cannot attack or collect items. Visitors also spectate invisibly during rounds
and can see each other. Remote avatar colliders are already disabled by the platform,
so spectators cannot block players. Ghosts still collide with the house to keep
locomotion familiar. During active rounds, living players hear only living
participants. Ghosts and visitors can hear the round and talk to each other, but
their speech is excluded from living players' voice audience. Results and game
teardown restore normal room conversation. Send and receive paths enforce the policy.

| Action | Desktop | VR controllers |
| --- | --- | --- |
| Join/leave at table; collect nearby item | E | Right grip |
| Draw/holster | R | Left grip |
| Drop weapon | Q | Left trigger |
| Fire/stab | Left click | Right trigger |
| Inspect private card in Blackthorn | Tab | Left A/X |

In Blackthorn, use the entry table's physical guest book to join and check the round.
Your private card briefly appears at round start; bring it back with Tab or left A/X
to inspect your role, time and five clue marks. Nearby pickups subtly brighten.
The desktop gun's modeled sight replaces an aim dot; VR uses the right controller.
Every murder map supplies a `GameDisplay` anchor for the guest book.
Existing movement and menu controls remain available. Optical
hand tracking still supports platform locomotion; game actions currently require
controllers or keyboard/mouse.

## Ownership

- `MurderRules` is a scene-independent model: roles, phases, items, deaths, victory,
  private snapshots. It has no world paths or networking dependency.
- `MurderSession` belongs to `Main/GameModes`, with its `player_manager` reference
  wired in the main scene. It binds on `local_player_spawned` and clears on
  `players_clearing`, before avatar destruction. Its endpoint outlives loaded maps
  to reject late packets safely; the networking autoload knows nothing about game
  modes. It elects the lowest
  connected peer ID, accepts requests using transport sender identity, validates
  phase, inventory, cooldown, distance and wall occlusion, and sends a tailored
  snapshot to each peer. Concealed weapons are omitted from public player state.
- `MurderMap` supplies spawn and pickup markers. The session binds it after the
  local player exists and unbinds it on room/world teardown. `PlayerManager` only
  emits generic lifecycle signals and has no murder-specific dependencies.
- `MurderPresentation` owns per-viewer ghost visibility, original mesh props,
  the display adapter, and local effects. `MurderSceneDisplay` supplies the physical
  book and private card from editable scenes at the map’s `GameDisplay` anchor. Clearing the mode
  restores avatar materials/visibility and removes the book and card.

Authority changes cancel the current round and preserve each connected client's
local opt-in preference. Old room packets and old-round action requests are ignored.
The elected peer necessarily knows all roles, and player movement remains client-owned
as in the existing platform; this is a cooperative P2P authority model, not a dedicated
anti-cheat server. Rules do not run on the Go signaling server.

## Adding a map

1. Create a `Node3D` world scene with the platform's `SpawnPoint` marker.
2. Add a direct child `Node` named `MurderMap` using `murder_map.gd`.
3. Add `GameSpawns`, `ClueSpawns`, and `KnifeSpawns` Node3D containers with uniquely
   named Marker3D children. Provide at least three player spawns, preferably sixteen,
   separated from walls/furniture. Place pickup markers above surfaces within reach.
4. Add a `GameTable` Marker3D where the join interaction should appear. The adapter's
   exported paths allow alternative node layouts. Marker positions are converted to
   global space, so translated/rotated map roots work too.
   Add a required root `GameDisplay` Marker3D on the table for the physical
   guest book/card presentation. Its local +Z is the
   page front; tilt it toward the reader and leave room for an 82 × 48 cm book.
5. Optionally add `GhostDetails` (initially hidden) for ghost-only scenery. Keep its
   details noninteractive so ghosts cannot affect a live round.
6. Register the scene in `worlds/world_registry.tres` and its stable world ID in
   `Server/room.go`. No changes to the rules, session, or presentation are needed.

## Verification

From the repository root with Godot 4.7:

```sh
godot --headless --editor --path Godot --xr-mode off --import --quit
godot --headless --path Godot --xr-mode off --script res://tests/murder_rules_test.gd
godot --headless --path Godot --xr-mode off --script res://tests/murder_presentation_test.gd
godot --headless --path Godot --xr-mode off --script res://tests/murder_session_test.gd
godot --headless --path Godot --xr-mode off --script res://tests/movement_test.gd
godot --headless --path Godot --xr-mode off --script res://worlds/blackthorn_house/validate_map.gd
```

The session suite uses independent local multiplayer peers; the presentation suite
checks visibility/material restoration. Physical headset tracking, controller aim,
comfort, and WAN WebRTC behavior still require device sessions. To play, run the Go
signaling server, open clients, select Blackthorn House, and join at its table.
