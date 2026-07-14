extends CharacterBody3D

@onready var desktop_camera: Camera3D = $Camera
@onready var vr_camera: XRCamera3D = $Origin/HMDView
@onready var xr_origin: Node3D = $Origin

# --- VR CONTROLLER ASSIGNMENTS ---
# Assign these to your LeftHand and RightHand nodes in the inspector
@export var left_controller: XRController3D
@export var right_controller: XRController3D

var xr_interface: XRInterface
var vr: bool

func _ready():
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		print("OpenXR initialized successfully")
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
		vr_camera.make_current()
		vr = true

		# Connect the controller button signals for event-driven jumping
		if right_controller:
			right_controller.button_pressed.connect(_on_vr_button_pressed)
	else:
		print("OpenXR not initialized, please check if your headset is connected. Starting in desktop mode")
		xr_origin.visible = false
		get_viewport().use_xr = false
		desktop_camera.make_current()
		vr = false

# Player movement
@export_range(1, 35, 1) var speed: float = 10 # m/s
@export_range(10, 400, 1) var acceleration: float = 100 # m/s^2

@export_range(0.1, 3.0, 0.1) var jump_height: float = 1 # m
@export_range(0.1, 3.0, 0.1, "or_greater") var camera_sens: float = 1.75

var jumping: bool = false
var mouse_captured: bool = false

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var move_dir: Vector2 # Input direction for movement
var look_dir: Vector2 # Input direction for look/aim

var walk_vel: Vector3 # Walking velocity
var grav_vel: Vector3 # Gravity velocity
var jump_vel: Vector3 # Jumping velocity


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		look_dir = event.relative * 0.001
		if mouse_captured: _rotate_camera()
	if Input.is_action_just_pressed(&"exit"): get_tree().quit()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and not vr and not mouse_captured:
			capture_mouse()

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed(&"jump"):
		jumping = true

	if vr:
		_handle_vr_rotation(delta)
	elif mouse_captured:
		_handle_joypad_camera_rotation(delta)

	velocity = _walk(delta) + _gravity(delta) + _jump(delta)
	move_and_slide()

func capture_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true

func release_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	mouse_captured = false


# --- ROTATION LOGIC ---

func _rotate_camera(sens_mod: float = 1.0) -> void:
	if vr: return
	desktop_camera.rotation.y -= look_dir.x * camera_sens * sens_mod
	desktop_camera.rotation.x = clamp(desktop_camera.rotation.x - look_dir.y * camera_sens * sens_mod, -1.5, 1.5)

func _handle_joypad_camera_rotation(delta: float, sens_mod: float = 1.0) -> void:
	if vr: return
	var joypad_dir: Vector2 = Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if joypad_dir.length() > 0:
		look_dir += joypad_dir * delta
		_rotate_camera(sens_mod)
		look_dir = Vector2.ZERO

func _handle_vr_rotation(delta: float) -> void:
	if not right_controller or not right_controller.get_is_active():
		return

	# "primary" on the right controller maps to the right joystick
	var vr_look: Vector2 = right_controller.get_vector2("primary")

	# Apply a quick deadzone check
	if abs(vr_look.x) > 0.1:
		# Multiplied by a scale factor of 1.5 for a smooth, comfortable turn rate
		var rotation_speed: float = -vr_look.x * camera_sens * delta * 1.5
		_rotate_origin_around_hmd(rotation_speed)

func _rotate_origin_around_hmd(angle: float) -> void:
	# Keep the offset calculations locked to the horizontal plane to prevent neck twisting
	var hmd_pos: Vector3 = vr_camera.position
	hmd_pos.y = 0.0

	# Matrix transform magic to rotate the origin relative to where your head is
	var t1 := Transform3D(Basis(), -hmd_pos)
	var r := Transform3D(Basis().rotated(Vector3.UP, angle), Vector3.ZERO)
	var t2 := Transform3D(Basis(), hmd_pos)

	xr_origin.transform = xr_origin.transform * t2 * r * t1


# --- MOVEMENT & PHYSICS LOGIC ---

func _walk(delta: float) -> Vector3:
	var active_camera: Camera3D = vr_camera if vr else desktop_camera

	# Get input vector dynamically based on active platform
	if vr and left_controller and left_controller.get_is_active():
		move_dir = left_controller.get_vector2("primary")
	else:
		move_dir = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_backwards")

	var _forward: Vector3 = active_camera.global_transform.basis * Vector3(move_dir.x, 0, move_dir.y)
	var walk_dir: Vector3 = Vector3(_forward.x, 0, _forward.z).normalized()
	walk_vel = walk_vel.move_toward(walk_dir * speed * move_dir.length(), acceleration * delta)
	return walk_vel

func _gravity(delta: float) -> Vector3:
	grav_vel = Vector3.ZERO if is_on_floor() else grav_vel.move_toward(Vector3(0, velocity.y - gravity, 0), gravity * delta)
	return grav_vel

func _jump(delta: float) -> Vector3:
	if jumping:
		if is_on_floor():
			jump_vel = Vector3(0, sqrt(4 * jump_height * gravity), 0)
		jumping = false
		return jump_vel
	jump_vel = Vector3.ZERO if is_on_floor() or is_on_ceiling_only() else jump_vel.move_toward(Vector3.ZERO, gravity * delta)
	return jump_vel


# --- VR EVENT HANDLERS ---

func _on_vr_button_pressed(button_name: String) -> void:
	# "ax_button" refers to the 'A' button on the Quest right controller
	if button_name == "ax_button":
		jumping = true
