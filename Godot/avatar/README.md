# Runtime avatars

`AvatarService` owns shared downloads, SHA-256 verification, a bounded parsed-scene
cache, and a disk cache. Containers acquire a request and release it on a new
selection or scene exit. Releasing the last consumer cancels HTTP; worker jobs
are collected even when nobody still needs their result. Each player gets its
own scene, skeleton, modifiers, and simulation history.

The catalog snapshots all 4,274 public, non-draft HTTPS VRM entries from the nine
Open Source Avatars collections, plus a bundled Godette sample and the built-in
Explorer. It is metadata only: remote models download on selection. Browse the wide wardrobe by
collection, with a thumbnail grid, favorites, and a persistent 3D preview. Search
by name/creator narrows the current collection. The rounded gallery starts with
18 cards and appends batches near the scroll boundary, without page controls. Models are not
pre-approved for compatibility: failures appear in the preview and the previous
player model stays equipped if a replacement fails to load.

Registry source/revision is recorded in `catalog_source.json`. Refresh with
`python3 scripts/sync_avatar_catalog.py <upstream-commit>`. A build uses the same
snapshot on every peer, so avatar replication still sends IDs rather than URLs.
The registry metadata is CC0; each model retains its collection license and the
picker shows creator/collection attribution. Downloads use the Worker `/avatar-assets/<id>/<kind>` route. The Worker resolves
only catalog IDs, adds CORS/CORP headers, caches successful responses, and tries
alternate IPFS gateways when the original gateway rejects a request. SHA-256 and exact sizes are checked where pinned; the upstream
registry does not publish these for most models, which receive GLB structure and
64 MiB size checks instead. Disk cache keys for those models hash the source URL.

Godette by SirRichard94, adapted to VRM by Lyuma, is CC-BY 3.0; attribution
appears in the picker. See `GODOT_VRM_SAMPLE_LICENSES.txt`.

VRM and MToon are vendored from V-Sekai/godot-vrm commit
`e15199f980064028bfa4fbee5e70dddb82dd55c3` under their original `addons/` paths.
Runtime extensions register once, independently of editor plugins. One local
fix in `1.0/VRMC_materials_mtoon.gd` records existing ShaderMaterials in the
replacement map, preventing spurious missing-replacement errors with the
Godette sample. Preserve the included upstream licenses when updating.

HTTP is asynchronous. Verification, caching and image decoding use worker jobs.
One serialized worker owns glTF parsing, detached scene generation, height/mesh
normalization and packing. Preview/player instantiation uses the same serialized
queue, with cancellable handoffs owned by the persistent service. Workers never
attach to the active scene tree or mutate a live player's resources. Main-thread
callbacks attach completed instances and configure tracking/IK/native springs.
Callbacks on freed players/pickers are discarded and detached nodes are freed.
Non-threaded web exports run the same operations synchronously. GPU upload and
first-use shader compilation can still synchronize with the renderer; detached
CPU preparation does not guarantee entirely hitch-free first rendering.

Standing eye height is baked into mesh/blend-shape positions, skeleton rest
translations, inverse skin binds, eye offsets, and collider data. Runtime
Skeleton3D and simulator node scales remain one, as required by the native
spring solver. Camera alignment uses the imported eye offset rather than the
head-bone origin. Desktop locomotion blends procedural walking with CC0-derived
idle motion. `AvatarGroundFeet` probes collision layer 1 on physics ticks and
uses native two-bone leg IK plus foot rotation to match the floor. It estimates
sole height from bind-pose mesh bounds (foot/toe proportions when unavailable),
locks standing feet, and releases animation swings and airborne bodies. The
owning player collider is excluded. No-ground, steep surfaces, missing legs,
disabled IK and tracked lower-body input fall back to the animation pose.

Ground placement never moves the camera or stretches bones. If the floor is
outside the avatar's leg reach, `reach_limited` / `target_gap` expose the remaining
gap; extreme avatar/user height differences need future calibration or a pelvis
solver. Sole bounds are an estimate for unusual shoes, skirts and asymmetric
feet. This is single-point contact, not heel/toe collision or moving-platform
locomotion. Native/WebXR full-body tracking is not implemented.

`PlayerReplication` reliably announces catalog IDs in spawn snapshots and on
selection changes. Body/head/hand poses retain their existing unreliable update
channel. The scene-owned container keeps `Head`, `LeftHand`, and `RightHand`
anchors stable for voice and input, replaces only model visuals, and consumes
local tracking every display frame. Local VR uses the avatar's own hand geometry. Separate controller/optical hand
models are hidden when a humanoid avatar is present and remain a fallback for
Explorer or incomplete rigs. Optical UI overlays use a neutral joint-position
shell with brighter fingertip outlines; it fades in near the menu and stays out
of mirrors. See `player/neutral_hand.md`. Local finger rotations use native XR hand modifiers;
replicated wrist targets drive both end position and orientation after arm IK.

Player cameras reserve visual layer 19 for the local VR body and tracked hands,
and layer 20 for the full local avatar. Desktop player cameras exclude both;
VR cameras include 19 and exclude 20. Remote avatars use world layer 1. Attach
`avatar_mirror_camera.gd` to a mirror's Camera3D (or call
`AvatarView.configure_mirror_camera(camera)`) to include layer 20 and exclude 19.
This keeps the complete head/body/hands in reflections without showing duplicate
headless geometry or tracked hands. Worlds still provide the reflection surface,
SubViewport, and reflected camera transform; this change adds no world mirror.

The Avatar submenu is available from the home and in-game menus. It uses the
horizontal panel space for collection navigation, a three-column gallery, and a
preview/equip pane. Favorites persist in the profile. The preview supports automatic
rotation, retry on failure, and disables equipping
until a preview succeeds. Thumbnails download separately from models, with two
concurrent requests, worker-pool image decoding, and a 64-texture memory cache.
A 400 ms card hover/focus warms at most one verified model download without
parsing a scene or uploading textures; leaving, changing filters, or closing releases it.
Selecting a hovered avatar shares the existing download. The scene is imported
only after selection. GIF thumbnails use their first frame; PNG/JPEG/WebP are also supported. Closing
or changing filters cancels pending thumbnail HTTP requests. Appending cards
preserves existing requests and scroll position. Unavailable images
keep a text placeholder without blocking selection. Spring bones
are a local viewing preference, enabled by default, rather than network state.
VRM bone colliders follow their bones. Node-based colliders currently use the
transform captured at installation; dynamically animated node colliders need a
follow-up adapter. The curated Godette sample uses bone colliders.

## Checks

After an editor import, run the avatar loading, container, rig, and spring tests
with `godot --headless --xr-mode off --path Godot --script
res://tests/avatar_loading_test.gd` (substitute the relevant test filename).
Loading tests use bundled bytes by default. Append `-- --network` to exercise
the three pinned remote assets; the optional `SSL_CERT_FILE` test trust store
does not disable TLS verification. The multiplayer suite also checks selection,
late-join snapshots, unknown IDs, and stable voice anchors.

Device acceptance still needs an exported browser and headset: material and
first-person appearance, arm reach/rotation, wrist seams, tracking loss, menu
contact, import stalls, and spring frame cost with several avatars. The native
spring solver is cosmetic local simulation; its result is not replicated.

The wardrobe inherits the room selector's theme, including the 16 px horizontal /
12 px vertical panel and button margins. Icons are bundled SVGs, not Unicode
symbols that rely on desktop font fallbacks. Explorer is an ordinary Bundled
entry; there is no separate reset/turntable control. Deploy the Worker from the
same catalog snapshot before publishing clients that use the asset proxy.

The panel's outer edges use the same scaled 32 px horizontal / 24 px vertical
margins as the lobby. The category title/count replace the redundant header;
Done shares the bottom action baseline in the sidebar, with the existing primary
button treatment and a check icon. Hair/cloth motion remains enabled by preference.
Clicked thumbnails preempt background thumbnail HTTP and appear in the preview
while the model downloads. The proxy reads the GLB length header and uses a fixed-length stream, allowing
the progress bar to show downloaded MB / total MB without buffering the model.
Indeterminate progress remains a fallback when Godot cannot expose a byte total.

The full-library search placeholder is "Search all". Artist credit appears on
avatar cards. License shorthand is right-aligned at the preview's bottom-right
corner. Progress and status overlay the clipped preview without resizing it;
Wear becomes Retry preview after a failure.

Desktop humanoids use procedural idle breathing, directional stepping, knee/foot
motion, torso counter-rotation and arm swing. The rig derives horizontal velocity
from the avatar container's world movement, so remote avatars and the local
mirror body animate without additional RPCs or downloaded animation assets.
Speed blends into idle on stopping; teleports reset the motion estimate. Available
humanoid bones are animated independently, so incomplete rigs skip missing bones.
Switching to VR restores the original bone poses and uses tracked hand targets.
The eye position remains attached to the camera while the torso animates.

Viewpoint resolution is shared by normalization and the live rig: paired eye
bones take priority, followed by a nonzero authored LookOffset. If neither is
available, a neck-proportioned offset places the viewpoint above the head joint.
This avoids aligning the camera with the base of the skull on incomplete VRMs.


Texture decoding runs as a CPU-only worker job in threaded builds. Runtime GLTF
parsing, scene generation, normalization, mesh upload and packing stay on main
but are separated by frame boundaries. Normalization transforms packed vertex
arrays in native code. Avatar hand geometry is retained without building extra
handless meshes. Single-threaded web exports use CPU fallbacks. Godot's indivisible GLTF calls and first-use GPU/shader work can
still cause a hitch for large avatars; this is not a fully asynchronous importer.

Imported secondary nodes use a passive source script in cached scenes. It keeps
spring definitions and collider paths but skips the add-on's runtime solver
initialization; AvatarSprings installs the native solver after the model enters
the tree. This avoids allocating two solvers during preview/equip.

The wardrobe supports native touchscreen and XR pointer dragging over avatar
cards and collections. Fingertips give hover feedback at 15 cm, with a 20 cm exit zone to prevent
flicker. Contact immediately highlights and pins the original button. Rays and native
touchscreens select on release with tremor tolerance; optical fingertips can
confirm by pressing through the surface before withdrawal when their approach
is predominantly normal to the panel. The last 140 ms of near-surface motion
classifies the approach: at least 6 mm of lateral travel latches scrolling, while
a predominantly inward approach permits early poke confirmation. Scroll intent
starts dragging immediately and cannot become a click through deeper penetration.
Ambiguous approaches retain tap-on-release behavior; release never selects a
neighboring card. Tracking loss and leaving the near-surface zone reset history.
The separate scrollbar remains directly draggable.

VR applies a 10 cm torso setback while counter-shifting the head to keep its eye
position tracked. This puts the camera in front of the chest when looking down
without moving wrist goals. Accurate optical hand overlays fade in near visible UI and fade out on withdrawal;
they use native joint poses and per-hand alpha materials supported by the mobile
and Compatibility renderers. The full avatar remains visible in mirrors.
Touch tuning follows Meta's surface-normal poke and contact-feedback guidance:
https://developers.meta.com/vr/design/touch_specs/
https://developers.meta.com/vr/documentation/unity/unity-isdk-poke-interaction/


## Local Custom library

The Custom tab includes a plus upload tile alongside owned avatars, including
when the library is empty. There are no sidebar upload/status controls. Upload
is enabled both in rooms and immersive mode for device testing; picker callbacks
and a ten-second no-response warning make browser limitations observable rather
than blocking the action. Import status/errors appear on the tile. VRM 0.x/1.0
files (.vrm or VRM-bearing .glb) are copied into
`user://avatars/custom/<sha256>.vrm`. The small manifest saves hash, title and
byte size; source files stay outside the project. Imports preview without
immediately equipping. Use Wear avatar to announce the content hash to peers.
Custom sits alongside All avatars and Favorites, separately from collections.

Preflight runs in WorkerThreadPool (with a synchronous fallback in non-threaded
web builds), before the existing texture-decoding/import pipeline. It requires
embedded binary buffers and PNG/JPEG images, rejects external URIs and unknown
extensions including Godot scene/script extensions, and checks graph and buffer
bounds. Current limits: 32 MiB/file, 32 files/256 MiB library, 100k triangles,
200k vertices including instances, 32 materials, 256 bones/skin, 128 morph targets
and 8 million vertex-target pairs, 4096 pixels per texture side and 32 megapixels
in total. Spring definitions are bounded too. These are resource limits, not a
security sandbox or a guarantee against importer bugs. Separate .gltf files,
external images, compressed geometry and Unity/FBX sources need conversion first.

Only successfully parsed models enter the persistent manifest. Failed imports
leave the previous preview/equipped avatar intact. Hashes deduplicate repeated
imports. Browser persistence uses Godot's user storage and is subject to browser
storage quotas/eviction. Native and browser device acceptance remains necessary.
Run `res://tests/avatar_custom_test.gd` and the picker suite to cover local
import, duplicate detection, persistence, filtering and content-hash announcements.


## Import profiling and UI hand overlays

The full home and session menus link to Debug. It shows threading/renderer/XR
capabilities, active downloads, selected/network avatar IDs, received peer IDs,
cache state, failures, a bounded 64-event history, stage CPU timings and peak
frame duration. Copy report exports the text; Reset clears timing history.
P2P diagnostics include receive/send byte counts, queued owners, validation,
completion, cancellation and timeout/rejection reasons. Mirror diagnostics show
actual reflection target sizes and per-eye visible-region UV crops.

Runtime normalization now transforms detached vertex and blend-shape arrays in
WorkerThreadPool. Mesh reads and GPU-facing surface creation remain on main, at
one surface per frame; already normalized meshes bypass rebuilding. Rig/rest
updates remain on main. GLTF parsing, scene generation and first-use GPU/shader
work can still hitch; the debug timings identify remaining expensive stages.
Synchronous import_bytes remains a test/tool path. Geometry regression tests
compare worker-normalized base and blend-shape arrays with that reference.

The native tracked hand uses the same joint poses as UI poke detection. When an
avatar's hands are active, the separate native mesh fades in per hand within
16 cm of visible UI, reaches full overlay strength at 2.5 cm and retreats over
about 125 ms. The overlay casts no shadow, draws over the offset avatar hand,
and uses only the local first-person layer. Tracking loss and hiding/rebinding
the panel clear proximity; without a humanoid avatar the normal opaque tracked
hand remains the fallback. Controller rays retain their existing feedback.


## P2P custom avatars

PlayerReplication owns a persistent AvatarTransfer child. Spawn snapshots and
selection changes announce owned custom SHA-256 IDs. Unknown hashes show Explorer
while fetching bytes directly from that peer, then pass the same resource-limit
preflight, SHA-256 verification and runtime importer before application. Already
verified content can be reused. A peer only serves its currently equipped owned
avatar, never arbitrary paths, public URLs or received avatars. Received entries
are not listed in the picker/favorites and cannot be worn as one's own.

The mesh negotiates a dedicated reliable high-level channel 2 (physical channel
4), alongside the existing pose/identity channels and voice channel 1. Transfer
uses 12 KiB chunks, a 192 KiB acknowledgement window and a four-packet global
per-frame send budget, round-robin across peers. SCTP buffered bytes are checked
before enqueueing more data. Two incoming transfers cap received payload memory
at 64 MiB; each asset is at most 32 MiB. Chunk order, owner, hash and request nonce
are checked. Avatar changes and disconnects cancel obsolete work; stalled
transfers report a 20-second idle or five-minute overall timeout.

Assembly and verification run in WorkerThreadPool. Successful received assets
use a separate 128 MiB disk cache under `user://avatars/received`, with no owned
library manifest entry. Imported scenes share the normal bounded scene cache.
Scene/GPU import calls can still hitch, including for remote arrivals. This is
transport and resource validation, not a sandbox against importer bugs. Protocol
checks run via `avatar_transfer_test.gd`; the multiplayer integration suite also
forces real fixture bytes through WebRTC channel 2 while testing voice and swaps.
All peers must use a build with the new channel/RPC layout.

Remote avatar nameplates show byte download progress followed by animated segments
while verifying/importing/equipping. Transfer requests are repeated while awaiting
an offer; transient failures retry three times with backoff. The send window is 48 KiB,
below Godot WebRTCJS's default 64 KiB receive queue, including RPC overhead.
Cumulative byte acknowledgements preserve the valid prefix; stalled sends resume
from it after five seconds, tolerating duplicate and out-of-order byte ranges.
Idle timeouts allow two minutes for throttled/background browser tabs, with a
fifteen-minute total lifetime. Saved avatar identity
is replayed when a remote player is created after its announcement. Diagnostics
include the owner's equipped ID, ownership and connected peers.

Quest Browser uploads are disabled only during immersive WebXR, with an
“Exit VR to upload” caption. Desktop browsers and native Android retain uploads
in rooms/immersive sessions. Local UI (panel, pointer, names and progress) uses
visual layer 17, excluded from all reflection passes. Nameplate and picker loading
bars use rounded pills: bytes fill the bar, preparation bounces a short segment.


## Capturing remaining render hitches

Open Debug, choose **Capture render hitches**, then close the debug panel and
reproduce one avatar selection/wear/mirror appearance. The capture stops after
30 seconds; reopen Debug and use Copy report. Reset clears both import and
render diagnostics. The panel itself redraws text, so keep it closed during the
measurement. Repeat with the same cached avatar to compare cold and warm draws.

The capture uses unclamped monotonic frame gaps, rendering submission wall time,
activity tags, bounded hitch history, per-viewport sampled CPU/GPU timings where
supported, and RenderingDevice pipeline deltas. Unfocused/resume gaps are ignored.
Zero/unavailable GPU values never mean that GPU cost is zero. Submission timing
is CPU wall time, not GPU completion; per-viewport timing is sampled once/second.

On web, opt-in reversible wrappers additionally time existing compile/link/status,
shader binding, uniform lookup, texture upload and buffer upload calls in the
browser's main WebGL context. They never inspect shader sources or upload data,
call `finish`, force compilation, or read pixels. Worker-owned contexts may not
be observed; zero calls there are inconclusive. Slow call timestamps share the
engine clock and can be correlated with frame gaps, not used as proof of cause.
Wrappers are removed when capture stops. No data is sent anywhere.

[Godot's pipeline compilation guide](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html)
explicitly excludes Compatibility/OpenGL ES/WebGL from ubershaders, pipeline
precompilation and shader baking. For those renderers, warming requires actually
drawing the relevant meshes/materials during loading. The picker already draws
the real model before Wear, but XR multiview, lighting/shadows, skinning and
viewport features can require other variants. Measure the outstanding variant
before adding more warm-up passes: an off-screen mono preview cannot guarantee
that an XR multiview variant is warm, and a synchronous GLES compile still stalls
if merely moved into a hidden viewport during gameplay.

Native RenderingDevice builds can use pipeline counters and precompilation.
Shader baking is enabled in the native export presets, but the documented baker
needs GPU access and does not run in the headless CI export path. Different MSAA
levels in preview/main/mirror viewports can also create variants on those APIs;
keep the reported configuration in mind when comparing renderers.

## Body-estimation follow-up

Native Meta OpenXR provides body skeleton data through the vendor plugin and
`XRBodyTracker`, including optional inferred lower-body joints. Leg estimates
are not independently measured leg trackers. That path needs extension settings,
manifest support, valid-joint gating, retargeting and hardware testing; it is not
wired to this avatar rig yet.

The [WebXR body-tracking draft](https://immersive-web.github.io/body-tracking/)
exposes `XRFrame.body` behind the optional `body-tracking` session feature. Godot's
current WebXR glue does not consume it. This project's existing WebXR JS patch
could bridge poses during the live XR frame, using the same reference space,
without a C++ fork. That bridge, consent flow, tracking-loss behavior and pose
replication still require implementation and Quest Browser validation. Debug
reports whether an `XRBodyTracker` currently exists and has data; standing
animations remain the fallback independently of either tracking API.
