# Generic Vr Platform

A vr metaverse platform built on top of Godot

### [Join the discord](https://discord.gg/6ybKAH2BfZ)

## Why?
- FOSS
- Highly available
- Preformant

## Get it
- On [Itch.io](https://sammyrules7.itch.io/generic-vr-metaverse)
- On [SideQuest](https://sidequestvr.com/app/61045/)
- [Latest ci build](https://forgejo.maio-tech.com/Sammy/Vr-Platform/actions/runs/latest)

## Roadmap
- [x] Implement Basic Setup with ci/cd
- [ ] Implement Networking
- [ ] Implement Voip
- [x] Implement basic ui
- [ ] Implement .vrm avatar importer and switcher
- [ ] Implement IK
- [x] Implement world switching and loading

## Stack:
- Godot
- Golang
- Kubernetes

## Home worlds

- Floating Island: the original grassy home world.
- Moon Garden: an open courtyard with trees and benches.
- [Moonlit Grotto](Godot/worlds/moonlit_grotto/README.md): a waterfall sanctuary
  with a lagoon, quartz shrine, and glowcap mushrooms.
- [Starlight Observatory](Godot/worlds/starlight_observatory/README.md): a moonlit social terrace
  with an interactive star globe. Open `Godot/worlds/starlight_observatory/preview.tscn` and press
  **F6** to explore offline, or use `Godot/MainObservatory.tscn` with the room service.

## Networking checks

The Go server manages rooms and forwards Protobuf WebRTC signaling over
WebSocket. Game traffic travels directly between Godot peers.

The Godot client has three responsibilities:

- `Networking.gd`: the autoload owns the WebSocket, handshake, and reconnect loop.
- `room_networking.gd`: a `RefCounted` object owns the room list, membership,
  pending room command, and active mesh. Its `MultiplayerAPI` is supplied explicitly.
  UI and player code use `Networking.room_networking` for room commands and signals.
- `webrtc_mesh.gd`: negotiates WebRTC connections and buffers early ICE candidates.

Room creation and joining complete on server acknowledgments. Leaving closes
the mesh. Losing signaling clears the directory but preserves the current room,
players, and existing WebRTC data channels. Room signals fire after their state changes.
Room commands return `OK`, `ERR_BUSY`, or `ERR_UNAVAILABLE`. Accepted commands emit
`operation_started`, then `operation_finished` with success or an error message.
Request IDs associate replies with commands. A ten-second timeout reconnects the
signaling socket so an ambiguous operation cannot leave the client out of sync.

`Main.tscn` owns `PlayerManager`, with direct references to its player container
and spawn point. It spawns players on room entry and removes them on room exit.
Recreating the manager in an active room requests the existing peers' players.
`PlayerReplication` is a small persistent RPC endpoint under `Networking`; it
survives scene changes so late packets never target a freed player manager.

Every player uses `network_player.tscn`. Only the local player creates desktop or
VR controls; movement physics is shared. The replication endpoint sends body, head, and
hand poses into the same remote avatar scene. Escape opens the room menu and releases the desktop mouse.

Run server regression tests with `cd Server && go test -race ./...`.

For the client integration test, start the server with `cd Server && go run .`.
Then, from the repository root, run:

```sh
godot --headless --xr-mode off --path Godot res://Networking/tests/network_test.tscn
```

This checks room UI error recovery, two-client WebRTC negotiation, duplicate
joins, failed joins, same-room rejoining, stale signaling, player spawning,
manager recreation, pose replication with one or both signaling sockets down,
preservation of the mesh across reconnection, and explicit offline leaving.
It also runs the actual game scene through creating a room, walking, jumping,
and leaving while a respawn timer is pending.
It does not require a headset; physical VR controls still need device testing.

Every room entry gets a new session ID. Signaling names both endpoints' sessions
so delayed packets are rejected even when a peer rejoins the same room.
After editing `Protocol/packets.proto`, run `bash Protocol/generate.sh` to regenerate
the Go and GDScript bindings. The server and Godot client must use the same schema.

## Lobby and VR menus

Choose a display name (up to 24 characters), name your room, and select Floating
Island or Moon Garden. An empty room name uses your display name. Display name
and world preferences are stored locally. Names appear above remote avatars.
Room names accept up to 48 UTF-8 bytes; rooms hold up to 16 people. Search matches
room names and world titles. A joining player loads the world selected by the
room creator. To switch worlds, leave the current room and create or join another.

The lobby shows a connection banner only while disconnected; it disappears
after reconnecting. If the server is offline, room actions are disabled while setup remains
editable. It retries every two seconds, with an eight-second connection/handshake
timeout. In an active room, control-plane loss displays a notice in desktop or
VR without opening the menu, pausing movement, or removing players. Existing
P2P connections keep running; **Leave room** still works while offline.
The server address is configured in
`SERVER_URL` in `Godot/Networking/Networking.gd`, with no address field in the UI.
Previously saved server-address preferences are ignored. For standalone headsets,
set that constant to a reachable server address before building; `localhost`
refers to the headset itself.

The server distinguishes signaling disconnection from explicit peer departure.
Only explicit departure or the actual WebRTC transport disconnect removes a
remote player. After a signaling reconnect, the room remains on its original
P2P identity: fresh directory IDs and late signaling cannot replace the mesh.
The current server does not resume the old room membership, so this surviving
session is not automatically relisted. Leave it to create or join through the
directory again. New peer connections still require signaling; the continuity
guarantee covers already-established P2P links, not loss of the network itself.

OpenXR starts in the lobby. The same UI is displayed on a world-space panel
with pointers on both controllers. Point and pull the trigger to select.
Focusing a text field opens an on-panel keyboard; **Done** restores the room
browser. On desktop, use the mouse wheel over the room list or world preview. Up/Down selects rooms; Left/Right changes the focused world preview. In VR, hold the trigger and drag the room list, or swipe horizontally across the world preview. Aim at either area and use the thumbstick to scroll rooms vertically or browse worlds horizontally. Press **B/Y** (or a runtime
that exposes **menu_button**) to open the room menu, then resume or leave.
Desktop users press **Escape**. Movement and jumping are disabled while the
menu is open. Reopening the VR menu positions it in front of the headset.

`WorldCatalog` maps server world IDs to bundled scenes. Each scene has a
`SpawnPoint`; add new IDs to the server allowlist as well as the catalog.
Changes to the room protocol and player announcement RPC require rebuilding
both the server and clients.

Additional checks (run from the repository root):

```sh
# UI states, world metadata, search, capacity, and simulated VR panel input:
godot --headless --xr-mode off --path Godot res://UI/tests/lobby_test.tscn

# Start the Go server first; checks offline startup, retries, and recovery:
godot --headless --xr-mode off --path Godot res://UI/tests/offline_test.tscn

# Render the fixed-size lobby and keyboard to /tmp/lobby-*.png:
godot --xr-mode off --path Godot res://UI/tests/lobby_test.tscn -- --capture
```

Run these checks sequentially: they temporarily use the same local preference
files and restore them afterward. Automated VR checks simulate pointer events;
headset tracking, button mappings, and comfort still need physical device testing.

## Local world registry

Open `Godot/worlds/world_registry.tres` in Godot's Inspector and expand **Worlds**.
Each entry is a `WorldDefinition` resource with:

- **Id**: the stable world ID sent to the server, such as `floating_island`.
- **Title** and **Description**: the text shown in the selector.
- **Scene**: drag in the world's `.tscn` file. Its root must be a `Node3D`
  with a direct child `Marker3D` named `SpawnPoint`.
- **Preview**: drag in a screenshot or other texture. A 16:9 image works well.
  This is optional; a world without an image shows a placeholder in the carousel.

Increase the array size and choose **New WorldDefinition** to add a world.
Array order determines carousel order. Previous/next buttons wrap through the
entries, with a position count, rounded preview, title, and description. With
one entry the arrows are disabled; with no entries room creation is disabled.
Restart the running game after editing the registry. Incomplete entries
and duplicate IDs are skipped with a warning in Godot's output.

The client loads scenes only from this local registry. Add new IDs to the
allowlist in `Server/room.go` and rebuild the server too. All participating
clients need the same IDs and corresponding bundled world scenes; this does
not download worlds from the server.

The bundled previews are actual scene screenshots in `Godot/worlds/previews/`.
To regenerate these two previews with Godot's renderer:

```sh
godot --xr-mode off --path Godot res://worlds/tools/render_previews.tscn
```

Camera positions for that helper are in `worlds/tools/render_previews.gd`.
You can instead assign your own images directly in the registry.
