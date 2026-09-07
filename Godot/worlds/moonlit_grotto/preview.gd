extends Node3D
## Offline inspection uses a separate controller, without multiplayer RPCs.
var player: CharacterBody3D
var camera: Camera3D
var captured := false

func _ready() -> void:
	player = CharacterBody3D.new()
	player.name = "Explorer"
	$Players.add_child(player)
	var shape := CapsuleShape3D.new()
	shape.radius = .3
	shape.height = 1.7
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = .85
	player.add_child(collider)
	camera = Camera3D.new()
	camera.position.y = 1.65
	camera.fov = 72
	player.add_child(camera)
	camera.current = true
	_reset()
	var hud := CanvasLayer.new()
	add_child(hud)
	var title := Label.new()
	title.text = "M O O N L I T   G R O T T O"
	title.position = Vector2(30,25)
	title.add_theme_font_size_override("font_size",21)
	title.modulate = Color(.72,.88,.94,.85)
	hud.add_child(title)
	var hint := Label.new()
	hint.text = "Click to explore  ·  WASD move  ·  Space jump  ·  Esc release mouse  ·  R reset  ·  B lobbies"
	hint.position = Vector2(30,58)
	hint.add_theme_font_size_override("font_size",14)
	hint.modulate = Color(.65,.78,.85,.8)
	hud.add_child(hint)

func _reset() -> void:
	player.global_transform = $World/SpawnPoint.global_transform
	player.velocity = Vector3.ZERO
	camera.rotation = Vector3.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		captured = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			captured = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_B:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_tree().change_scene_to_file("res://Main.tscn")
		elif event.keycode == KEY_R:
			_reset()
	if event is InputEventMouseMotion and captured:
		player.rotate_y(-event.relative.x*.002)
		camera.rotation.x = clampf(camera.rotation.x-event.relative.y*.002,-1.45,1.45)

func _physics_process(delta: float) -> void:
	if player == null:
		return
	var axes := Input.get_vector("move_left","move_right","move_forward","move_backwards") if captured else Vector2.ZERO
	var direction := player.basis * Vector3(axes.x,0,axes.y)
	player.velocity.x = direction.x * 4.0
	player.velocity.z = direction.z * 4.0
	if not player.is_on_floor():
		player.velocity.y -= 9.8*delta
	elif captured and Input.is_action_just_pressed("jump"):
		player.velocity.y = 4.5
	else:
		player.velocity.y = 0
	player.move_and_slide()
