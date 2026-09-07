class_name MovementInput
extends Node3D
## Device adapters produce a world-space wish velocity direction and one-shot jump.

var move_direction := Vector3.ZERO
var jump_requested := false

func sample(_delta: float) -> void:
	move_direction = Vector3.ZERO

func consume_jump() -> bool:
	var requested := jump_requested
	jump_requested = false
	return requested

static func planar_direction(input: Vector2, heading: Basis) -> Vector3:
	# Derive forward from right, so looking vertically never collapses movement.
	var right := Vector3(heading.x.x, 0.0, heading.x.z).normalized()
	var back := right.cross(Vector3.UP)
	return (right * input.x + back * input.y).limit_length(1.0)
