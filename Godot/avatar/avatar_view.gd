class_name AvatarView
extends RefCounted
## Reserve visual layers 19/20 for the local first-person body and full avatar.
## Mirrors see the full avatar; player cameras never draw that layer.
const LOCAL_UI := 1 << 16
const MIRROR_SURFACE := 1 << 17
const FIRST_PERSON := 1 << 18
const FULL_BODY := 1 << 19


static func configure_player_camera(camera: Camera3D, vr: bool) -> void:
	camera.cull_mask = (camera.cull_mask | MIRROR_SURFACE | LOCAL_UI) & ~(FIRST_PERSON | FULL_BODY)
	if vr:
		camera.cull_mask |= FIRST_PERSON


static func configure_mirror_camera(camera: Camera3D) -> void:
	camera.cull_mask = (camera.cull_mask | FULL_BODY) & ~(FIRST_PERSON | MIRROR_SURFACE | LOCAL_UI)


static func use_first_person_layer(root: Node3D) -> void:
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		mesh.layers = FIRST_PERSON
