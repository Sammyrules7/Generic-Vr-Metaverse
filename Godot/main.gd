extends Node3D

const POINTER := preload("res://addons/godot-xr-tools/functions/function_pointer.tscn")
const TRACKED_HAND := preload("res://player/tracked_hand.gd")
var lobby_origin: XROrigin3D
var lobby_camera: XRCamera3D
var panel: XRToolsViewport2DIn3D
var ui: Control
var xr_active := false
var pointers: Array[Node3D] = []
var control_plane_notice: Label3D
var menu_pinch_time := 0.0
var menu_pinch_latched := false
var _world_load_generation := 0


func _ready() -> void:
	ui = $roomSelector
	ui.xr_requested.connect($StartXR.start_webxr)
	$StartXR.xr_started.connect(_enable_xr_lobby)
	$StartXR.xr_ended.connect(_disable_xr_lobby)
	$StartXR.xr_status_changed.connect(ui.set_xr_status)
	ui.set_xr_status($StartXR.xr_status)
	ui.menu_changed.connect(_menu_changed)
	ui.control_plane_warning_changed.connect(_control_plane_warning_changed)
	$PlayerManager.local_player_spawned.connect(_player_spawned)
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
		controller.name = "LeftHand" if hand == "left_hand" else "RightHand"
		controller.tracker = hand
		controller.pose = "grip"
		lobby_origin.add_child(controller)
		_attach_pointer(controller)
	panel = load("res://UI/vr_panel.tscn").instantiate()
	panel.name = "LobbyPanel"
	panel.viewport_size = Vector2(1120, 800)
	panel.screen_size = Vector2(0.56, 0.4)
	panel.unshaded = true
	add_child(panel)
	ui.reparent(panel.get_node("Viewport"))
	ui.vr_mode = true
	panel.pointer_event.connect(ui.get_node("Navigation").pointer_event)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.set_menu_open(ui.menu_open)
	panel.bind_rig(lobby_origin, lobby_camera, lobby_origin.get_node("LeftHand"))
	if is_instance_valid($PlayerManager.local_player):
		$PlayerManager.local_player.set_control_mode(true)
		_activate_player_rig()
	_menu_changed(ui.menu_open)


func _disable_xr_lobby() -> void:
	# Native OpenXR reports temporary focus loss (including its system menu)
	# through xr_ended. Keep the rig and XR rendering alive in that case.
	if $StartXR.xr_interface is OpenXRInterface and $StartXR.xr_interface.is_initialized():
		ui.set_menu_open(true)
		return
	xr_active = false
	get_viewport().use_xr = false
	if is_instance_valid(panel):
		panel.release_touch()
		ui.reparent(self)
		panel.queue_free()
	if is_instance_valid(lobby_origin):
		lobby_origin.queue_free()
	ui.vr_mode = false
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if is_instance_valid($PlayerManager.local_player):
		$PlayerManager.local_player.set_control_mode(false)
	ui.set_menu_open(true)


func load_world(world_id: String) -> Marker3D:
	_world_load_generation += 1
	var generation := _world_load_generation
	# Room IDs resolve only to bundled scenes, never to arbitrary network paths.
	var id := world_id if WorldCatalog.WORLDS.has(world_id) else "floating_island"
	var path: String = WorldCatalog.WORLDS[id].scene_path
	var error := ResourceLoader.load_threaded_request(path)
	if error != OK:
		push_error("Could not start loading world: " + path)
		return null
	var status := ResourceLoader.load_threaded_get_status(path)
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
		status = ResourceLoader.load_threaded_get_status(path)
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		push_error("Could not load world: " + path)
		return null
	var packed := ResourceLoader.load_threaded_get(path) as PackedScene
	# Consume the loader's result even when cancelled, releasing its request.
	if generation != _world_load_generation or not is_inside_tree():
		return null
	if packed == null:
		push_error("Could not load world: " + path)
		return null
	var old_world := get_node_or_null("World")
	if old_world != null:
		old_world.free()
	var world: Node3D = packed.instantiate()
	world.name = "World"
	add_child(world)
	return world.get_node("SpawnPoint")


func _player_spawned() -> void:
	if xr_active:
		$PlayerManager.local_player.set_control_mode(true)
		_activate_player_rig()
	_menu_changed(false)


func _activate_player_rig() -> void:
	lobby_origin.current = false
	lobby_camera.current = false
	lobby_origin.hide()
	var controls = $PlayerManager.local_player.controls
	controls.get_node("Origin").current = true
	controls.head.current = true
	_attach_pointer(controls.left_hand)
	_attach_pointer(controls.right_hand)
	panel.bind_rig(controls.get_node("Origin"), controls.head, controls.left_hand)


func _left() -> void:
	_world_load_generation += 1
	var world := get_node_or_null("World")
	if world != null:
		world.free()
	if xr_active:
		get_viewport().use_xr = true
		lobby_origin.current = true
		lobby_origin.show()
		lobby_camera.current = true
		panel.bind_rig(lobby_origin, lobby_camera, lobby_origin.get_node("LeftHand"))
	_menu_changed(true)


func _attach_pointer(controller: XRController3D) -> void:
	if controller.has_meta("ui_attached"):
		return
	controller.set_meta("ui_attached", true)
	# Grip poses are appropriate for hand meshes, but their axes and origin are
	# not the pointing ray (especially with optical hand tracking).
	var aim := XRController3D.new()
	aim.name = controller.name + "Aim"
	aim.tracker = controller.tracker
	aim.pose = "aim"
	controller.get_parent().add_child(aim)
	var pointer: Node3D = POINTER.instantiate()
	pointer.set_script(preload("res://UI/ui_pointer.gd"))
	pointer.process_priority = 25
	pointer.hand_offset_mode = 4
	pointer.distance = 4.0
	pointer.suppress_radius = 0.06
	pointer.collision_mask = 4194304
	pointer.show_laser = XRToolsFunctionPointer.LaserShow.COLLIDE
	pointer.laser_length = XRToolsFunctionPointer.LaserLength.COLLIDE
	pointer.y_offset = 0.0
	aim.add_child(pointer)
	pointer.enabled = false
	pointers.append(pointer)
	controller.button_pressed.connect(_controller_button_pressed)
	var tracked := Node3D.new()
	tracked.set_script(TRACKED_HAND)
	tracked.hand = "left" if controller.tracker == &"left_hand" else "right"
	controller.get_parent().add_child(tracked)


func _controller_button_pressed(action: String) -> void:
	if action in ["menu_button", "menu", "select_button", "by_button"] and Networking.room_networking.current_room != null:
		ui.set_menu_open(not ui.menu_open)


func _menu_changed(open: bool) -> void:
	var player: NetworkPlayer = $PlayerManager.local_player
	if is_instance_valid(player) and player.controls != null:
		player.controls.input_enabled = not open
	if xr_active:
		if not is_instance_valid(panel):
			return
		panel.visible = open
		panel.enabled = open
		_update_pointers()
		if not open:
			panel.release_touch()


func _update_pointers() -> void:
	for index in range(pointers.size() - 1, -1, -1):
		var pointer := pointers[index]
		if not is_instance_valid(pointer):
			pointers.remove_at(index)
			continue
		var controller := pointer.get_parent() as XRController3D
		var in_lobby := controller.get_parent() == lobby_origin
		var correct_rig := in_lobby == (Networking.room_networking.current_room == null)
		var hand := "left" if controller.tracker == &"left_hand" else "right"
		var tracked := PlatformXRInput.hand_tracker(hand)
		pointer.enabled = ui.menu_open and panel.visible and correct_rig and controller.get_is_active() and not PlatformXRInput.optical_hand(tracked)
		# Legacy controller hands stay local to the moving rig. Optical hands
		# are rendered from joint data by the tracked-hand sibling instead.
		var grip := controller.get_parent().get_node_or_null("LeftHand" if hand == "left" else "RightHand")
		if grip != null and grip.get_child_count() > 0:
			grip.get_child(0).visible = correct_rig and tracked == null and grip.get_is_active()


func _process(delta: float) -> void:
	if not xr_active:
		return
	_hand_menu_gesture(delta)
	var stick := Vector2.ZERO
	var point := Vector2(-1, -1)
	var body = panel.get_node("StaticBody3D")
	_update_pointers()
	for pointer in pointers:
		var controller := pointer.get_parent() as XRController3D
		var ray := pointer.get_node("RayCast") as RayCast3D
		var input := PlatformXRInput.stick(controller)
		if pointer.enabled and ray.is_colliding() and ray.get_collider() == body and input.length_squared() > stick.length_squared():
			stick = input
			point = body.global_to_viewport(ray.get_collision_point())
	ui.get_node("Navigation").handle_stick(stick, point, delta)


func _hand_menu_gesture(delta: float) -> void:
	# Hands-only fallback for runtimes that reserve the hardware menu button.
	# A held left thumb/ring pinch is distinct from thumb/index locomotion.
	var tracker := PlatformXRInput.hand_tracker("left")
	var thumb := XRHandTracker.HAND_JOINT_THUMB_TIP
	var ring := XRHandTracker.HAND_JOINT_RING_FINGER_TIP
	if Networking.room_networking.current_room == null or not PlatformXRInput.optical_hand(tracker) or not PlatformXRInput.joint_valid(tracker, thumb) or not PlatformXRInput.joint_valid(tracker, ring):
		menu_pinch_time = 0.0
		menu_pinch_latched = false
		return
	var distance := tracker.get_hand_joint_transform(thumb).origin.distance_to(tracker.get_hand_joint_transform(ring).origin)
	if distance > 0.04:
		menu_pinch_time = 0.0
		menu_pinch_latched = false
	elif distance < 0.02 and not menu_pinch_latched:
		menu_pinch_time += delta
		if menu_pinch_time >= 0.4:
			menu_pinch_latched = true
			ui.set_menu_open(not ui.menu_open)


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
