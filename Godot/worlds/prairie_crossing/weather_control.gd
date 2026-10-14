extends Node3D
## Physical, local weather selection for desktop, controllers, and fingertips.
var weather: Node3D
var buttons: Array[StaticBody3D] = []
var caption: Label3D
var held: Dictionary = {}
var touched := -1
var _manager_cache: PlayerManager
var _touch_accum := 0.0

func _ready() -> void:
	weather = get_parent().get_node("Weather")
	caption = _label("WEATHER STATION", Vector3(0, 2.04, 0.1), 30)
	_label("POINT + TRIGGER / TOUCH · E TO CYCLE", Vector3(0, 1.32, 0.1), 16)
	for index in weather.PRESETS.size():
		var button := StaticBody3D.new()
		button.name = weather.TITLES[index].replace(" ", "")
		button.position = Vector3((index - 1) * 0.88, 1.68, 0.14)
		button.set_meta("weather_index", index)
		add_child(button)
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.78, 0.34, 0.07)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		button.add_child(collision)
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = shape.size
		mesh.mesh = box
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override = material
		button.add_child(mesh)
		buttons.append(button)
		_label(weather.TITLES[index], button.position + Vector3(0, 0, 0.045), 22)
	weather.weather_changed.connect(_update)
	_update(weather.preset)

func _label(text: String, at: Vector3, size: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.font_size = size
	label.pixel_size = 0.003
	label.outline_size = 0
	label.modulate = Color("f5eed7")
	add_child(label)
	return label

func _update(preset: String) -> void:
	caption.text = "WEATHER · " + weather.TITLES[weather.PRESETS.find(preset)].to_upper()
	for index in buttons.size():
		var mesh := buttons[index].get_child(1) as MeshInstance3D
		mesh.material_override.albedo_color = Color("4c9a91") if weather.PRESETS[index] == preset else Color("48635c")

func select_button(index: int) -> void:
	if index >= 0 and index < weather.PRESETS.size():
		weather.set_weather(weather.PRESETS[index])

func _controls() -> PlayerControls:
	if _manager_cache == null or not is_instance_valid(_manager_cache):
		_manager_cache = get_parent().get_parent().get_node_or_null("PlayerManager") as PlayerManager
	var manager := _manager_cache
	if manager != null and is_instance_valid(manager.local_player):
		return manager.local_player.controls
	return null

func _pick(origin: Vector3, direction: Vector3) -> int:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 3.0, 1)
	var controls := _controls()
	if controls != null:
		query.exclude = [controls.body.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider in buttons:
		return int(hit.collider.get_meta("weather_index"))
	return -1

func _unhandled_input(event: InputEvent) -> void:
	var controls := _controls()
	if controls == null or not controls.input_enabled or get_viewport().use_xr:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_E:
		if controls.head.global_position.distance_to(to_global(Vector3(0, 1.68, 0))) < 3.0:
			weather.cycle_weather()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var index := _pick(controls.head.global_position, -controls.head.global_basis.z)
		if index >= 0:
			select_button(index)
			get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	var controls := _controls()
	if controls == null or not controls.input_enabled or not get_viewport().use_xr:
		held.clear()
		touched = -1
		return
	for controller in [controls.left_hand, controls.right_hand]:
		if not controller is XRController3D:
			continue
		var pressed: bool = controller.get_is_active() and (controller.is_button_pressed("trigger_click") or controller.get_float("trigger") > 0.7)
		if pressed and not held.get(controller.name, false):
			var aim := controller.get_parent().get_node_or_null(str(controller.name) + "Aim") as Node3D
			if aim != null:
				select_button(_pick(aim.global_position, -aim.global_basis.z))
		held[controller.name] = pressed
	# Fingertip hover at ~20Hz is plenty; joint queries + to_local per tick wasted.
	_touch_accum += delta
	if _touch_accum < 0.05:
		return
	_touch_accum = 0.0
	var tracker := PlatformXRInput.hand_tracker("right")
	var joint := XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP
	var contact := -1
	if PlatformXRInput.optical_hand(tracker) and PlatformXRInput.joint_valid(tracker, joint):
		var origin := controls.head.get_parent() as XROrigin3D
		var tip := PlatformXRInput.joint_world(origin, tracker, joint).origin
		for index in buttons.size():
			var local := buttons[index].to_local(tip)
			if absf(local.x) < 0.39 and absf(local.y) < 0.17 and local.z >= -0.02 and local.z <= 0.06:
				contact = index
	if contact >= 0 and contact != touched:
		select_button(contact)
	touched = contact
