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
	add_child(model)
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	modifier = XRHandModifier3D.new()
	modifier.hand_tracker = tracker
	modifier.bone_update = XRHandModifier3D.BONE_UPDATE_FULL
	skeleton.add_child(modifier)
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE
	process_priority = -5
	hide()


func _process(_delta: float) -> void:
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
		skeleton.scale = Vector3.ONE * XRServer.world_scale
