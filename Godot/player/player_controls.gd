class_name PlayerControls
extends Node3D

var body: CharacterBody3D
# World-space desired movement, including stick magnitude. NetworkPlayer applies
# speed, acceleration, gravity, and jumping identically for both input modes.
var input_enabled := true
var movement := Vector3.ZERO
var jump_requested := false
var head: Node3D
var left_hand: Node3D
var right_hand: Node3D


func _ready() -> void:
	body = get_parent() as CharacterBody3D


func update(_delta: float) -> void:
	pass


func consume_jump() -> bool:
	# A VR button signal can arrive between physics ticks; consume it exactly once.
	var requested := jump_requested
	jump_requested = false
	return requested


func pose(node: Node3D) -> Transform3D:
	if node == null:
		return Transform3D.IDENTITY
	return body.global_transform.affine_inverse() * node.global_transform
