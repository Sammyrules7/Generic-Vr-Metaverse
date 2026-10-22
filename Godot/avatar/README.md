# Runtime avatars

`AvatarService` owns shared downloads, SHA-256 verification, a bounded parsed-scene
cache, and a disk cache. Containers acquire a request and release it on a new
selection or scene exit. Releasing the last consumer cancels HTTP; worker jobs
are collected even when nobody still needs their result. Each player gets its
own scene, skeleton, modifiers, and simulation history.

The catalog is a pinned allowlist, not a URL supplied by another peer. It contains
three CC0 100Avatars R1 models by ToxSam from Open Source Avatars, and a bundled
Godette sample so selection, first-person rendering, and spring bones work
offline. Godette by SirRichard94, adapted to VRM by Lyuma, is CC-BY 3.0; attribution
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
optical hand visuals, removing overlapping hand-weighted avatar triangles.

The Avatar submenu is available from the home and in-game menus. Spring bones
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
