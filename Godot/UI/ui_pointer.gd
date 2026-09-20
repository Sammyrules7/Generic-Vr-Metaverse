extends XRToolsFunctionPointer

func _process(delta: float) -> void:
	# Refresh after locomotion and the hand menu's smoothing, so the beam and
	# its hit point use this rendered frame's rig transform (including jumps).
	$RayCast.force_raycast_update()
	if enabled and $RayCast.is_colliding():
		var surface: Node = $RayCast.get_collider().get_parent()
		if surface.has_method("contains_ui_point") and not surface.contains_ui_point($RayCast.get_collision_point()):
			enabled = false
	super._process(delta)
