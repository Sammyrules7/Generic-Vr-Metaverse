class_name PlayerControls
extends MovementInput

var body: CharacterBody3D
# World-space desired movement, including stick magnitude. NetworkPlayer applies
# speed, acceleration, gravity, and jumping identically for both input modes.
var input_enabled := true
var movement := Vector3.ZERO
var head: Node3D
var left_hand: Node3D
var right_hand: Node3D


func _ready() -> void:
	body = get_parent() as CharacterBody3D


func update(_delta: float) -> void:
	pass


func sample(delta: float) -> void:
	update(delta)
	move_direction = movement if input_enabled else Vector3.ZERO


func pose(node: Node3D) -> Transform3D:
	if node == null:
		return Transform3D.IDENTITY
	return body.global_transform.affine_inverse() * node.global_transform


func hand_pose(side: String) -> Transform3D:
	var origin := get_node_or_null("Origin") as XROrigin3D
	var tracker := PlatformXRInput.hand_tracker(side)
	if origin != null and PlatformXRInput.optical_hand(tracker) and PlatformXRInput.joint_valid(tracker, XRHandTracker.HAND_JOINT_WRIST):
		return body.global_transform.affine_inverse() * PlatformXRInput.joint_world(origin, tracker, XRHandTracker.HAND_JOINT_WRIST)
	return pose(left_hand if side == "left" else right_hand)
