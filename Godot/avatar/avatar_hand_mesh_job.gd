class_name AvatarHandMeshJob
extends RefCounted
## Only CPU-side ImporterMesh arrays and immutable skin/material references.
const VRM_UTILS := preload("res://addons/vrm/vrm_utils.gd")
var mesh: ImporterMesh
var skin: Skin
var hidden_bones := {}
var result: ImporterMesh
var task_id := -1

func run() -> void:
	result = VRM_UTILS._generate_hide_bone_mesh(mesh, skin, hidden_bones, [])
