extends CharacterBody3D
## Offline scene-review controller. Does not alter the platform's player scripts.

@export var speed := 3.5
var xr_active := false
var turn_ready := true
@onready var desktop_camera: Camera3D = $Camera3D
@onready var origin: XROrigin3D = $XROrigin3D
@onready var headset: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var left: XRController3D = $XROrigin3D/Left
@onready var right: XRController3D = $XROrigin3D/Right
@onready var spawn: Marker3D = get_node("../../World/SpawnPoint")


func _ready() -> void:
	var xr := XRServer.find_interface("OpenXR")
	if not "--desktop" in OS.get_cmdline_user_args() and xr != null:
		xr_active = xr.is_initialized() or xr.initialize()
	get_viewport().use_xr = xr_active
	desktop_camera.current = not xr_active
	headset.current = xr_active
	$HUD.visible = not xr_active
	if xr_active:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	global_transform = spawn.global_transform


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not xr_active and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * 0.002)
		desktop_camera.rotation.x = clampf(desktop_camera.rotation.x - event.relative.y * 0.002, -1.4, 1.4)


func _physics_process(delta: float) -> void:
	var movement := Input.get_vector("move_left", "move_right", "move_forward", "move_backwards")
	var view_basis := global_basis
	if xr_active:
		movement = left.get_vector2("primary")
		view_basis = headset.global_basis
		var turn := right.get_vector2("primary").x
		if absf(turn) < 0.25:
			turn_ready = true
		elif absf(turn) > 0.7 and turn_ready:
			# Snap about the physical headset, avoiding a room-scale orbit.
			var before := headset.global_position
			rotate_y(-signf(turn) * PI / 6.0)
			global_position += before - headset.global_position
			turn_ready = false
		movement.y = -movement.y
	var direction := view_basis * Vector3(movement.x, 0, movement.y)
	direction.y = 0
	direction = direction.limit_length()
	velocity.x = move_toward(velocity.x, direction.x * speed, delta * 14.0)
	velocity.z = move_toward(velocity.z, direction.z * speed, delta * 14.0)
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0
	move_and_slide()
