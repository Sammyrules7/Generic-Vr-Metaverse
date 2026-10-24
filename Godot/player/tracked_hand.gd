extends XRNode3D
## Native Godot hand tracking with a humanoid-rigged mesh. The engine owns
## joint poses, parent relationships, and skin updates; no axis offsets here.

@export_enum("left", "right") var hand := "left"
var skeleton: Skeleton3D
var modifier: XRHandModifier3D
var _overlay_alpha := 0.0
var _overlay_mode := false
var _surfaces: Array[Dictionary] = []


func _ready() -> void:
	tracker = StringName("/user/hand_tracker/" + hand)
	pose = &"default"
	var side := "Left" if hand == "left" else "Right"
	var model := (load("res://player/hands/%sHandHumanoid.gltf" % side) as PackedScene).instantiate()
	PlatformXRInput.prepare_hand_model(model)
	add_child(model)
	AvatarView.use_first_person_layer(model)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var original := mesh.get_active_material(surface)
			var fade := original.duplicate() as BaseMaterial3D if original is BaseMaterial3D else StandardMaterial3D.new()
			fade.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			fade.no_depth_test = true
			fade.render_priority = 1
			_surfaces.append({"mesh": mesh, "surface": surface, "original": original, "fade": fade, "color": fade.albedo_color, "shadow": mesh.cast_shadow})
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	modifier = XRHandModifier3D.new()
	modifier.hand_tracker = tracker
	modifier.bone_update = XRHandModifier3D.BONE_UPDATE_FULL
	skeleton.add_child(modifier)
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE
	process_priority = -5
	hide()


func _process(_delta: float) -> void:
	var avatar_active := bool(get_parent().get_meta("avatar_hands_active", false))
	var target := clampf(float(get_parent().get_meta("ui_hand_overlay_" + hand, 0.0)), 0, 1) if avatar_active else 0.0
	_overlay_alpha = move_toward(_overlay_alpha, target, maxf(_delta, 0) * 8.0)
	_set_overlay_mode(avatar_active)
	if avatar_active and _overlay_alpha <= 0.001:
		hide()
		modifier.active = false
		return
	# Validity must react within one frame: tests and gameplay drive flag
	# changes and call _process directly. The single cached tracker lookup
	# above keeps this cheap; the joint scan early-outs on first invalid.
	var hand_tracker := PlatformXRInput.hand_tracker(hand)
	var valid := PlatformXRInput.optical_hand(hand_tracker)
	# A full native update needs all orientations. Hold the mesh hidden during
	# partial tracking rather than handing invalid transforms to the modifier.
	if valid:
		for joint in XRHandTracker.HAND_JOINT_MAX:
			if not PlatformXRInput.joint_valid(hand_tracker, joint) or (hand_tracker.get_hand_joint_flags(joint) & XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID) == 0:
				valid = false
				break
	visible = valid
	modifier.active = valid
	if avatar_active:
		for surface in _surfaces:
			var color: Color = surface.color
			color.a *= _overlay_alpha * 0.85
			(surface.fade as BaseMaterial3D).albedo_color = color
	if valid:
		# Refresh the anchor from the same joint snapshot as the modifier. After
		# tracking loss, joint data can recover before a new default-pose signal.
		var palm := hand_tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM)
		palm.origin *= XRServer.world_scale
		transform = XRServer.get_reference_frame() * palm
		skeleton.scale = Vector3.ONE * XRServer.world_scale


func _set_overlay_mode(active: bool) -> void:
	if active == _overlay_mode:
		return
	_overlay_mode = active
	for surface in _surfaces:
		(surface.mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if active else surface.shadow
		(surface.mesh as MeshInstance3D).set_surface_override_material(surface.surface, surface.fade if active else surface.original)
