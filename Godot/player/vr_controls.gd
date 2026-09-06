extends PlayerControls

@export var rotation_speed := 2.625
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


func _exit_tree() -> void:
	# The rig is scene-owned; returning to the lobby must restore ordinary rendering.
	get_viewport().use_xr = false


func update(delta: float) -> void:
	var look: Vector2 = $Origin/RightHand.get_vector2("primary")
	if $Origin/RightHand.get_is_active() and absf(look.x) > 0.1:
		# Turn around the user's tracked position, not the room origin, so moving
		# away from the origin doesn't make turning swing the camera in an arc.
		var pivot := Vector3(head.position.x, 0, head.position.z)
		var turn := Transform3D(Basis(Vector3.UP, -look.x * rotation_speed * delta), Vector3.ZERO)
		$Origin.transform *= Transform3D(Basis.IDENTITY, pivot) * turn * Transform3D(Basis.IDENTITY, -pivot)
	var input: Vector2 = $Origin/LeftHand.get_vector2("primary") if $Origin/LeftHand.get_is_active() else Vector2.ZERO
	if input.length_squared() > 0.04:
		pinching = false
	else:
		_update_pinch()
		input = Vector2(0, -1) if pinching else Vector2.ZERO
	var direction := head.global_basis * Vector3(input.x, 0, input.y)
	direction.y = 0
	movement = direction.normalized() * input.length()


func _button_pressed(button: String) -> void:
	if button == "ax_button":
		jump_requested = true


func _update_pinch() -> void:
	if tracker == null:
		tracker = XRServer.get_tracker("/user/hand_tracker/left") as XRHandTracker
	if tracker == null or not tracker.has_tracking_data:
		pinching = false
		return
	var thumb := tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_THUMB_TIP).origin
	var index := tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP).origin
	var distance := thumb.distance_to(index)
	# Separate press/release thresholds stop tracking noise toggling movement.
	if not pinching and distance < pinch_threshold:
		pinching = true
	elif pinching and distance > release_threshold:
		pinching = false
