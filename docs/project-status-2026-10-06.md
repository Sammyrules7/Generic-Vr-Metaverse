# Project readiness audit — 2026-10-06

## Implementation follow-up

The fixes below are now implemented locally on `Multiplayer`. The original
audit that follows records the state before these changes.

- Corrected optical hand rotations and hide hands without valid palm orientation.
- Preserved surviving room/peer/session identities across server restarts,
  rejected identity collisions, and added room recovery tokens to distinguish
  reused numeric room IDs. Clients reconcile peers returned during recovery.
- Reserved Menu/Select for returning home; B/Y remains available to world actions.
- Restricted murder-mystery voice during active rounds: living players can be
  heard by everyone; ghosts and visitors can talk among themselves. Results
  restore whole-room conversation. Send, receive, and queued playback enforce it.
- Integrated Prairie Crossing as the seventh world, with physical Daylight,
  Rain, and Night Lights buttons usable by desktop rays/E, controller rays and
  triggers, or a tracked right index fingertip. Weather is a local preference.
- Updated the headless networking suite to test voice transport without audio
  capture and to expect preserved identities during reconnect.

Validation passed: Go race tests and vet; Godot hand-pose, voice-audience,
Prairie weather/collision, lobby, offline/reconnect and networking checks;
movement and all three murder suites; all seven worlds' room/spawn/leave
lifecycle; protocol-generator ShellCheck and whitespace checks. Native renders
confirmed all three weather states and readable physical controls.

These changes are saved in a local WIP commit and have not been deployed. Deploy the updated
client and server together for the recovery-token protocol. Physical headset,
microphone permission flows, WebXR exit/reentry, WAN sessions, and performance
still require device verification. The obsolete Observatory/Grotto preview
validators and resource-lifetime warnings from the original audit remain open;
actual bundled scenes pass the world lifecycle check. World art, lighting and
interaction work can proceed with those limits recorded.

The platform is usable for world authoring, but the implementation is not fully
polished. Finish a focused platform fix pass for hand posing, restart recovery,
and a conflicting VR button before treating it as complete. No broad architecture
rewrite is needed to start building worlds.

Audited `Multiplayer` at `0a6335e429205d0c5b242ed6ddc9234aceaf025b`.
The checkout was clean and matched the live Forgejo branch. Only this report was
added; implementation files, other worktrees, remote branches, and deployments
were not changed.

## Where you left off

The latest project conversations were on September 20:

| Thread | Last outcome | Current status |
| --- | --- | --- |
| **Refine World and Add Weather Toggle** (`d61f427b-5031-433e-b082-5f7e994f2914`) | Consolidate Prairie Crossing's three weather worlds; final request was to put the toggle physically in the world for VR. | Uncommitted draft remains in a separate worktree. No final verification/completion message. |
| **Fix WebXR Room Flow and UI** (`23dbe591-ec4b-4d81-adf5-c57f1f66a94b`) | Web runtime startup, header status, silent room recovery, Desktop/VR badge, direct VR return home, and hand posing. | Committed/pushed as `33bec95` and `c44b283`; present here. Last report explicitly noted a failing headless voice assertion. |
| **Review and Simplify Codebase** (`5a24e2ac-4132-48e6-b7a2-c42d048f5e34`) | Networking/delivery cleanup, CI separation, image selection, caches and signing cleanup. | Present here, despite the older review documents saying the changes are uncommitted. Their latest tracked update is `50d2ade`. |
| **Polish Web VR Fallback and UI** (`1fc49071-f4da-43b0-959a-6bedda951dcd`) | Movement input, pointer lock, hand menu/touch, voice controls, tracking. | Committed/pushed as `6326e0a`. A later request changed the in-room VR menu action to leave directly. Physical-device verification remains outstanding. |

Your recollection of needing polish was accurate. The latest committed work
addressed bugs you had reported on the web/headset paths; it did not establish
that every physical interaction now works.

## Findings to address before platform sign-off

### 1. High: optical hand rotations still do not match tracking

`Godot/player/tracked_hand.gd:53-56` assumes bone poses are deltas from rest and
subtracts the authored rest rotation. Godot 4's pose rotation is local to the
parent bone; the extra inverse-rest multiplication is incorrect here. See the
[Godot Skeleton3D API](https://docs.godotengine.org/en/stable/classes/class_skeleton3d.html#class-skeleton3d-method-set-bone-pose-rotation).

A temporary harness fed both production hand drivers joint transforms derived
from their actual imported neutral skeletons. **25 of 26 bones on each hand**
differed from the requested orientation by more than one degree; the maximum
error was **110.78 degrees**. An isolated copy of the driver using the calculated
local rotation directly reduced mismatches to **0 of 26**, with maximum numerical
error about **0.056 degrees**. Production code was not edited.

Preserving bone lengths is sensible. Correct the local rotation assignment,
then check neutral/open/curled hands, partial tracking loss, orientation validity,
world scale, and rig movement on a headset. This finding is reproduced numerically;
it is not a claim that physical tracking/alignment was verified.

### 2. High: recovery after a fresh server restart has identity collisions

`Server/room.go:87-117` restores old peer/session IDs but does not reserve them
against the new server's counters. `Server/hub.go:27-43` starts IDs over from 2.
Temporary tests in an isolated copy of the server reproduced three failures:

- Recover peer 3 into room 9 on a fresh hub; the next normal client receives ID 3.
  Joining room 9 overwrites the survivor in the membership map: one member remains
  where there should be two (`enterRoom`, `room.go:120-132`).
- Recover session 1, then create a new room; the new membership also receives
  session 1. The client's duplicate-join path at
  `Godot/Networking/room_networking.gd:202-211` uses session equality alone and
  preserves the old mesh without emitting `room_joined` to load the new world.
- A new client creates room 1 before a survivor recovers its old room 1. Recovery
  accepts that different room, even when the survivor's world is Moon Garden and
  the new directory entry is Floating Island.

The existing recovery test removes/reconnects clients on the **same hub**, so its
counters never reset. It passes, but does not cover these fresh-process cases.
These are ordinary restart/order-of-arrival failures, independent of the accepted
choice to trust clients during recovery.

Reserve recovered identities, reject conflicting room identities/worlds, and
make duplicate membership detection include room identity. Also review peer-list
reconciliation: the preserved-mesh recovery path currently ignores the reply's
peer list, which could miss peers who joined while this client was detached.
That latter scenario was identified by inspection, not reproduced end to end.

### 3. Medium: Briarwick's furnishing button also exits the room

`Godot/worlds/briarwick_manor/manor_interactions.gd:64-71` uses `by_button`
(B/Y) to activate furnishings. `Godot/main.gd:195-197` treats that same button
as a room-leave action on either hand. A temporary invocation of the production
handler with a Briarwick room confirmed that B/Y leaves it.

Choose distinct bindings or route the interaction before the global leave action.
Keep the requested menu-to-home behavior. Update the hints/docs to the final
binding. This conflict should be fixed before polishing those world interactions.

## World implementation and unfinished drafts

The current catalog contains six worlds: Floating Island, Moon Garden, Moonlit
Grotto, Starlight Observatory, Blackthorn House, and Briarwick Manor. All six
successfully went through a real local signaling-server create-room flow, loaded
the world, spawned a local player, and removed the world and avatars on leave.
The client catalog and Go world allowlist match.

The scene/game separation is ready for further authoring: worlds own scenes and
spawn/interaction markers; the platform owns players/networking; the optional
murder mode binds through its map adapter. Add new IDs to both the catalog and
server allowlist. There is no architectural reason to postpone world work until
VRM importing, full avatar IK, crouching, or climbing exists.

Prairie Crossing lives outside this branch:

- Worktree: `/home/sammy/.t3/worktrees/Vr-Platform/t3code-d58ba504`
- Local branch: `t3code/refine-world-weather-toggle`
- Upstream: `origin/t3code/stylized-transmission-park-world`
- Committed base: `1f6b93f` (three weather variants).
- Draft: 11 tracked files changed plus two untracked scripts/shaders; consolidates
  the catalog into one world and adds weather transitions.
- `weather_control.gd` still builds a desktop CanvasLayer selector. Its VR path
  cycles weather when a trigger is pressed while looking toward the station;
  physical selectable Daylight/Rain/Night buttons from the final request are absent.
- The branch uses the older `WorldDefinition.scene` field; this branch uses
  `scene_path`. Its full registry also omits Blackthorn/Briarwick and newer profile
  settings. Port its world-specific work deliberately rather than replacing the
  current registry/profile with the older versions.

Other local worktrees still contain dirty movement, Observatory, starting-world,
and Grotto edits. Many corresponding features are already present here after
squash integration; dirty status is not proof every edit is new. Preserve and
compare them before deleting anything. Three local stashes also remain:
`Another codex pass`, `Mcp server`, and the old `Basic-setup` CI stash.

The older **Identify Unmerged Work Across Machines** thread recorded additional
Grotto/world/murder drafts on `sammydesktop`. Its claim that voice was unmerged is
now obsolete: `ac0fb20` integrated voice here. SSH to `sammydesktop` timed out during
this audit, so the remaining desktop drafts could not be reverified.

## Deployment and Forgejo

- Forgejo returned no issues or pull requests in the all-state queries.
- Latest web build/publish succeeded for `c44b283`:
  [run 139](https://forgejo.maio-tech.com/Sammy/Generic-Vr-Platform/actions/runs/139).
- Latest server-image build/publish succeeded for the same commit:
  [run 138](https://forgejo.maio-tech.com/Sammy/Generic-Vr-Platform/actions/runs/138).
  `0a6335e` subsequently updated image pins with `[skip ci]`.
- `origin/main` remains at `9230218` from July 15 UTC. There are 98 commits reachable
  from `Multiplayer` that are absent from remote main. The local `main` is separately
  divergent (one ahead, two behind its remote); do not use it blindly as a release base.
- The latest successful native release workflow was
  [run 55](https://forgejo.maio-tech.com/Sammy/Generic-Vr-Platform/actions/runs/55)
  on July 15. It does not establish that current Windows/Android changes ship.
- The browser root and `/multiplayer/` return different build configurations.
  Use the [Multiplayer preview](https://app.vr.maio-tech.com/multiplayer/) or its
  [pinned build](https://app.vr.maio-tech.com/multiplayer/c44b283547c588f3cc0d02ba052880737ccd3eb8/)
  when verifying recent work. Do not mistake the older root build for this checkout.
- Live and pinned HTML/JS/PCK/WASM assets returned HTTP 200; cross-origin isolation
  headers are present. The Multiplayer pack is **193,282,164 bytes** (about 184 MiB),
  an appreciable cold-load cost worth measuring before adding much more content.
- A successful image publication is not evidence of a Flux/Kubernetes rollout.
  Live cluster state was not inspected, and no rollout/release was triggered.

## Verification performed now

Godot `4.7.2.stable.nixpkgs.ed1daf0bf`, Go `1.26.7`.
Test profile/configuration writes were isolated under `/tmp/vr-platform-audit`
using separate `XDG_DATA_HOME` directories. Supplemental harnesses and an isolated
server copy were written there, not into production source.

| Check | Result |
| --- | --- |
| Godot import/parser | Pass; no script errors. |
| Go existing suite with race detection; `go vet ./...` | Pass. |
| Movement | Pass; 0 failures. |
| Murder rules | Pass; 53 assertions. |
| Murder presentation | Pass; 39 assertions. |
| Murder session integration | Pass; 85 assertions. |
| Lobby/world-loading tests | Pass. |
| Offline/reconnect test | Pass. |
| Six-world room/spawn/leave smoke harness | Pass. Pacing respects the server's room-command limiter. |
| Blackthorn map validator | Pass; 1,617 connected floor samples, 16 spawns, 24 pickups. |
| Supplemental optical-hand pose probe | Fails on production driver; isolated candidate correction passes. |
| Supplemental fresh-hub recovery probes | Three reproduced failures described above. |
| Existing networking integration suite | Fails waiting for voice on its dedicated channel; headless voice processing is disabled by design. |
| Observatory and Grotto verification tools | Both fail loading their absent `preview.tscn`; eventually timeout. Bundled actual world scenes load successfully. |
| ShellCheck | Pass for publisher, image updater, and protocol generator. |
| Actionlint | Pass with custom `default`/`nix` runner labels and GitHub-specific artifact-v3 warnings excluded. |
| Git whitespace | Pass. |

Warnings remain: Jolt ignores the legacy solver-bias setting; the XR starter
logs an OpenXR initialization error even with headless `--xr-mode off`. The six-world
smoke run reports three ObjectDB instances leaked at exit. Blackthorn's validator
reports ten instances and four resources still in use. Those warnings merit a
resource-lifetime follow-up; passing functional assertions do not prove leak freedom.

The collaborative browser downloaded the live build and captured its splash,
but later automation snapshots timed out. A second pinned-build attempt also
had not reached a verified lobby at the initial capture. Browser startup/gameplay
is therefore **inconclusive**, not passed and not established as a game defect.
No physical headset, microphone, permission-denial/retry, browser Escape, rendered
world performance, Windows/Android export, or WAN session was validated today.

## Remaining polish and recommended next session

1. Fix the hand rotation assignment and the fresh-server recovery identity cases.
   Preserve their small reproductions as focused regressions when implementing.
2. Resolve Briarwick's B/Y conflict. Verify menu-to-home, tracking loss, jumping,
   stick/pinch movement, and WebXR exit/reentry on the actual headset.
3. Verify current web and native builds, microphone allow/deny/retry, and desktop
   Escape. Repair the networking suite's headless voice assumption and obsolete
   world verification entrypoints so useful checks can finish reliably.
4. Resume Prairie Crossing in its existing worktree, finish the physical weather
   control, and port it onto the current world/profile interfaces.
5. Move into world art/lighting/interactions. Briarwick explicitly has no lightmap
   bake yet; its saved editable scene is ready for that work. Profile headset and
   web frame time rather than assuming the unbaked preview meets the target.
6. Before calling murder mystery finished, separate ghost/spectator voice from
   living-player voice. `VoiceChat.voice_packet.rpc()` currently broadcasts to the
   whole room, as the game README correctly states. Hand-tracking-only game actions
   are also not implemented; keyboard/mouse or controllers are required.

Keep the already accepted STUN-only connectivity and live branch-URL behavior
as known scope decisions. VRM/IK and dependency/retention housekeeping can stay
later roadmap items. Refresh the stale recovery/menu/uncommitted notes in README,
player documentation, and the September review files alongside the next changes.
