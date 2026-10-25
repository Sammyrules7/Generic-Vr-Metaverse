extends XRNode3D
## Neutral optical-hand shell. Joint positions drive the geometry directly, so
## skin bind axes cannot turn palms/fingers inside out on different runtimes.
@export_enum("left", "right") var hand := "left"
var visual: NeutralHandVisual
var tracking_valid := false
var _overlay_alpha := 0.0

func _ready() -> void:
	tracker = StringName("/user/hand_tracker/" + hand)
	pose = &"default"
	visual = NeutralHandVisual.new()
	add_child(visual)
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
		return
	var hand_tracker := PlatformXRInput.hand_tracker(hand)
	var valid := PlatformXRInput.optical_hand(hand_tracker)
	if valid:
		for joint in XRHandTracker.HAND_JOINT_MAX:
			if not PlatformXRInput.joint_valid(hand_tracker, joint) or not hand_tracker.get_hand_joint_transform(joint).origin.is_finite():
				valid = false
				break
	visible = valid
	tracking_valid = valid
	if valid:
		# Only the root frame uses orientation; the complete visual is derived
		# from positions. An identity root also supports position-only trackers.
		var palm := hand_tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM)
		palm.basis = Basis.IDENTITY
		visual.update_joints(hand_tracker, palm)
		palm.origin *= XRServer.world_scale
		transform = XRServer.get_reference_frame() * palm
		visual.scale = Vector3.ONE * XRServer.world_scale
		visual.set_appearance(_overlay_alpha if avatar_active else 1.0, avatar_active)
