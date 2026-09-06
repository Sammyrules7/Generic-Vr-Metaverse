extends PlayerControls

@export var camera_sensitivity := 1.75
var mouse_captured := false


func _ready() -> void:
	super._ready()
	head = $Camera
	$Camera.current = true
	_capture_mouse()


func _unhandled_input(event: InputEvent) -> void:
	# Let UI buttons consume clicks before we decide to recapture the mouse.
	if event is InputEventMouseMotion and mouse_captured:
		_look(event.relative * 0.001)
	if event.is_action_pressed("exit"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		mouse_captured = false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_capture_mouse()


func update(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_backwards")
	movement = body.transform.basis * Vector3(input.x, 0, input.y)
	jump_requested = Input.is_action_just_pressed("jump")
	_look(Input.get_vector("look_left", "look_right", "look_up", "look_down") * delta)


func _capture_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true


func _look(amount: Vector2) -> void:
	body.rotation.y -= amount.x * camera_sensitivity
	head.rotation.x = clampf(head.rotation.x - amount.y * camera_sensitivity, -1.5, 1.5)
