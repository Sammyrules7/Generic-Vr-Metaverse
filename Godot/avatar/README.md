# Runtime avatars

## Ownership and loading

`AvatarService` owns shared downloads, verification, disk/parsed-scene caches and
serialized preparation jobs. `AvatarContainer` owns each player's visual model,
rig, springs and request lease. Releasing the last consumer cancels HTTP;
outstanding worker tasks are collected before their results are discarded.
Generation checks prevent stale results from replacing a newer selection.
Every player and preview gets its own skeleton, modifiers and simulation history.

HTTP is asynchronous. Threaded builds use worker jobs for verification, image
decoding, glTF parsing, detached scene generation, normalization, packing and
instantiation. Main-thread callbacks attach instances and install live tracking,
IK and spring modifiers. Workers do not mutate live scene-tree resources.
Non-threaded web builds use synchronous fallbacks. GPU uploads and first-use
shader compilation can still block rendering after CPU preparation completes.

## Catalog and asset proxy

`catalog.json` snapshots 4,274 public HTTPS VRM entries from nine Open Source
Avatars collections, plus bundled Godette. Explorer is the built-in fallback.
The catalog contains metadata; remote models download on demand. Compatibility
is checked during import, rather than assumed for every catalog entry.

`catalog_source.json` records the upstream revision. Refresh from a pinned commit:

```sh
python3 scripts/sync_avatar_catalog.py <upstream-commit>
```

Deploy the Cloudflare Worker and clients from the same catalog snapshot. Clients
request `/avatar-assets/<id>/<kind>`; the Worker resolves catalog IDs, supplies
CORS/CORP headers, caches successful responses and retries alternate IPFS gateways.
Peers announce catalog IDs rather than arbitrary public URLs. Pinned assets get
SHA-256 and exact-size checks; other public assets get GLB structure and 64 MiB
size checks, with disk-cache keys derived from their source URLs.

Registry metadata is CC0; models retain their individual licenses. Godette by
SirRichard94, adapted by Lyuma, is CC-BY 3.0; see `GODOT_VRM_SAMPLE_LICENSES.txt`.
The bundled Godette sample comes from V-Sekai/godot-vrm revision
`e15199f980064028bfa4fbee5e70dddb82dd55c3`, as recorded in `catalog.json`.
The addons are vendored separately (see their `.gitrepo` files):

- V-Sekai/godot-vrm, branch `only-addon`, revision
  `651205484c35f5cd7ba56475ff636e10db8ad674`.
- V-Sekai/Godot-MToon-Shader, branch `main`, revision
  `268c0d3b19c0885698b7bd39e21a16c9c2af448f`.

Preserve their upstream licenses.
The local MToon importer patch records existing ShaderMaterials in its replacement
map to avoid missing-replacement errors with Godette.

## Wardrobe

Home and in-game menus open the same Avatar submenu. All avatars, Favorites and
Custom are separate tabs; collection buttons and search scope filter the public
library. The grid adapts from two to four columns and appends batches of 18 cards
near the scroll boundary. Theme colors, margins, icons and primary buttons follow
the surrounding menus.

The preview rotates automatically. Selection starts a prioritized download and
shows its thumbnail while preparing the model. Wear is enabled after a successful
preview; failures reuse that action as Retry preview. Closing or changing selection
releases the preview lease. A failed replacement leaves the equipped model intact.
Creator credits appear on cards; license shorthand and full-credit tooltips use
the existing preview credits. Custom VRM 0.x/1.0 metadata populates those same fields
and persists in the local library. Older imports backfill metadata on their next load.

Thumbnails use two concurrent downloads, worker image decoding and a 64-texture
memory cache. GIF previews use their first frame. A 400 ms hover/focus warms at
most one model's verified bytes, without importing a scene or uploading its mesh.
Changing filters, leaving the card or closing the menu releases speculative work.
Byte totals drive determinate progress; preparation uses a bouncing pill segment.

Touch and XR scrolling share the existing menu navigation. Near-surface finger
motion distinguishes lateral scroll intent from inward pokes; ambiguous gestures
select on release. Contact feedback pins the original button, so release cannot
select a neighboring card. Tracking loss clears gesture history. The visible
scrollbars remain directly draggable.

## Rig, hands and ground contact

Normalization bakes standing eye height into mesh/blend-shape positions, skeleton
rests, skin binds, eye offsets and spring collider data. Skeleton/simulator node
scales remain one. Eye bones take priority over authored LookOffset data, with a
neck-proportioned fallback for incomplete rigs. Head and wrist anchors remain
independent of the replaceable visual model.

Desktop avatars blend directional walking with CC0-derived idle motion. See
[animation provenance and retargeting](animations/README.md). Untracked VR idle
moves only the lower body; tracked head and hands remain authoritative. Native
arm IK solves wrist position, with a following modifier applying wrist rotation.
Local optical finger rotations use Godot's native hand modifier.

`AvatarGroundFeet` shares the driver's humanoid axes, probes world collision layer
1 during physics ticks and uses native leg IK plus foot orientation. Standing feet
lock to the floor; animation swings, jumps and teleports release/reset contact.
Probes start above the locomotion floor even when crouching puts unsolved ankles
underground. Vertical head movement does not release standing foot locks. The
owning player collider is excluded. Missing bones, missing ground, steep surfaces,
disabled IK or tracked lower-body input leave the animation pose in control.

Ground placement preserves the eye anchor and bone lengths. `reach_limited` and
`target_gap` expose unreachable targets. Extreme avatar/user height differences
need calibration or pelvis adjustment. Sole offsets use mesh bounds or foot/toe
proportions, so unusual footwear and asymmetric geometry remain approximate.
Contact is single-point, without a heel/toe or moving-platform locomotion solver.

Native springs install after attachment. Passive imported secondary nodes retain
spring definitions without constructing the addon's duplicate solver. The local
spring preference defaults on and is not replicated. Bone colliders follow their
bones; node-based colliders use the transform captured at installation.

VR sets the torso back 10 cm while counter-shifting the head to keep the eyes
tracked. Avatar hands remain the normal in-game representation. Raw optical hand
meshes fade in near UI, using baked fingertip/wrist masks and a contrasting outline;
see [interaction hands](../player/hand_outline.md). Controller fallback uses the
same style. Tracking loss hides the interaction mesh immediately.

Player cameras exclude the full local avatar on layer 20. VR includes the
first-person body/hands on layer 19; desktop excludes both. Remote avatars use
world layer 1. Mirrors include the complete local avatar and exclude interaction
hands, local UI and mirror surfaces. The reusable mirror component owns its stereo
projection and resolution management; see [planar mirrors](../components/planar_mirror/README.md).

## Custom uploads and P2P

The Custom tab includes a plus upload tile, including in an empty library. Imports
preview without auto-wearing. Quest Browser disables the file picker only during
immersive WebXR and shows "Exit VR to upload". Other browsers and native Android
retain in-room uploads; a no-response warning helps diagnose picker limitations.

VRM 0.x/1.0 files (`.vrm` or VRM-bearing `.glb`) stay outside the project at
`user://avatars/custom/<sha256>.vrm`. Original bytes are preserved. The manifest
stores identity, size and extracted title/author/license credits. Hashes deduplicate
imports; only successfully parsed models enter the persistent library. Browser
persistence remains subject to storage quotas and eviction.

Worker preflight requires embedded buffers/images, rejects external URIs and
unknown extensions, and checks graph/buffer bounds. Limits are 32 MiB/file,
32 owned files/256 MiB, 100k triangles, 200k instanced vertices, 32 materials,
256 bones/skin, 128 morph targets, eight million vertex-target pairs, 4096 pixels
per texture side and 32 megapixels total. Springs have chain/joint/collider caps.
These checks bound resources; they are not a sandbox against importer bugs.
Separate `.gltf`, external images, compressed geometry and Unity/FBX sources need
conversion before import.

`PlayerReplication` owns the persistent `AvatarTransfer` endpoint. Spawn snapshots
and selection changes announce owned custom content hashes. Unknown hashes show
Explorer while fetching the owner's bytes. Receivers assemble, verify SHA-256,
extract embedded credits and run the same preflight/import pipeline. Only the
currently equipped owned asset is served. Received avatars cannot be selected,
favorited or re-shared as one's own.

Transfers use reliable high-level channel 2 (physical WebRTC channel 4), alongside
voice channel 1. A 48 KiB acknowledgement window stays below WebRTCJS's 64 KiB
receive queue, using 12 KiB chunks and a four-packet global per-frame send budget.
Two simultaneous receives cap payload memory at 64 MiB. Cumulative acknowledgements
resume valid prefixes after five-second stalls. Offer requests repeat; transient
failures retry three times with backoff. Idle timeout is two minutes and total
lifetime fifteen minutes. Identity can precede transport readiness or player spawn;
queued identities are replayed when those become available. Changes/disconnects
cancel obsolete work. All peers need the same channel/RPC layout.

Received bytes use a separate 128 MiB cache under `user://avatars/received`, with
no owned-library manifest entry. Parsed scenes share the normal bounded scene
cache. Nameplates show measurable transfer progress followed by preparation motion.

## Diagnostics and checks

Home and session menus link to Debug. Copy report includes platform/threading/XR
state, imports, stage timings, bounded event history, cached/received identities,
P2P queues/progress/retries and mirror target details. Reset clears diagnostics.

To profile a hitch, choose **Capture render hitches**, close Debug, reproduce the
selection/wear/mirror event, then reopen Debug and copy the report. Capture stops
after 30 seconds. Repeat with the cached avatar to compare cold and warm draws.
Monotonic frame gaps exclude unfocused/resume intervals. Render submission is CPU
wall time, not GPU completion; viewport timings are sampled once/second where
supported. Zero/unavailable GPU values do not mean zero GPU cost.

Web capture temporarily wraps existing shader compile/link/status, binding,
uniform-lookup and upload calls in the main WebGL context. Slow-call timestamps
share the engine clock. It does not inspect shader/upload contents, force work,
read pixels or send data anywhere. Worker contexts may be unobserved. Wrappers
are removed on stop; timings correlate with hitches without proving their cause.

[Godot's pipeline guide](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html)
excludes GLES/WebGL from ubershaders, pipeline precompilation and shader baking.
Warm-up there requires actual drawing, and moving synchronous compilation into a
hidden viewport can still stall gameplay. Mono previews do not warm every XR,
lighting, shadow or viewport variant. Native RenderingDevice builds support
pipeline counters/precompilation. Shader baking is enabled for native presets,
but cannot run in the headless CI export path.

After editor import, run `scripts/check_runtime.sh` in the development shell.
Export jobs run `scripts/check_godot_smoke.sh native` for the focused XR/avatar
suites; `web` runs the same common suites without the loading, container, rig,
springs and picker checks. `check_runtime.sh` remains the full runtime gate.
Focused suites live in `Godot/tests/avatar_*_test.gd`,
`Godot/tests/tracked_hand_test.gd`, `Godot/tests/mirror_test.gd` and
`Godot/UI/tests/avatar_picker_test.tscn`. Loading tests are offline by default;
`-- --network` adds pinned remote assets. The networking integration suite forces
real fixture bytes through WebRTC while testing avatar swaps and voice.

Shader changes also need an exported WebGL/GLES render. Headset acceptance covers
stereo mirrors, first-person appearance, contact feedback, arm/leg reach, tracking
loss, import stalls and spring cost across several avatars.

## Deferred body estimation

Native Meta OpenXR can supply `XRBodyTracker` skeleton data through the vendor
plugin, including inferred lower-body joints. It is not wired into this rig.
[WebXR body tracking](https://immersive-web.github.io/body-tracking/) would need a
feature-gated bridge through the existing WebXR JS patch, consent, tracking-loss
handling, replication and hardware validation. Neither path replaces the current
head/hands fallback yet; Debug reports tracker availability for investigation.
