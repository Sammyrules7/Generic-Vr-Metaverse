extends XRNode3D
## The original humanoid hand mesh and native skinning, with neutral outline
## shading instead of skin textures or a procedural joint representation.
@export_enum("left", "right") var hand := "left"
var skeleton: Skeleton3D
var modifier: XRHandModifier3D
var tracking_valid := false
var _overlay_alpha := 0.0
var _materials: Array[ShaderMaterial] = []

func _ready() -> void:
	tracker = StringName("/user/hand_tracker/" + hand)
	pose = &"default"
	var side := "Left" if hand == "left" else "Right"
	var model := (load("res://player/hands/%sHandHumanoid.gltf" % side) as PackedScene).instantiate()
	add_child(model)
	PlatformXRInput.prepare_hand_model(model)
	AvatarView.use_first_person_layer(model)
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var material := HandOutline.material_for(mesh, skeleton, side)
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_materials.append(material)
	modifier = XRHandModifier3D.new()
	modifier.hand_tracker = tracker
	modifier.bone_update = XRHandModifier3D.BONE_UPDATE_FULL
	skeleton.add_child(modifier)
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE
	physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_OFF
	process_priority = -5
	hide()

func _process(delta: float) -> void:
	var avatar_active := bool(get_parent().get_meta("avatar_hands_active", false))
	var target := clampf(float(get_parent().get_meta("ui_hand_overlay_" + hand, 0.0)), 0, 1) if avatar_active else 0.0
	_overlay_alpha = move_toward(_overlay_alpha, target, maxf(delta, 0) * 8.0)
	tracking_valid = false
	if avatar_active and _overlay_alpha <= 0.001:
		hide()
		modifier.active = false
		return
	var hand_tracker := PlatformXRInput.hand_tracker(hand)
	var valid := PlatformXRInput.optical_hand(hand_tracker)
	if valid:
		for joint in XRHandTracker.HAND_JOINT_MAX:
			if not PlatformXRInput.joint_valid(hand_tracker, joint) or (hand_tracker.get_hand_joint_flags(joint) & XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID) == 0:
				valid = false
				break
	visible = valid
	tracking_valid = valid
	modifier.active = valid
	if valid:
		var palm := hand_tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM)
		palm.origin *= XRServer.world_scale
		transform = XRServer.get_reference_frame() * palm
		skeleton.scale = Vector3.ONE * XRServer.world_scale
		for material in _materials:
			HandOutline.set_appearance(material, _overlay_alpha if avatar_active else 1.0, avatar_active)
