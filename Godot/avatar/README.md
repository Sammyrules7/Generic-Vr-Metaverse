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

HTTP is asynchronous. Pure file verification and caching use WorkerThreadPool;
scene generation stays on the main thread, at most one avatar import per frame.
There is a synchronous verification fallback for non-threaded web exports.
This does not promise hitch-free imports: GPU upload and shader compilation need
measurement on each target renderer.

Standing eye height is baked into mesh/blend-shape positions, skeleton rest
translations, inverse skin binds, eye offsets, and collider data. Runtime
Skeleton3D and simulator node scales remain one, as required by the native
spring solver. Camera alignment uses the imported eye offset rather than the
head-bone origin. Legs retain their rest pose; locomotion clips, foot planting,
and full-body tracking are not implemented.

`PlayerReplication` reliably announces catalog IDs in spawn snapshots and on
selection changes. Body/head/hand poses retain their existing unreliable update
channel. The scene-owned container keeps `Head`, `LeftHand`, and `RightHand`
anchors stable for voice and input, replaces only model visuals, and consumes
local tracking every display frame. Local VR keeps the existing controller and
optical hand visuals, removing overlapping hand-weighted avatar triangles from
the first-person mesh only. The full mesh retains its hands for mirrors.

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


Texture decoding and first-person hand-mesh filtering run as CPU-only worker
jobs in threaded builds. Runtime GLTF parsing, scene generation, normalization,
mesh upload and packing stay on main but are separated by frame boundaries.
Normalization transforms packed vertex arrays in native code. Handless geometry
is prepared once and stored in the shared PackedScene, so wearing a previewed
avatar reuses it. Single-threaded web exports use the same staged pipeline with
CPU fallbacks. Godot's indivisible GLTF calls and first-use GPU/shader work can
still cause a hitch for large avatars; this is not a fully asynchronous importer.
