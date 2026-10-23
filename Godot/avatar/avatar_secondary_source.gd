extends "res://addons/vrm/vrm_secondary.gd"
## Preserve imported spring definitions without constructing the add-on solver.
## AvatarSprings installs the native solver immediately after entering the tree.
func _ready() -> void:
	skel = get_node_or_null(skeleton) as Skeleton3D
	set_process(false)
	set_physics_process(false)
