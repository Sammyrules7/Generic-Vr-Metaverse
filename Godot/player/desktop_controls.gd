extends PlayerControls

@export var mouse_sensitivity := 0.00175
@export var look_speed := 1.75
var mouse_captured := false


func _ready() -> void:
	super._ready()
	head = $Camera
	$Camera.current = true
	_capture_mouse()


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	mouse_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	# Let UI buttons consume clicks before we decide to recapture the mouse.
	if event is InputEventMouseMotion and mouse_captured:
		apply_look(event.relative * mouse_sensitivity)
	if event.is_action_pressed("exit"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		mouse_captured = false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_capture_mouse()


func update(delta: float) -> void:
	if not input_enabled:
		movement = Vector3.ZERO
		jump_requested = false
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_backwards")
	movement = planar_direction(input, body.global_basis)
	jump_requested = Input.is_action_just_pressed("jump")
	apply_look(Input.get_vector("look_left", "look_right", "look_up", "look_down") * look_speed * delta)


func _capture_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true


func apply_look(radians: Vector2) -> void:
	body.rotate_y(-radians.x)
	head.rotation.x = clampf(head.rotation.x - radians.y, -1.5, 1.5)


func _exit_tree() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
