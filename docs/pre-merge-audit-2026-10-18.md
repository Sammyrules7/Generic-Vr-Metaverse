# Pre-merge audit — 2026-10-18

Audit of `Multiplayer` at `e05120d` (tip, in sync with `origin/Multiplayer`) against
`origin/main` (`9230218`): **180 commits ahead, 0 behind** — a clean fast-forward
target. The branch is 672 files / +51k lines relative to `main`. All audit-turn
edits (Membership limiter, publisher retention, README/API wording, new publisher
tests) are **uncommitted working-tree changes** plus untracked `scripts/tests/`;
they passed with the parent's verification below. This report consolidates
user intent from the prior T3 threads and repository docs against the current
code. Audit and fixes only — no merge, deploy, or push was requested this turn.

## Intent sources

- [Review Networking Architecture Readiness](t3-thread://v1/bf86023b-30a1-4ed5-9cf1-8603b069e7d2)
  — review abstractions as a stopping point; user later asked for coturn +
  client-initiated switch-over so a coturn node restart doesn't drop players
  ("rolling restarts… kinda like how it does already for when the control plane
  restarts").
- [Fix missing world preview images](t3-thread://v1/bb62e628-9813-4579-b9b3-3f5686a45df8)
  — user wants all previews working **and** Forgejo act-runner CI without GitHub
  Actions ("Fix them all and migrate to forgejo").
- [Optimize Project Hot Paths](t3-thread://v1/ee53ffe4-cc58-4ffb-8bc9-e88548dc0b8f)
  — user values optimization and confirmed `.lmbake` lightmap data must ship.
- [docs/codebase-review.md](codebase-review.md),
  [docs/ci-review.md](ci-review.md),
  [docs/project-status-2026-10-06.md](project-status-2026-10-06.md) — earlier
  intents and accepted scope decisions (STUN-only fallback, live branch URLs,
  Recreate rollout for one-replica signaling).

## Verified against current code (all line refs at `e05120d` + working tree)

| Intent | Status | Evidence |
| --- | --- | --- |
| Transport/session/replication separation (stop-point verdict) | Still holds | [Godot/Networking/Networking.gd](../Godot/Networking/Networking.gd), [Godot/Networking/room_networking.gd](../Godot/Networking/room_networking.gd), [Godot/Networking/webrtc_mesh.gd](../Godot/Networking/webrtc_mesh.gd) |
| VoiceChat parent-order coupling fixed | Fixed | Injection before `add_child` at [Godot/Networking/Networking.gd](../Godot/Networking/Networking.gd#L42-L46); guarded rebind in [Godot/Networking/voice_chat.gd](../Godot/Networking/voice_chat.gd) |
| Silent survival of P2P sessions across signaling loss | Preserved (accepted tradeoff) | `detached_session` + detached-reply filtering in [Godot/Networking/room_networking.gd](../Godot/Networking/room_networking.gd#L37-L39); [README.md](../README.md) documents it accurately |
| TURN with client renegotiation after coturn restart | Implemented in code | Server mints ephemeral creds per join reply and leaves them disabled without relay config: [Server/turn.go](../Server/turn.go), [Server/room.go](../Server/room.go#L123); client applies creds with TTL refresh via re-join: [Godot/Networking/room_networking.gd](../Godot/Networking/room_networking.gd#L315-L343); transport-loss re-offer keeping membership (no despawn, 20 s × 4 bounded retries, 90 s deadline) in [room_networking.gd](../Godot/Networking/room_networking.gd#L354-L407) and [Godot/Networking/webrtc_mesh.gd](../Godot/Networking/webrtc_mesh.gd#L110-L127), including inbound re-offer with `connection == null` ([webrtc_mesh.gd](../Godot/Networking/webrtc_mesh.gd#L153-L161)) |
| coturn deployment artifacts | Present | [cluster/turn/README.md](../cluster/turn/README.md) (DNS/firewall/restarts, 41-port range) plus [job.yaml](../cluster/turn/job.yaml), [service.yaml](../cluster/turn/service.yaml), [rbac.yaml](../cluster/turn/rbac.yaml), [deployment.yaml](../cluster/turn/deployment.yaml), [kustomization.yaml](../cluster/turn/kustomization.yaml) |
| World previews in exported builds | Fixed in all five presets | No `worlds/previews/**` exclusion remains in [Godot/export_presets.cfg](../Godot/export_presets.cfg); all 7 previews referenced by [Godot/worlds/world_registry.tres](../Godot/worlds/world_registry.tres); the "No preview available" placeholder copy in [Godot/UI/room_selector.tscn](../Godot/UI/room_selector.tscn) is the fallback only |
| Forgejo act-runner migration | Hold mostly | No GitHub-hosted (`actions/*` from github.com) references remain on `Multiplayer` workflows; CI green at `348aaf1` during that thread. Two pinned [cache@v4](https://code.forgejo.org/actions/cache) uses remain in [Delivery-checks.yaml](../.forgejo/workflows/Delivery-checks.yaml) and [Web-preview.yaml](../.forgejo/workflows/Web-preview.yaml) — Forgejo-hosted action, act-compatible |
| Hot-path optimization retained | Present | `REPLICATION_HZ := 15` with cached transport revalidated per send in [Godot/player/player_replication.gd](../Godot/player/player_replication.gd#L12-L26) (the rejoin stale-cache regression was fixed during the networking merge) |
| `.lmbake` shipping | Preserved | Exclude filters omit `*.lmbake`; 4 baked worlds tracked ([Godot/worlds/floating_island/floating_island.lmbake](../Godot/worlds/floating_island/floating_island.lmbake) et al.) |
| Murder voice audience policy | Implemented | `set_audience_policy` / reset in [Godot/Networking/voice_chat.gd](../Godot/Networking/voice_chat.gd#L53-L192), bound in [Godot/game_modes/murder_mystery/murder_session.gd](../Godot/game_modes/murder_mystery/murder_session.gd#L90,L259); covered by the passing voice_audience suite |
| Dual world allowlist documented, in sync | Holds | Both sides list the same 7 worlds: [Server/room.go](../Server/room.go#L21-L29) and the registry above; cross-references documented in headers |
| Publisher retention | Improved this turn | keep-newest (3) plus incoming build and branch pointer with exact-SHA delimiting in [scripts/publish_web.sh](../scripts/publish_web.sh#L24-L42); regression tests in untracked [scripts/tests/test_publish_web.py](../scripts/tests/test_publish_web.py) now wired into Delivery-checks |
| Membership mint abuse limits | Improved this turn | Global quota moved after request validation and a per-socket member budget added: `admitMembership` in [Server/room.go](../Server/room.go#L212-L217), per-client field in [Server/client.go](../Server/client.go), quota regressions in [Server/network_test.go](../Server/network_test.go); documented in [cluster/turn/README.md](../cluster/turn/README.md) |

Verification this turn (parent checks plus delegated integration checks): Go `-race`+vet, Worker5
tests, publisher regression after a fixed fail-before assert, delivery native
checks/LFS, protobuf regeneration produces no diff, Godot 4.7.2 import, movement,
tracked hand, hand menu, codec/audience, all murder suites, weather, native
WebRTC networking, offline/reconnect, world-loading (20 assertions), lobby.

## Additional fixes and CI coverage

- Background TURN refresh timeouts now preserve the signaling socket and mesh,
  ignore delayed replies, and retry after backoff. The lobby treats refreshes as
  silent operations, avoiding an invalid operation/status lookup.
- A missing WebRTC connection can be recreated by an incoming offer; stale
  answers no longer recreate a connection with no local offer.
- Voice decode jobs have a per-peer pending limit so one sender cannot fill
  the entire shared queue. Native codec/audience regressions cover this path.
- [scripts/check_runtime.sh](../scripts/check_runtime.sh) runs nine headless
  suites and real local-server WebRTC integration with isolated preferences,
  deadlines and cleanup. Delivery-checks now invokes it on pull requests.
  The server reports its actual bound address so tests can use port zero.
- The claimed recovery-ID forgery was rejected after independent verification:
  HMAC authentication binds the IDs, so tampered claims fail before mutation.

## Practical optional refactors

- Centralize branch slug handling; collision-resistant names would change existing URLs.
- Automate vendored-addon upgrades while preserving local patches and provenance.
- Split voice preferences and virtual keyboard out of the room selector when
  making a related UI change with visual verification.

## Remaining verification limits

- **Valid live TURN allocation and relayed media were not proven by this audit.** The prior thread's final cluster proof covers STUN
  binding over UDP 3478 and bogus-credential rejection only; the
  [cluster/turn/README.md](../cluster/turn/README.md) verify section still asks a
  human to confirm relayed candidates. A forced-relay integration test with valid server-issued credentials and a relay restart remains needed; local direct WebRTC tests do not establish this behavior.
- **No physical headset verification** to prove XR runtime behavior; the
  usual warnings (Jolt solver-bias notice, OpenXR init error with `--xr-mode
  off`, ObjectDB/RefCounted residuals at world teardown) remain open.
- **Real microphone capture, permission allow/deny/retry, and WebXR
  exit/re-entry are untestable headless**; the hardware mic harness stays
  deliberately out of CI.
- **Seven-world lifecycle smoke passed:** all seven worlds admitted, loaded, spawned a local player, and cleaned up on leave against an isolated local server. Visible baked LightmapGI resources also loaded. Native networking integration passed again after the membership limiter change.
- **Forgejo workflows last verified green at `348aaf1`**, not at `e05120d`; the
  tip has not been re-run end-to-end (attention: atlas import memory/atlas
  requirement near `e05120d` and image pins are bot-managed).
- **Full exports and cloud deployment were not performed this turn** and are not
  covered by any passing check; the deployed web preview still reflects an older
  build until a new publish.

## Merge risks

1. **Everything is uncommitted.** The membership limiter, quota reordering,
   publisher retention, README/API wording, and `scripts/tests/` must be
   committed with the implementation before merging.
2. **Pushing the merge to `main` triggers the production release pipeline**
   (native builds + itch deploy) — stage the merge deliberately; see
   [docs/project-status-2026-10-06.md](project-status-2026-10-06.md#deployment-and-forgejo).
3. **Deploy client and server together ideally.** The protocol carries TURN credentials and signed
   recovery capabilities. The server rejects unsigned recovery claims; clients
   from before the signed-token upgrade must rejoin after the new server deploys
   ([cluster/turn/README.md](../cluster/turn/README.md)).
4. **Flux picks up image pins automatically**; after a toolchain change the bot
   may pin images only a cached runner can resolve — that handoff worked during
   the CI migration but re-check after a merge.
5. **Anonymous abuse limits are budgets, not hardening.** With the new per-socket
   limiter one socket cannot starve admission, but multiple persistent sockets
   can still exhaust the global mint budget — a remaining limitation.

## Recovery and final verification status

The original orchestration thread failed. Subsequent Big Pickle and Space Bunny
Free attempts failed immediately with `Rate limit exceeded. Please try again later.`;
those attempts supplied no review or verification evidence. No Codex subagents were
launched in the recovered thread.

Current-tree Go race tests and vet, all four publisher regressions, all five Worker
tests, ShellCheck for publisher/runtime scripts, and whitespace checks passed.
Final runtime verification passed after repairing the background-refresh UI handler
and replacing malformed SDP in the new regression fixture with a real generated
offer: all nine headless suites and real local-server WebRTC integration passed,
with no SCRIPT ERROR or malformed-SDP errors. Expected headless OpenXR and
ObjectDB warnings remain. Hardware and live TURN limits above remain unchanged.

The audit supports keeping the existing architecture and focused fixes rather than
a broad refactor. Automated functional checks pass; production readiness still
requires the relay-capacity and device validation described above.

## Beam Free independent review (this turn)

This Beam Free pass reviewed the final exact working tree, especially the
uncommitted networking/server/runtime/CI patch and its integration with the
lobby/player/game-mode paths touched by that patch. No nested agents, commits,
pushes, merges, or deployments were used. Authorized working-tree edits were
preserved.

Accepted findings:
- The uncommitted membership-limiter, publisher-retention, TURN refresh/rebuild,
  voice decode fairness, runtime-script, and UI refresh changes are internally
  coherent and match their regression tests.
- Server admission validation precedes quota consumption; per-socket and global
  budgets are updated atomically on success and preserved on rejection/recovery.
- The stale-answer/rebuild and refresh-timeout behavior is covered by the
  network regression fixture using real generated offer SDP.

Rejected or non-actionable observations:
- The earlier recovery counter-wrap forgery claim remains rejected: HMAC binds
  room/name/world/nonce/client ID/session ID, and tampered claims fail before
  mutation.
- The prior `__pycache__` addition and publisher mock failures seen during this
  pass were environment/PATH artifacts (missing `awk`), not repository defects;
  publisher tests pass with the CI toolchain.
- Headless OpenXR/ObjectDB warnings remain expected and are not functional
  failures.

Checks rerun this turn:
- `go test -race -count=1 ./...` and `go vet ./...` in `Server/`: passed.
- `python3 -m unittest discover -s scripts/tests`: 4/4 passed.
- `godot --headless --xr-mode off --script res://tests/voice_codec_test.gd`:
  0 failures.

Checks intentionally not repeated this turn: the full nine-suite runtime script
and native WebRTC integration already passed in the parent turn; repeating them
would add no new evidence. The known verification limits (live TURN relay,
physical headset/microphone/WebXR, exports/deployment) are unchanged and remain
unproven.

All changes remain uncommitted; nothing was pushed, merged, or deployed.
