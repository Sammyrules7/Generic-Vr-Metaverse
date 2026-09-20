# Codebase and repository review

Reviewed 2026-09-20, starting from `6326e0a` on `Multiplayer`.

## Assessment

The main architecture is appropriate for this project. The Go server owns room
membership and signaling; Godot owns the mesh, avatars, worlds, and gameplay.
Keeping RPC endpoints alive across world changes is a good design. The shared
character motor and scene-independent murder rules also have useful boundaries.
Replacing these with a framework, an entity-component system, or more services
would add work without addressing the failures found here.

The strongest opportunities were lifecycle correctness, safer web publishing,
and making the development/deployment setup understandable. The changes below
are local working-tree edits, with no commit, push, deployment, or history rewrite.

This review covered first-party runtime scripts, the protocol and generated-code
boundary, the Go server, web routing, CI/Nix/Kubernetes configuration, export
settings, documentation, and local Git history/structure. Vendored libraries,
generated serializers, binary assets, and every authored scene property were
not exhaustively audited. TURN and scaling work are deferred at your request.

## Issues fixed

| Priority | Issue and consequence | Change |
| --- | --- | --- |
| High | An async world load could finish after leaving or switching rooms, recreating a world/avatar for obsolete membership. Main also waited on an unscoped spawn signal. | Added load/spawn generations; consume cancelled load results without attaching them. Main now reacts directly to `local_player_spawned`. Failed loads report an error and request a leave. |
| High | Voice worker results captured before mute or push-to-talk release could still be transmitted. Room changes could retain queued audio. | Recheck current controls immediately before sending; reset voice processing on room entry; handle worker startup failure and reject work when it is inactive. |
| High | WebSocket connections had no heartbeat/read deadline, retaining disappeared clients and rooms. | Send pings every 30 seconds, require pongs within 60 seconds, and bound HTTP header reads. |
| High | Signaling and membership churn were unbounded. Room updates amplify a sender's work into broadcasts to the directory. | Per-connection packet budget plus a smaller room-command budget, with correlated room errors and recovery after the budget refills. This is not a complete denial-of-service defense. |
| High | The API proxy constructed an upstream URL from an untrusted path. A `//host/path` could replace its configured host. Encoded asset paths also needed normalization before URL construction. | Assign the upstream pathname independently; reject traversal, backslashes, control bytes and malformed escapes; encode asset segments. |
| Medium | Publication overwrote live assets before switching the commit pointer. Pinned URLs stopped working on the next publication. | Upload to commit-specific storage, mark complete, then update the pointer. Completed commits are reused. Existing legacy storage remains readable during migration. |
| Medium | HEAD requests fetched object bodies, and unsatisfiable ranges were converted into 502 errors. | Forward HEAD and If-Range, preserve 206/416, and retain cross-origin isolation headers. |
| Medium | One replica still allowed an overlapping default rolling deployment, splitting clients across unrelated in-memory room directories. | Use `Recreate`; document the brief signaling interruption. |
| Medium | Reconnected signaling hid the warning for a room whose peer session was still detached from the directory. | Base the warning and room-command availability on detached membership. |
| Low | CI missed Nix image-source and web configuration changes; protocol regeneration only checked for one of its two Go tools. | Add workflow path triggers and check both `protoc` and `protoc-gen-go`. |
| Low | Web export-template paths hardcoded a patch version; development lacked a shared tool environment; deployment docs described an obsolete image registry. | Derive template paths from the package version, add a pinned development shell, and rewrite setup/deployment documentation. |
| Low | Release signing keys and default local build outputs were easy to accidentally add. | Broaden ignores for keystores, JKS files, Nix result links, and the Go executable. |

The web publisher is a shared shell script instead of two duplicated upload
blocks. Publishing and branch cleanup share a workflow concurrency group.
Forgejo describes workflow concurrency as best-effort serialization, not a
distributed lock; see its [Actions reference](https://forgejo.org/docs/v15.0/user/actions/reference/#concurrency).

## Behavior deliberately preserved

- `/` serves the latest main build directly.
- `/<branch-slug>/` serves the latest branch build directly.
- `/<branch-slug>/<commit>/` selects a published commit. Historical versioned
  builds continue working while retained. A historical build already overwritten
  before this change cannot be recovered by the router.
- Live URLs still resolve independently per request. A publish between asset
  requests can mix versions; this risk was explicitly accepted. There is no forced
  redirect from a live URL to a pinned commit.
- Established P2P sessions can survive signaling loss. Reconnection creates a new
  directory identity; leaving the detached session restores normal room commands.
- Existing test files remain untouched and were not run.

## What I would change next

1. **Separate game voice audiences.** `MurderSession` hides ghosts visually, but
   `VoiceChat.voice_packet` still broadcasts to the whole room. Ghosts and visitors
   can reveal information to living players. Add a generic voice audience policy
   owned by the game mode, with teardown restoring normal room voice. The game
   documentation now states the existing behavior accurately.
2. **Finish device-specific verification.** Android microphone permission is
   requested asynchronously while capture starts immediately; denied/granted
   permission and retry behavior need a real-device check. Verify WebXR entry,
   pointer lock, hand tracking, menu touch, and headset focus changes. The current
   automated checks cannot establish their physical behavior.
3. **Keep a small regression suite rather than deleting all tests.** Room/session
   ordering, cancelled loads, mute timing, and world/game teardown are valuable
   targets. You can remove redundant fixtures while preserving these invariants.
   Existing movement checks are referenced by release/preview workflows, and Nix's
   Go package normally runs its tests; deleting files requires updating those
   references too.
4. **Record dependency provenance.** Vendored XR/WebRTC code is convenient for a
   self-contained checkout, but upstream versions/checksums and local patches
   should be documented. In particular, `addons/godot-xr-tools/xr/start_xr.gd`
   contains application-specific behavior. Keep a patch record or move that
   behavior into an application-owned adapter before upgrading the addon.
5. **Make branch slug handling unambiguous before adding more preview branches.**
   Build and cleanup currently lowercase, replace punctuation, and truncate names.
   Different branch names can collide. Trailing hyphens after truncation are now
   removed consistently so those URLs work. A shared slug helper with a short hash
   suffix would avoid collisions, but changes existing URLs, so that was deferred.
6. **Choose an artifact retention policy.** Versioned builds are retained until
   branch deletion; main builds currently accumulate. Decide how long pinned links
   should remain available before introducing pruning.

The large room-selector script is a reasonable later cleanup: voice preferences
and the virtual keyboard can become separate UI components. I would only do that
alongside a UI change and visual checks; splitting files alone would add churn.

## Git and repository findings

The checkout was clean initially. Local Git object integrity passed `git fsck`.
Gitleaks found no matches in 170 commits of first-party source/configuration
history (about 13.22 MB). The unrestricted all-history scan was killed before
completion; the successful scan excluded vendored/generated code and skipped
targets over 1 MB. This is a scoped check, not a guarantee that all historical
assets or credentials are clean.
The object store was about 72 MiB, with most large tracked files being native
addons, assets, and a generated scene. This does not justify rewriting history or
changing the existing LFS setup now.

`Multiplayer` matched the locally recorded `origin/Multiplayer` at review start.
Local `main` is older than the locally recorded `origin/main`; several other
branches are attached to separate worktrees, and the voice branch has diverged.
These observations use local refs, not a fresh fetch. Do not delete those branches
or worktrees without reconciling their outstanding work. Nothing was fetched,
rebased, merged, or removed in this review.

Many recent commits fix CI/image delivery, which is another reason to keep the
toolchain and publishing logic centralized. Prefer descriptive commits over
messages such as `Idk` or `Clean up`, and separate runtime fixes from deployment
changes when committing this review.

## Verification

Temporary smoke harnesses were created outside the repository; none of the
existing test suites were executed.

- Go production build, `go vet` on production files, and `go mod verify` passed.
- Real local WebSocket checks passed for handshake, room creation/join/leave,
  rejected switches retaining membership, session-scoped relays, packet flooding,
  correlated membership throttling, and budget recovery.
- A timed heartbeat check removed an unresponsive upgraded socket while retaining
  a responsive idle client.
- Godot imported successfully with no script errors. All six worlds loaded,
  spawned players, and cleaned up through the local server. A cancelled load did
  not recreate the world.
- Two independent native Godot clients established WebRTC data channels and
  replicated both avatars. Queued voice results stayed suppressed after muting
  and releasing push-to-talk.
- Mocked worker checks passed for live/pinned paths, publication cache rollover,
  legacy migration, API origin confinement, path validation, HEAD, range responses,
  and cross-origin isolation headers.
- Mocked publisher checks verified upload-before-pointer ordering, completed-build
  reuse, and failure leaving the pointer unchanged. ShellCheck passed.
- Actionlint passed after suppressing the custom Forgejo runner-label warnings
  and GitHub-specific artifact-v3 deprecation warnings. Artifact action versions
  were retained; verify Forgejo compatibility before changing them.
- Nix server/image derivations and the development shell evaluated. Kustomize
  rendered the cluster configuration successfully. `git diff --check` passed.

Headless world runs still report the existing Jolt solver-bias warning and an
OpenXR initialization error because no headset runtime is available. The full
world teardown harness also reports three unclassified zero-reference RefCounted
instances at process exit; its functional checks pass, but this warning needs a
separate resource-lifetime investigation. The two-client harness exited without
that leak warning. No Android/Windows/web export, rendered visual inspection,
physical audio/headset test, live object-store publish, or cluster rollout was
performed.
