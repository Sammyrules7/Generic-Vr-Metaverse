# Generic VR Platform

A free and open source social VR platform built with Godot and Go. Explore seven
worlds using desktop controls, OpenXR, or WebXR, with peer-to-peer multiplayer,
positional voice, and an optional murder mystery game.

[Play in a browser](https://app.vr.maio-tech.com) ·
[Itch.io](https://sammyrules7.itch.io/generic-vr-metaverse) ·
[SideQuest](https://sidequestvr.com/app/61045/) ·
[Discord](https://discord.gg/6ybKAH2BfZ)

## Run locally

On x86_64 Linux, `nix develop` supplies the pinned Go, Godot, protobuf, and review
tools. Otherwise install the versions required by `Server/go.mod` and
`Godot/project.godot` (currently Go 1.26.5 or later and Godot 4.7).

Start the signaling server in one terminal:

```sh
nix develop
cd Server
go run .
```

In another terminal, from the repository root:

```sh
nix develop
godot --headless --xr-mode off --editor --path Godot --import
godot --path Godot
```

Local clients use `ws://localhost:8080/ws`. Set `VR_PLATFORM_SERVER_URL` to
override the client endpoint, or `VR_PLATFORM_LISTEN_ADDR` to change the server's
listen address. Release CI embeds the production endpoint using
`Godot/tools/configure_release.gd`. `VR_PLATFORM_ALLOWED_ORIGINS` is a
comma-separated list of HTTPS browser hostnames accepted by the server; native
clients do not send an Origin header.

After changing `Protocol/packets.proto`, run `bash Protocol/generate.sh` inside
the development shell and commit both generated implementations.

## Ownership

- `Server/`: in-memory room directory, membership, and WebRTC signaling. Run one
  instance; separate instances do not share rooms.
- `Godot/Networking/`: persistent signaling, room sessions, WebRTC mesh, and voice.
- `Godot/player/`: shared character motor, desktop/XR controls, and replication.
- `Godot/worlds/world_registry.tres`: bundled world catalog. New world IDs must
  also be allowed in `Server/room.go`.
- `Godot/game_modes/murder_mystery/`: rules, peer authority, and presentation,
  independent of the signaling server.
- `cloudflare/` and `.forgejo/workflows/`: browser delivery and releases.

Established peer connections survive signaling loss. Clients silently restore
directory membership with their original room token and peer/session IDs after
reconnection. Conflicting recovered identities are rejected without replacing the
surviving mesh. The mesh currently uses STUN only;
some networks require a TURN relay, which is not provisioned here.

## Web builds

The root URL serves the latest main build. `/<branch-slug>/` serves the latest
branch build at that URL; `/<branch-slug>/<40-character-commit>/` selects a
published commit. Only a missing trailing slash is redirected. Old commit URLs
remain usable while their stored builds are retained.

`scripts/publish_web.sh` uploads into `<channel>/builds/<commit>/assets/`, writes
a completion marker, then updates `<channel>/commit.txt`. Re-running a completed
commit reuses its assets. Pinned URLs may be cached immutably; live URLs require
revalidation. Live URLs intentionally can cross build versions if publication
happens between a browser's asset requests. Pointer propagation may take 30 seconds.

The worker also serves the active pre-migration `<channel>/assets/` layout when
no versioned build exists. Branch deletion removes its stored builds; retained
branches and the main channel need an explicit retention policy as storage grows.

See [player controls](Godot/player/README.md),
[murder mystery](Godot/game_modes/murder_mystery/README.md),
[cluster deployment](cluster/README.md), and the
[codebase review](docs/codebase-review.md) for details and remaining work.
The [CI follow-up](docs/ci-review.md) describes build triggers, cache behavior,
image updates, and further optimization options.

## Roadmap

- Broader device validation
- VRM avatar importing and switching
- Inverse kinematics
