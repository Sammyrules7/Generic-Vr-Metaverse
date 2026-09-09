extends Node3D

const POINTER := preload("res://addons/godot-xr-tools/functions/function_pointer.tscn")
var lobby_origin: XROrigin3D
var lobby_camera: XRCamera3D
var panel: XRToolsViewport2DIn3D
var ui: Control
var xr_active := false
var pointers: Array[Node3D] = []
var control_plane_notice: Label3D


func _ready() -> void:
	ui = $roomSelector
	$StartXR.xr_started.connect(_enable_xr_lobby)
	$StartXR.xr_ended.connect(_disable_xr_lobby)
	ui.menu_changed.connect(_menu_changed)
	ui.control_plane_warning_changed.connect(_control_plane_warning_changed)
	Networking.room_networking.room_joined.connect(_joined)
	Networking.room_networking.room_left.connect(_left)
	_menu_changed(true)


func _enable_xr_lobby() -> void:
	if xr_active:
		return
	xr_active = true
	get_viewport().use_xr = true
	lobby_origin = XROrigin3D.new()
	lobby_origin.name = "LobbyOrigin"
	add_child(lobby_origin)
	lobby_camera = XRCamera3D.new()
	lobby_camera.position.y = 1.7
	lobby_origin.add_child(lobby_camera)
	for hand: String in ["left_hand", "right_hand"]:
		var controller := XRController3D.new()
		controller.tracker = hand
		controller.pose = "grip"
		lobby_origin.add_child(controller)
		_attach_pointer(controller)
	panel = load("res://UI/vr_panel.tscn").instantiate()
	panel.name = "LobbyPanel"
	panel.viewport_size = Vector2(1120, 800)
	panel.screen_size = Vector2(2.24, 1.6)
	panel.unshaded = true
	add_child(panel)
	ui.reparent(panel.get_node("Viewport"))
	ui.vr_mode = true
	panel.pointer_event.connect(ui.get_node("Navigation").pointer_event)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_position_panel(lobby_camera)
	_menu_changed(ui.menu_open)


func _disable_xr_lobby() -> void:
	xr_active = false
	get_viewport().use_xr = false


func load_world(world_id: String) -> Marker3D:
	# Room IDs resolve only to bundled scenes, never to arbitrary network paths.
	var id := world_id if WorldCatalog.WORLDS.has(world_id) else "floating_island"
	var old_world := get_node_or_null("World")
	if old_world != null:
		old_world.free()
	var world: Node3D = WorldCatalog.WORLDS[id].scene.instantiate()
	world.name = "World"
	add_child(world)
	return world.get_node("SpawnPoint")


func _joined(_room: roomClass) -> void:
	if xr_active:
		lobby_origin.current = false
		lobby_camera.current = false
		lobby_origin.hide()
		var controls = $PlayerManager.local_player.controls
		controls.get_node("Origin").current = true
		controls.head.current = true
		_attach_pointer(controls.left_hand)
		_attach_pointer(controls.right_hand)
	_menu_changed(false)


func _left() -> void:
	if xr_active:
		get_viewport().use_xr = true
		lobby_origin.current = true
		lobby_origin.show()
		lobby_camera.current = true
		_position_panel(lobby_camera)
	_menu_changed(true)


func _attach_pointer(controller: XRController3D) -> void:
	var pointer: Node3D = POINTER.instantiate()
	controller.add_child(pointer)
	pointers.append(pointer)
	controller.button_pressed.connect(func(action: String):
		if action in ["by_button", "menu_button"] and Networking.room_networking.current_room != null:
			ui.set_menu_open(not ui.menu_open)
	)


func _position_panel(camera: Node3D) -> void:
	var forward := -camera.global_basis.z
	forward.y = 0
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	panel.global_position = camera.global_position + forward.normalized() * 2.0
	panel.look_at(panel.global_position + forward.normalized(), Vector3.UP)


func _menu_changed(open: bool) -> void:
	var player: NetworkPlayer = $PlayerManager.local_player
	if is_instance_valid(player) and player.controls != null:
		player.controls.input_enabled = not open
	if xr_active:
		panel.visible = open
		panel.enabled = open
		for pointer in pointers:
			if is_instance_valid(pointer):
				pointer.enabled = open and pointer.get_parent().get_is_active()
		if open:
			var camera: Node3D = player.controls.head if is_instance_valid(player) else lobby_camera
			_position_panel(camera)


func _process(delta: float) -> void:
	if not xr_active:
		return
	var stick := Vector2.ZERO
	var point := Vector2(-1, -1)
	var body = panel.get_node("StaticBody3D")
	for index in range(pointers.size() - 1, -1, -1):
		var pointer := pointers[index]
		if not is_instance_valid(pointer):
			pointers.remove_at(index)
			continue
		var controller := pointer.get_parent() as XRController3D
		var in_lobby := controller.get_parent() == lobby_origin
		pointer.enabled = ui.menu_open and controller.get_is_active() and (in_lobby == (Networking.room_networking.current_room == null))
		var ray := pointer.get_node("RayCast") as RayCast3D
		var input := controller.get_vector2("primary")
		if pointer.enabled and ray.is_colliding() and ray.get_collider() == body and input.length_squared() > stick.length_squared():
			stick = input
			point = body.global_to_viewport(ray.get_collision_point())
	ui.get_node("Navigation").handle_stick(stick, point, delta)


func _control_plane_warning_changed(message: String) -> void:
	if not xr_active:
		return
	if message.is_empty():
		if is_instance_valid(control_plane_notice):
			control_plane_notice.hide()
		return
	var player: NetworkPlayer = $PlayerManager.local_player
	if player == null:
		return
	if not is_instance_valid(control_plane_notice):
		control_plane_notice = Label3D.new()
		control_plane_notice.name = "ControlPlaneNotice"
		control_plane_notice.font_size = 28
		control_plane_notice.pixel_size = 0.001
		control_plane_notice.position = Vector3(0, -0.35, -1.5)
		control_plane_notice.no_depth_test = true
		control_plane_notice.modulate = Color("#f5bc79")
		player.controls.head.add_child(control_plane_notice)
	control_plane_notice.text = message
	control_plane_notice.show()
