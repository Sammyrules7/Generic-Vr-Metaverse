extends Node3D

const POINTER := preload("res://addons/godot-xr-tools/functions/function_pointer.tscn")
const TRACKED_HAND := preload("res://player/tracked_hand.gd")
var lobby_origin: XROrigin3D
var lobby_camera: XRCamera3D
var panel: XRToolsViewport2DIn3D
var ui: Control
var xr_active := false
var pointers: Array[Node3D] = []
var _world_load_generation := 0


func _ready() -> void:
	# Avoid Godot's default grey clear color while the lobby or a world is loading.
	RenderingServer.set_default_clear_color(Color("#09101a"))
	ui = $roomSelector
	ui.xr_requested.connect($StartXR.start_webxr)
	$StartXR.xr_started.connect(_enable_xr_lobby)
	$StartXR.xr_ended.connect(_disable_xr_lobby)
	$StartXR.webxr_support_changed.connect(ui.set_webxr_supported)
	ui.set_webxr_supported($StartXR.webxr_supported)
	ui.menu_changed.connect(_menu_changed)
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
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.set_menu_open(ui.menu_open)
	panel.bind_rig(lobby_origin, lobby_camera)
	if is_instance_valid($PlayerManager.local_player):
		$PlayerManager.local_player.set_control_mode(true)
		_activate_player_rig()
	_menu_changed(ui.menu_open)


func _disable_xr_lobby() -> void:
	# Native OpenXR reports temporary focus loss (including its system menu)
	# through xr_ended. Keep the rig, rendering, and app menu state intact:
	# opening the runtime dashboard is not an application menu action.
	if $StartXR.xr_interface != null and $StartXR.xr_interface.get_name() == "OpenXR" and $StartXR.xr_interface.is_initialized():
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
	# PlayerManager can join an existing room while children are still entering
	# the tree, before Main and the selector have run their _ready callbacks.
	if ui == null:
		await get_tree().process_frame
	if generation != _world_load_generation or not is_inside_tree():
		return null
	# Room IDs resolve only to bundled scenes, never to arbitrary network paths.
	var id := world_id if WorldCatalog.WORLDS.has(world_id) else WorldCatalog.default_id()
	if id.is_empty():
		push_error("Could not load world: the world catalog is empty")
		ui.finish_world_loading(false)
		return null
	ui.begin_world_loading(id)
	# Give both the desktop and XR panel a rendered loading frame before any
	# cached resource, scene instantiation, or synchronous fallback can run.
	await get_tree().process_frame
	await get_tree().process_frame
	if generation != _world_load_generation or not is_inside_tree():
		return null
	var path: String = WorldCatalog.WORLDS[id].scene_path
	var error := ResourceLoader.load_threaded_request(path)
	if error != OK:
		# A resource can already be cached or have a platform-specific threaded
		# loader failure. Loading it synchronously is a safe fallback here because
		# every path comes from the bundled world allowlist.
		push_warning("Threaded world load did not start (%s); retrying directly" % error_string(error))
	var packed: PackedScene
	if error == OK:
		var status := ResourceLoader.load_threaded_get_status(path)
		while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			var progress := []
			ResourceLoader.load_threaded_get_status(path, progress)
			if generation == _world_load_generation:
				ui.set_world_loading_progress("Loading world…", float(progress[0]) * 0.7 if not progress.is_empty() else 0.0)
			await get_tree().process_frame
			status = ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			packed = ResourceLoader.load_threaded_get(path) as PackedScene
	if packed == null:
		packed = load(path) as PackedScene
	# Consume the loader's result even when cancelled, releasing its request.
	if generation != _world_load_generation or not is_inside_tree():
		return null
	if packed == null:
		push_error("Could not load world: " + path)
		ui.finish_world_loading(false)
		return null
	ui.set_world_loading_progress("Preparing world…", 0.7)
	await get_tree().process_frame
	if generation != _world_load_generation or not is_inside_tree():
		return null
	var world := packed.instantiate() as Node3D
	if world == null:
		ui.finish_world_loading(false)
		return null
	world.set_meta("defer_world_build", true)
	if world.has_signal("world_build_progress"):
		world.connect("world_build_progress", func(progress: float):
			if generation == _world_load_generation:
				ui.set_world_loading_progress("Preparing world…", 0.7 + progress * 0.25)
		)
	world.name = "World"
	var old_world := get_node_or_null("World")
	if old_world != null:
		_retire_world(old_world)
	add_child(world)
	if world.has_method("prepare_world"):
		world.set_meta("preparation_pending", true)
		await world.prepare_world()
		if is_instance_valid(world):
			world.set_meta("preparation_pending", false)
	if generation != _world_load_generation or not is_inside_tree() or not is_instance_valid(world):
		if is_instance_valid(world):
			world.queue_free()
		return null
	var spawn := world.get_node_or_null("SpawnPoint") as Marker3D
	if spawn == null:
		world.queue_free()
		ui.finish_world_loading(false)
		return null
	ui.set_world_loading_progress("Entering world…", 0.95)
	return spawn


func _player_spawned() -> void:
	var generation := _world_load_generation
	var player: NetworkPlayer = $PlayerManager.local_player
	if xr_active:
		$PlayerManager.local_player.set_control_mode(true)
		_activate_player_rig()
	_menu_changed(true)
	# Keep feedback over the world's first rendered frame and camera handoff.
	await get_tree().process_frame
	await get_tree().process_frame
	if generation != _world_load_generation or not is_instance_valid(player):
		return
	ui.finish_world_loading()


func _activate_player_rig() -> void:
	lobby_origin.current = false
	lobby_camera.current = false
	lobby_origin.hide()
	var controls = $PlayerManager.local_player.controls
	controls.get_node("Origin").current = true
	controls.head.current = true
	_attach_pointer(controls.left_hand)
	_attach_pointer(controls.right_hand)
	panel.bind_rig(controls.get_node("Origin"), controls.head)


func _left() -> void:
	_world_load_generation += 1
	var world := get_node_or_null("World")
	if world != null:
		_retire_world(world)
	if $StartXR.xr_interface != null and $StartXR.xr_interface.get_name() == "WebXR" and $StartXR.xr_interface.is_initialized():
		$StartXR.end_xr()
		return
	if xr_active:
		get_viewport().use_xr = true
		lobby_origin.current = true
		lobby_origin.show()
		lobby_camera.current = true
		panel.bind_rig(lobby_origin, lobby_camera)
	_menu_changed(true)


func _retire_world(world: Node3D) -> void:
	# Let an in-flight procedural build return before releasing its coroutine.
	if world.has_method("cancel_world_preparation") and world.get_meta("preparation_pending", false):
		world.cancel_world_preparation()
		world.name = "CancelledWorld"
		world.hide()
		world.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		world.free()


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
	controller.button_pressed.connect(_controller_button_pressed.bind(controller.tracker))
	var tracked := XRNode3D.new()
	tracked.set_script(TRACKED_HAND)
	tracked.hand = "left" if controller.tracker == &"left_hand" else "right"
	controller.get_parent().add_child(tracked)


func _controller_button_pressed(action: String, controller_tracker: StringName) -> void:
	if action == "menu_button" and controller_tracker == &"left_hand" and Networking.room_networking.current_room != null:
		ui.set_menu_open(not ui.menu_open)


func _menu_changed(open: bool) -> void:
	var player: NetworkPlayer = $PlayerManager.local_player
	if is_instance_valid(player) and player.controls != null:
		player.controls.input_enabled = not open
	if xr_active:
		if not is_instance_valid(panel):
			return
		var in_room: bool = Networking.room_networking.current_room != null and not ui.world_loading
		panel.set_room_mode(in_room, in_room and not open)
		panel.visible = open or in_room
		panel.enabled = panel.visible
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
		var correct_rig: bool = in_lobby == (Networking.room_networking.current_room == null or ui.world_loading)
		var hand := "left" if controller.tracker == &"left_hand" else "right"
		var tracked := PlatformXRInput.hand_tracker(hand)
		pointer.enabled = panel.visible and correct_rig and controller.get_is_active() and not PlatformXRInput.optical_hand(tracked)
		# Legacy controller hands stay local to the moving rig. Optical hands
		# are rendered from joint data by the tracked-hand sibling instead.
		var grip := controller.get_parent().get_node_or_null("LeftHand" if hand == "left" else "RightHand")
		if grip != null and grip.get_child_count() > 0:
			grip.get_child(0).visible = correct_rig and tracked == null and grip.get_is_active()


func _process(delta: float) -> void:
	if not xr_active:
		return
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
