extends CharacterBody3D

@onready var vr_camera: XRCamera3D = $Origin/HMDView
@onready var xr_origin: Node3D = $Origin

@export var left_controller: XRController3D
@export var right_controller: XRController3D

@export var speed: float = 10.0
@export var acceleration: float = 100.0
@export var jump_height: float = 1.0
@export var camera_sens: float = 1.75

var jumping: bool = false
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var walk_vel: Vector3
var grav_vel: Vector3
var jump_vel: Vector3

func _ready() -> void:
	var xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
		if right_controller:
			right_controller.button_pressed.connect(_on_vr_button_pressed)

func _physics_process(delta: float) -> void:
	_handle_vr_rotation(delta)
	velocity = _walk(delta) + _gravity(delta) + _jump(delta)
	move_and_slide()

func _handle_vr_rotation(delta: float) -> void:
	if not right_controller or not right_controller.get_is_active():
		return

	var vr_look = right_controller.get_vector2("primary")
	if abs(vr_look.x) > 0.1:
		var rotation_speed = -vr_look.x * camera_sens * delta * 1.5
		_rotate_origin_around_hmd(rotation_speed)

func _rotate_origin_around_hmd(angle: float) -> void:
	var hmd_pos = vr_camera.position
	hmd_pos.y = 0.0

	var t1 := Transform3D(Basis(), -hmd_pos)
	var r := Transform3D(Basis().rotated(Vector3.UP, angle), Vector3.ZERO)
	var t2 := Transform3D(Basis(), hmd_pos)

	xr_origin.transform = xr_origin.transform * t2 * r * t1

func _walk(delta: float) -> Vector3:
	var move_dir = Vector2.ZERO
	if left_controller and left_controller.get_is_active():
		move_dir = left_controller.get_vector2("primary")

	var forward = vr_camera.global_transform.basis * Vector3(move_dir.x, 0, move_dir.y)
	var walk_dir = Vector3(forward.x, 0, forward.z).normalized()

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

func _on_vr_button_pressed(button_name: String) -> void:
	if button_name == "ax_button":
		jumping = true
