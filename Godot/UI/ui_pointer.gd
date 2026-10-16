extends XRToolsFunctionPointer


func _process(delta: float) -> void:
	# RayCast3D already updates every physics frame; forcing a second query
	# every render frame doubled physics cost per pointer. Rely on the physics
	# update and only gate off-screen hits here.
	if enabled and $RayCast.is_colliding():
		var surface: Node = $RayCast.get_collider().get_parent()
		if surface.has_method("contains_ui_point") and not surface.contains_ui_point($RayCast.get_collision_point()):
			enabled = false
	super._process(delta)
