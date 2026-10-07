extends PlayerControls

@export var rotation_speed := 2.625
@export_range(0.0, 0.9) var deadzone := 0.2
@export var pinch_threshold := 0.02
@export var release_threshold := 0.035
@export var pinch_release_delay := 0.08

var pinching := false
var pinch_release_time := 0.0
var pinch_release_samples := 0
var pinch_hand := ""


func _ready() -> void:
	super._ready()
	head = $Origin/HMDView
	left_hand = $Origin/LeftHand
	right_hand = $Origin/RightHand
	get_viewport().use_xr = true
	$Origin/HMDView.current = true
	$Origin/RightHand.button_pressed.connect(_button_pressed)
	# XR Tools renders hand meshes as top-level nodes. Update them after the
	# character motor so they include this tick's locomotion transform.
	for path: NodePath in [^"Origin/LeftHand/LeftHand", ^"Origin/RightHand/RightHand"]:
		var hand_mesh := get_node_or_null(path)
		if hand_mesh != null:
			hand_mesh.process_physics_priority = 1


func update(delta: float) -> void:
	if not input_enabled:
		movement = Vector3.ZERO
		jump_requested = false
		pinching = false
		pinch_release_time = 0.0
		pinch_release_samples = 0
		pinch_hand = ""
		return
	sync_room_scale()
	var look := PlatformXRInput.stick($Origin/RightHand)
	rotate_around_head(-filtered_stick(Vector2(look.x, 0.0)).x * rotation_speed * delta)
	var input := PlatformXRInput.stick($Origin/LeftHand)
	var hand := _hand_pinch()
	movement = planar_direction(select_movement(input, hand.x > 0.5, hand.y, delta), head.global_basis)


func _button_pressed(button: String) -> void:
	if input_enabled and button == "ax_button":
		jump_requested = true


func filtered_stick(value: Vector2) -> Vector2:
	var strength := minf(value.length(), 1.0)
	if strength <= deadzone:
		return Vector2.ZERO
	return value.normalized() * (strength - deadzone) / (1.0 - deadzone)


func select_movement(stick: Vector2, hand_valid: bool, pinch_distance: float, delta: float = 1.0 / 60.0) -> Vector2:
	var filtered := filtered_stick(stick)
	if not filtered.is_zero_approx():
		pinching = false
		pinch_release_time = 0.0
		pinch_release_samples = 0
		pinch_hand = ""
		# OpenXR stick up is positive Y; shared movement forward is negative Y.
		return Vector2(filtered.x, -filtered.y)
	# Keep the sustained pinch while filtering brief separation/tracking gaps.
	# Invalid data can retain an existing pinch briefly, never start it.
	if hand_valid and pinch_distance < pinch_threshold:
		pinching = true
		pinch_release_time = 0.0
		pinch_release_samples = 0
	elif pinching and (not hand_valid or pinch_distance > release_threshold):
		pinch_release_time += delta
		pinch_release_samples += 1
		if pinch_release_samples >= 2 and pinch_release_time >= pinch_release_delay:
			pinching = false
			pinch_hand = ""
	else:
		pinch_release_time = 0.0
		pinch_release_samples = 0
	return Vector2.UP if pinching else Vector2.ZERO


func _hand_pinch() -> Vector2:
	var thumb_joint := XRHandTracker.HAND_JOINT_THUMB_TIP
	var middle_joint := XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP
	var valid_flag := XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID
	var closest := INF
	var closest_hand := ""
	for hand: String in ["left", "right"]:
		# An idle second hand in the hysteresis band must not keep the first
		# hand's released gesture moving the player.
		if pinching and not pinch_hand.is_empty() and hand != pinch_hand:
			continue
		var tracker := PlatformXRInput.hand_tracker(hand)
		if not PlatformXRInput.optical_hand(tracker):
			continue
		if (tracker.get_hand_joint_flags(thumb_joint) & valid_flag) == 0 or (tracker.get_hand_joint_flags(middle_joint) & valid_flag) == 0:
			continue
		var thumb := tracker.get_hand_joint_transform(thumb_joint).origin
		var middle := tracker.get_hand_joint_transform(middle_joint).origin
		var distance := thumb.distance_to(middle)
		if distance < closest:
			closest = distance
			closest_hand = hand
	if not pinching:
		pinch_hand = closest_hand if closest < pinch_threshold else ""
	return Vector2(1.0, closest) if closest < INF else Vector2.ZERO


func rotate_around_head(angle: float) -> void:
	var origin := $Origin as XROrigin3D
	var pivot := head.global_position
	origin.global_transform = Transform3D(Basis(Vector3.UP, angle), pivot) * Transform3D(Basis.IDENTITY, -pivot) * origin.global_transform


func sync_room_scale() -> void:
	# Put the collision body beneath the tracked head and counter-translate the
	# origin. Collision blocking therefore corrects the virtual head position.
	var offset := head.global_position - body.global_position
	offset.y = 0.0
	if offset.length_squared() < 0.000001:
		return
	body.move_and_collide(offset)
	$Origin.global_position -= offset
