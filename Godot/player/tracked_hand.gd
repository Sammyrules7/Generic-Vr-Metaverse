extends XRNode3D
## Native Godot hand tracking with a humanoid-rigged mesh. The engine owns
## joint poses, parent relationships, and skin updates; no axis offsets here.

@export_enum("left", "right") var hand := "left"
var skeleton: Skeleton3D
var modifier: XRHandModifier3D


func _ready() -> void:
	tracker = StringName("/user/hand_tracker/" + hand)
	pose = &"default"
	var side := "Left" if hand == "left" else "Right"
	var model := (load("res://player/hands/%sHandHumanoid.gltf" % side) as PackedScene).instantiate()
	PlatformXRInput.prepare_hand_model(model)
	add_child(model)
	AvatarView.use_first_person_layer(model)
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	modifier = XRHandModifier3D.new()
	modifier.hand_tracker = tracker
	modifier.bone_update = XRHandModifier3D.BONE_UPDATE_FULL
	skeleton.add_child(modifier)
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE
	process_priority = -5
	hide()


func _process(_delta: float) -> void:
	if bool(get_parent().get_meta("avatar_hands_active", false)):
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
	if valid:
		# Refresh the anchor from the same joint snapshot as the modifier. After
		# tracking loss, joint data can recover before a new default-pose signal.
		var palm := hand_tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM)
		palm.origin *= XRServer.world_scale
		transform = XRServer.get_reference_frame() * palm
		skeleton.scale = Vector3.ONE * XRServer.world_scale
