# Generic-Vr-Platform

A free and open source social VR platform built with Godot and Go. Explore seven
worlds using desktop controls, OpenXR, or WebXR, with peer-to-peer multiplayer,
positional Opus voice via [TwoVoip](Godot/addons/twovoip/README.md), and an optional
murder mystery game.

[Play in a browser](https://app.vr.maio-tech.com) ·
[Itch.io](https://sammyrules7.itch.io/generic-vr-metaverse) ·
[SideQuest](https://sidequestvr.com/app/61045/) ·
[Discord](https://discord.gg/6ybKAH2BfZ)

## Run locally

On x86_64 Linux, `nix develop` supplies the pinned Go, Godot, protobuf, and review
tools. Otherwise install the versions required by `Server/go.mod` and
`Godot/project.godot` (currently Go 1.26.5 or later and Godot 4.7).

After cloning, run `git lfs pull` to materialize the bundled models and native
libraries before importing the Godot project.

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
VR_PLATFORM_SERVER_URL=ws://localhost:8080/ws godot --path Godot
```

The local command above selects `ws://localhost:8080/ws`. Without an override,
clients use the production endpoint. Set `VR_PLATFORM_SERVER_URL` to
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
surviving mesh. The mesh uses STUN and optional server-issued TURN credentials;
see [TURN setup](cluster/turn/README.md) for networks that require a relay.

See [XR rendering and world startup](docs/xr-runtime-performance.md) for the
headset quality defaults, remaining real-time lighting, and startup timing logs.

## Web builds

The root URL serves the latest main build. `/<branch-slug>/` serves the latest
branch build at that URL; `/<branch-slug>/<40-character-commit>/` selects a
published commit. Only a missing trailing slash is redirected. Old commit URLs
remain usable while their stored builds are retained.

Live HTML keeps the root or branch address and inserts a base URL for the chosen
commit. Relative PCK/WASM/JavaScript and worker URLs then use pinned paths, skipping
pointer reads and retaining immutable browser caching. One page load uses one
build even if a new build publishes during loading. Direct live asset requests
still revalidate, and HEAD/range requests preserve origin metadata.
The web export excludes unused XR Tools hand/glove variants; the selected
low-poly controller hands and optical hand models remain included. Adjust the
web preset exclusions if adding another addon hand style.

CI runs `node scripts/patch_webxr.mjs build/web/index.js` after the Godot web
export. Run this command for local web exports too. It updates the pinned
engine runtime to reconcile browser input sources at session start and before
each XR frame, including after returning from the browser. The patch rejects
an unexpected export-template layout; CI also tests the actual exported runtime.

New publications include precompressed PCK/WASM/JavaScript files for full browser
downloads. Compression runs in CI; the router selects the gzip variant. The CDN
caches each immutable storage URL separately through `fetch()`, without a second
Worker-managed cache. Byte-range requests use the original
files, and older builds without compressed variants remain supported.

`scripts/publish_web.sh` uploads into `<channel>/builds/<commit>/assets/`, writes
a completion marker, then updates `<channel>/commit.txt`. Re-running a completed
commit reuses its assets. Pinned URLs may be cached immutably; live URLs require
revalidation. Pointer propagation may take 30 seconds.

The worker also serves the active pre-migration `<channel>/assets/` layout when
no versioned build exists. Branch deletion removes its stored builds; retained
branches and the main channel need an explicit retention policy as storage grows.

Cloudflare redirects `vr.maio-tech.com` to the app with a Redirect Rule. The API
proxy remains until the Gateway TLS migration is applied; see
[Worker routing migration](cloudflare/README.md).

See [runtime avatars](Godot/avatar/README.md),
[player controls](Godot/player/README.md),
[murder mystery](Godot/game_modes/murder_mystery/README.md),
[cluster deployment](cluster/README.md), and the
[codebase review](docs/codebase-review.md) for details and remaining work.
The [CI follow-up](docs/ci-review.md) describes build triggers, cache behavior,
image updates, and further optimization options.

## Roadmap

- Broader device validation
- Broader avatar compatibility and tracking validation

## Builds and distribution

The app title, Android label, Windows product name, and download filenames use
`Generic-Vr-Platform`. The Android application ID remains
`com.maiotech.vrplatform`, and the existing desktop settings directory is retained
so renaming does not break upgrades or discard saved preferences. Existing Itch
storefront URLs, server names, and storage identifiers remain valid.

Every branch push and PR update runs **Web preview**. Same-repository PRs publish
under `pr-<number>/<commit>/`; fork PRs build without publishing credentials.
The PR checks area includes a `preview/web` status: while building or on failure,
its details link opens the workflow; once published, it opens that exact preview.
`https://app.vr.maio-tech.com/pr-<number>/` follows the latest successful PR build.
Closing the PR removes its previews.
Manual previews can target a branch, tag, or commit; their cache and download
identity use the commit actually checked out. Only non-PR builds can update the
main web channel.

For a manual build, open [Actions → Build native platforms](https://forgejo.maio-tech.com/Sammy/Generic-Vr-Platform/actions?workflow=Build-and-release.yaml),
choose **Run workflow**, select the branch, and run with the default options.
This builds Linux, Windows, and a signed Quest APK. Downloads appear in the job
summaries and Forgejo Releases; branch builds are marked as prereleases. Disable
the desktop checkbox for a Quest-only build. Windows and Linux downloads are
compressed `.tar.gz` archives; extract them before running.

**Build native platforms** has independent desktop and Quest jobs. A main
push affecting the game builds both. Itch publication and SideQuest notification
are restricted to main.
The Quest job checks the signature and application ID, publishes a versioned APK
as a Forgejo release asset, verifies anonymous download access, and
prints the link in the job summary. Branch builds are marked as prereleases.
This uses the automatic repository token and works without SideQuest configured.

To ship with the current pipeline:

1. Test the PR preview and, when needed, run **Build native platforms** on its
   branch to test installable builds.
2. Merge into `main` after checks pass. Game or release-workflow changes trigger
   the native jobs; every main push updates the web client.
3. Check the main **Web preview** and **Build native platforms** runs. Native
   jobs upload downloads to Forgejo Releases and publish to the existing Itch
   channels. The Quest job also notifies SideQuest when its secret is configured.
4. Confirm the live website, Itch downloads, and SideQuest version. The first
   real SideQuest submission still needs this end-to-end confirmation.

These are continuous releases: desktop and Quest have separate generated tags,
and APK versions use a monotonic build number. Creating a `vX.Y.Z` tag alone
does not trigger a release. A shared semantic version, combined release page,
and approval before storefront publication are not implemented yet.

Under repository **Settings → Actions → Secrets**, configure:

- `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_ALIAS`, and
  `ANDROID_KEYSTORE_PASSWORD`: the existing release signing identity. Keep using
  the same key for installed apps to update.
- `SIDEQUEST_WEBHOOK_URL`: the private URL from the SideQuest developer portal.
  Main pushes notify SideQuest when configured. For a manual main build, enable
  **notify_sidequest** to submit it. Keep this URL out of commits and chat.
- `BUTLER_API_KEY`: the existing Itch publication credential.

The APK's versionCode uses seconds since 2020, rather than a workflow-local run
number, so workflow changes cannot reset the Android update sequence. Never run
an older workflow to publish an update after switching to this scheme.

SideQuest's direct version webhook receives the public APK URL. An HTTP success
only confirms receipt; verify the version displayed on the listing. A retired
endpoint (including HTTP 410 or a `No! repo` response) fails the notification step
and preserves the APK link for manual submission in the developer portal. A
malformed `SIDEQUEST_WEBHOOK_URL` is skipped with a warning after the APK is
published, so a configuration mistake cannot block the release or Itch
publication; correct the secret to resume automatic updates.
