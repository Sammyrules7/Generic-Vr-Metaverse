extends CharacterBody3D

# ===============================
# README!!!!!!!!
# This is like all vibe coded
# I mean "agentic engineered"
# I will rewrite it at some point
# I recomend not touching it.
# ===============================

@onready var camera: Camera3D = $Camera

@export var speed: float = 10.0
@export var acceleration: float = 100.0
@export var jump_height: float = 1.0
@export var camera_sens: float = 1.75

var jumping: bool = false
var mouse_captured: bool = false
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var move_dir: Vector2
var look_dir: Vector2

var walk_vel: Vector3
var grav_vel: Vector3
var jump_vel: Vector3

func _ready() -> void:
	capture_mouse()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mouse_captured:
		look_dir = event.relative * 0.001
		_rotate_camera()

	if Input.is_action_just_pressed(&"exit"):
		get_tree().quit()

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and not mouse_captured:
			capture_mouse()

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed(&"jump"):
		jumping = true

	_handle_joypad_camera_rotation(delta)

	velocity = _walk(delta) + _gravity(delta) + _jump(delta)
	move_and_slide()

func capture_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true

func _rotate_camera(sens_mod: float = 1.0) -> void:
	rotation.y -= look_dir.x * camera_sens * sens_mod
	camera.rotation.x = clamp(camera.rotation.x - look_dir.y * camera_sens * sens_mod, -1.5, 1.5)

func _handle_joypad_camera_rotation(delta: float, sens_mod: float = 1.0) -> void:
	var joypad_dir = Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if joypad_dir.length() > 0:
		look_dir += joypad_dir * delta
		_rotate_camera(sens_mod)
		look_dir = Vector2.ZERO

func _walk(delta: float) -> Vector3:
	move_dir = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_backwards")
	var forward = transform.basis * Vector3(move_dir.x, 0, move_dir.y)
	var walk_dir = forward.normalized()
	walk_vel = walk_vel.move_toward(walk_dir * speed * move_dir.length(), acceleration * delta)
	return walk_vel

func _gravity(delta: float) -> Vector3:
	if is_on_floor():
		grav_vel = Vector3.ZERO
	else:
		grav_vel = grav_vel.move_toward(Vector3(0, velocity.y - gravity, 0), gravity * delta)
	return grav_vel

func _jump(delta: float) -> Vector3:
	if jumping:
		if is_on_floor():
			jump_vel = Vector3(0, sqrt(2 * jump_height * gravity), 0)
		jumping = false
		return jump_vel

	if is_on_floor() or is_on_ceiling_only():
		jump_vel = Vector3.ZERO
	else:
		jump_vel = jump_vel.move_toward(Vector3.ZERO, gravity * delta)
	return jump_vel
