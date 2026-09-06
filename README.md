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
- [ ] Implement basic ui
- [ ] Implement .vrm avatar importer and switcher
- [ ] Implement IK
- [ ] Implement world switching and loading

## Stack:
- Godot
- Golang
- Kubernetes

## Networking checks

The Go server manages rooms and forwards Protobuf WebRTC signaling over
WebSocket. Game traffic travels directly between Godot peers.

The Godot client has three responsibilities:

- `Networking.gd`: the autoload owns the WebSocket, handshake, and reconnect loop.
- `room_networking.gd`: a `RefCounted` object owns the room list, membership,
  pending room command, and active mesh. Its `MultiplayerAPI` is supplied explicitly.
  UI and player code use `Networking.room_networking` for room commands and signals.
- `webrtc_mesh.gd`: negotiates WebRTC connections and buffers early ICE candidates.

Room state changes on server acknowledgments. Leaving closes the mesh; losing
signaling also clears the room list. Room signals fire after their state changes.
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
hand poses into the same remote avatar scene. Escape releases the desktop mouse
so the Leave room button can be used.

Run server regression tests with `cd Server && go test -race ./...`.

For the client integration test, start the server with `cd Server && go run .`.
Then, from the repository root, run:

```sh
godot --headless --xr-mode off --path Godot res://Networking/tests/network_test.tscn
```

This checks room UI error recovery, two-client WebRTC negotiation, duplicate
joins, failed joins, same-room rejoining, stale signaling, player spawning,
manager recreation, pose replication, disconnect cleanup, and reconnection.
It also runs the actual game scene through creating a room, walking, jumping,
and leaving while a respawn timer is pending.
It does not require a headset; physical VR controls still need device testing.

Every room entry gets a new session ID. Signaling names both endpoints' sessions
so delayed packets are rejected even when a peer rejoins the same room.
After editing `Protocol/packets.proto`, run `bash Protocol/generate.sh` to regenerate
the Go and GDScript bindings. The server and Godot client must use the same schema.
