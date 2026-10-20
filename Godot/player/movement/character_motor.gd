class_name CharacterMotor
extends Node
## The only owner of locomotion velocity. Collision response feeds the next tick.

@export var speed: float = 5.0
@export var acceleration: float = 30.0
@export var deceleration: float = 40.0
@export var jump_height: float = 1.0
@export var input_source: MovementInput

@onready var body: CharacterBody3D = get_parent() as CharacterBody3D
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

func _physics_process(delta: float) -> void:
	input_source.sample(delta)
	step(delta, input_source.move_direction, input_source.consume_jump())

func step(delta: float, direction: Vector3, jump: bool) -> void:
	var target := Vector3(direction.x, 0.0, direction.z).limit_length(1.0) * speed
	var horizontal := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var rate := deceleration if target.is_zero_approx() else acceleration
	horizontal = horizontal.move_toward(target, rate * delta)
	body.velocity.x = horizontal.x
	body.velocity.z = horizontal.z
	if body.is_on_floor():
		body.velocity.y = sqrt(2.0 * gravity * jump_height) if jump else 0.0
	else:
		body.velocity.y -= gravity * delta
	body.move_and_slide()
