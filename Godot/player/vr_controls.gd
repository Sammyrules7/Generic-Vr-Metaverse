extends PlayerControls

@export var rotation_speed := 2.625
@export_range(0.0, 0.9) var deadzone := 0.2
@export var pinch_threshold := 0.02
@export var release_threshold := 0.035

var tracker: XRHandTracker
var pinching := false


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
	$Origin/LeftHand/LeftHand.process_physics_priority = 1
	$Origin/RightHand/RightHand.process_physics_priority = 1


func update(delta: float) -> void:
	if not input_enabled:
		movement = Vector3.ZERO
		jump_requested = false
		pinching = false
		return
	sync_room_scale()
	var look: Vector2 = $Origin/RightHand.get_vector2("primary") if $Origin/RightHand.get_is_active() else Vector2.ZERO
	rotate_around_head(-filtered_stick(Vector2(look.x, 0.0)).x * rotation_speed * delta)
	var input: Vector2 = $Origin/LeftHand.get_vector2("primary") if $Origin/LeftHand.get_is_active() else Vector2.ZERO
	var hand := _hand_pinch()
	movement = planar_direction(select_movement(input, hand.x > 0.5, hand.y), head.global_basis)


func _button_pressed(button: String) -> void:
	if input_enabled and button == "ax_button":
		jump_requested = true


func filtered_stick(value: Vector2) -> Vector2:
	var strength := minf(value.length(), 1.0)
	if strength <= deadzone:
		return Vector2.ZERO
	return value.normalized() * (strength - deadzone) / (1.0 - deadzone)


func select_movement(stick: Vector2, hand_valid: bool, pinch_distance: float) -> Vector2:
	var filtered := filtered_stick(stick)
	if not filtered.is_zero_approx():
		pinching = false
		# OpenXR stick up is positive Y; shared movement forward is negative Y.
		return Vector2(filtered.x, -filtered.y)
	if not hand_valid:
		pinching = false
	elif pinch_distance < pinch_threshold:
		pinching = true
	elif pinch_distance > release_threshold:
		pinching = false
	return Vector2.UP if pinching else Vector2.ZERO


func _hand_pinch() -> Vector2:
	if tracker == null:
		tracker = XRServer.get_tracker("/user/hand_tracker/left") as XRHandTracker
	if tracker == null or not tracker.has_tracking_data:
		return Vector2.ZERO
	var thumb_joint := XRHandTracker.HAND_JOINT_THUMB_TIP
	var index_joint := XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP
	var valid_flag := XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID
	if (tracker.get_hand_joint_flags(thumb_joint) & valid_flag) == 0 or (tracker.get_hand_joint_flags(index_joint) & valid_flag) == 0:
		return Vector2.ZERO
	var thumb := tracker.get_hand_joint_transform(thumb_joint).origin
	var index := tracker.get_hand_joint_transform(index_joint).origin
	return Vector2(1.0, thumb.distance_to(index))


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
