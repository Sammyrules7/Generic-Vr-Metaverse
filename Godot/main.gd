extends Node3D

const POINTER := preload("res://addons/godot-xr-tools/functions/function_pointer.tscn")
const TRACKED_HAND := preload("res://player/tracked_hand.gd")
const CONTROLLER_HANDS := {
	"left_hand": preload("res://addons/godot-xr-tools/hands/scenes/lowpoly/left_hand_low.tscn"),
	"right_hand": preload("res://addons/godot-xr-tools/hands/scenes/lowpoly/right_hand_low.tscn"),
}
var lobby_origin: XROrigin3D
var lobby_camera: XRCamera3D
var panel: XRToolsViewport2DIn3D
var ui: Control
var xr_active := false
var pointers: Array[Node3D] = []
var tracked_hands: Dictionary = {}
const WORLD_ADAPTER := preload("res://worlds/world_adapter.gd")
const WORLD_RUNTIME := preload("res://worlds/world_runtime.gd")
var _desktop_msaa: int
var _desktop_screen_aa: int
var _world_load_generation := 0
var _pending_world: Node3D
var _panel_body_cache: Node3D
var _ray_cache: Dictionary = {}


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
	$PlayerManager.players_clearing.connect(_retain_tracked_hands)
	Networking.room_networking.room_left.connect(_left)
	_menu_changed(true)


func _enable_xr_lobby() -> void:
	if xr_active:
		return
	xr_active = true
	_desktop_msaa = get_viewport().msaa_3d
	_desktop_screen_aa = get_viewport().screen_space_aa
	get_viewport().msaa_3d = Viewport.MSAA_2X
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	var world := get_node_or_null("World") as Node3D
	if world != null:
		WORLD_RUNTIME.set_xr_mode(world, true)
	if is_instance_valid(_pending_world):
		WORLD_RUNTIME.set_xr_mode(_pending_world, true)
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
		controller.add_child(CONTROLLER_HANDS[hand].instantiate())
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
	if is_instance_valid(_pending_world) and _pending_world.visible:
		lobby_origin.global_transform = WORLD_ADAPTER.spawn_point(_pending_world).global_transform
		lobby_origin.current = true
		lobby_camera.current = true
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
	if not xr_active:
		return
	xr_active = false
	get_viewport().msaa_3d = _desktop_msaa
	get_viewport().screen_space_aa = _desktop_screen_aa
	var world := get_node_or_null("World") as Node3D
	if world != null:
		WORLD_RUNTIME.set_xr_mode(world, false)
	if is_instance_valid(_pending_world):
		WORLD_RUNTIME.set_xr_mode(_pending_world, false)
	get_viewport().use_xr = false
	if is_instance_valid(_pending_world) and _pending_world.visible:
		var entry_camera := _pending_world.get_node_or_null("WorldEntryCamera") as Camera3D
		if entry_camera == null:
			entry_camera = Camera3D.new()
			entry_camera.name = "WorldEntryCamera"
			_pending_world.add_child(entry_camera)
		entry_camera.global_transform = WORLD_ADAPTER.spawn_point(_pending_world).global_transform
		entry_camera.global_position += Vector3.UP * 1.7
		entry_camera.current = true
	if is_instance_valid(panel):
		panel.release_touch()
		panel.enabled = false
		ui.reparent(self)
		panel.queue_free()
	if is_instance_valid(lobby_origin):
		lobby_origin.queue_free()
	ui.vr_mode = false
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if is_instance_valid($PlayerManager.local_player):
		$PlayerManager.local_player.set_control_mode(false)
	tracked_hands.clear()
	ui.set_menu_open(true)


func load_world(world_id: String) -> Marker3D:
	_world_load_generation += 1
	if is_instance_valid(_pending_world):
		_retire_world(_pending_world)
	_pending_world = null
	var generation := _world_load_generation
	# PlayerManager can join an existing room while children are still entering
	# the tree, before Main and the selector have run their _ready callbacks.
	if ui == null:
		await get_tree().process_frame
	if generation != _world_load_generation or not is_inside_tree():
		return null
	# Room IDs resolve only to bundled scenes, never to arbitrary network paths.
	var id := world_id
	if not WorldCatalog.WORLDS.has(id):
		push_error("Could not load unknown world ID: " + id)
		ui.finish_world_loading(false)
		return null
	ui.begin_world_loading(id)
	# Give both the desktop and XR panel a rendered loading frame before any
	# cached resource or scene instantiation can run.
	await get_tree().process_frame
	await get_tree().process_frame
	if generation != _world_load_generation or not is_inside_tree():
		return null
	var path: String = WorldCatalog.WORLDS[id].scene_path
	var load_started := Time.get_ticks_usec()
	var error := ResourceLoader.load_threaded_request(path)
	if error != OK:
		# A direct fallback can block XR for seconds. Report the failure instead.
		push_error("Threaded world load did not start: " + error_string(error))
		ui.finish_world_loading(false)
		return null
	var packed: PackedScene
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
	# Consume the loader's result even when cancelled, releasing its request.
	if generation != _world_load_generation or not is_inside_tree():
		return null
	if packed == null:
		push_error("Could not load world: " + path)
		ui.finish_world_loading(false)
		return null
	var resources_loaded := Time.get_ticks_usec()
	ui.set_world_loading_progress("Preparing world…", 0.7)
	await get_tree().process_frame
	if generation != _world_load_generation or not is_inside_tree():
		return null
	var instantiation_started := Time.get_ticks_usec()
	var instance := packed.instantiate()
	var instantiation_finished := Time.get_ticks_usec()
	var world := instance as Node3D
	if world == null or not WORLD_ADAPTER.validate(world):
		if is_instance_valid(instance):
			instance.free()
		ui.finish_world_loading(false)
		return null
	WORLD_RUNTIME.prepare_particles(world)
	world.set_meta("defer_world_build", true)
	if world.has_signal("world_build_progress"):
		world.connect("world_build_progress", func(progress: float):
			if generation == _world_load_generation:
				ui.set_world_loading_progress("Preparing world…", 0.7 + progress * 0.18)
		)
	world.name = "PendingWorld"
	_pending_world = world
	world.hide()
	var enter_started := Time.get_ticks_usec()
	add_child(world)
	var enter_finished := Time.get_ticks_usec()
	if world.has_method("prepare_world"):
		world.set_meta("preparation_pending", true)
		await world.prepare_world()
		if is_instance_valid(world):
			world.set_meta("preparation_pending", false)
	if generation != _world_load_generation or not is_inside_tree() or not is_instance_valid(world):
		if is_instance_valid(world):
			world.queue_free()
		return null
	WORLD_RUNTIME.prepare_particles(world)
	WORLD_RUNTIME.set_xr_mode(world, xr_active)
	var preparation_finished := Time.get_ticks_usec()
	var spawn := WORLD_ADAPTER.spawn_point(world)
	if spawn == null:
		_pending_world = null
		world.queue_free()
		ui.finish_world_loading(false)
		return null
	# Draw from the actual entry pose. Otherwise meshes out of the lobby
	# camera's frustum would still compile/upload together after the handoff.
	var loading_camera: Camera3D
	if xr_active and is_instance_valid(lobby_origin):
		lobby_origin.global_transform = spawn.global_transform
		lobby_origin.current = true
		lobby_origin.show()
		lobby_camera.current = true
		panel.bind_rig(lobby_origin, lobby_camera)
	else:
		loading_camera = Camera3D.new()
		world.add_child(loading_camera)
		loading_camera.global_transform = spawn.global_transform
		loading_camera.global_position += Vector3.UP * 1.7
		loading_camera.current = true
	# Hidden worlds do not warm their draw calls. Reveal small batches while
	# loading feedback remains up, so first-use GL work is spread across frames.
	var visuals: Array[GeometryInstance3D] = WORLD_RUNTIME.hide_visuals(world)
	world.show()
	var batch_started := Time.get_ticks_usec()
	var batch_count := 0
	for index in visuals.size():
		if generation != _world_load_generation or not is_inside_tree() or not is_instance_valid(world):
			return null
		visuals[index].show()
		batch_count += 1
		if batch_count >= 16 or Time.get_ticks_usec() - batch_started >= 2000:
			ui.set_world_loading_progress("Drawing world…", 0.88 + 0.07 * float(index + 1) / visuals.size())
			await get_tree().process_frame
			batch_started = Time.get_ticks_usec()
			batch_count = 0
	if generation != _world_load_generation or not is_inside_tree() or not is_instance_valid(world):
		return null
	print("World startup %s: resources %.1f ms; instantiate %.1f ms; enter tree %.1f ms; preparation %.1f ms; drawing %.1f ms" % [id, (resources_loaded - load_started) / 1000.0, (instantiation_finished - instantiation_started) / 1000.0, (enter_finished - enter_started) / 1000.0, (preparation_finished - enter_finished) / 1000.0, (Time.get_ticks_usec() - preparation_finished) / 1000.0])
	if loading_camera != null:
		loading_camera.free()
	var switched_camera := world.get_node_or_null("WorldEntryCamera")
	if switched_camera != null:
		switched_camera.free()
	_pending_world = null
	var old_world := get_node_or_null("World") as Node3D
	if old_world != null:
		_retire_world(old_world)
	world.name = "World"
	world.show()
	ui.set_world_loading_progress("Entering world…", 0.95)
	return spawn


func _player_spawned() -> void:
	var generation := _world_load_generation
	var player: NetworkPlayer = $PlayerManager.local_player
	if xr_active:
		$PlayerManager.local_player.set_control_mode(true)
		_activate_player_rig()
	_menu_changed(true)
	# The player's rig can select different draw variants from the warm-up
	# camera. Keep the overlay until this actual viewpoint has settled.
	var player_ref: WeakRef = weakref(player)
	await WORLD_RUNTIME.wait_for_rendering(get_tree(), func():
		return generation == _world_load_generation and player_ref.get_ref() != null
	)
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


func _retain_tracked_hands() -> void:
	# PlayerManager calls this before freeing the outgoing player's controls.
	# Keep the live optical meshes/modifiers for the next world in this session.
	if not xr_active or not is_instance_valid(lobby_origin):
		return
	for tracked in tracked_hands.values():
		if is_instance_valid(tracked) and tracked.get_parent() != lobby_origin:
			tracked.reparent(lobby_origin, false)


func _left() -> void:
	_world_load_generation += 1
	if is_instance_valid(_pending_world):
		_retire_world(_pending_world)
	_pending_world = null
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
	var side := "left" if controller.tracker == &"left_hand" else "right"
	var tracked: Variant = tracked_hands.get(side)
	if not is_instance_valid(tracked):
		tracked = XRNode3D.new()
		tracked.set_script(TRACKED_HAND)
		tracked.hand = side
		tracked_hands[side] = tracked
		controller.get_parent().add_child(tracked)
	elif tracked.get_parent() != controller.get_parent():
		# World entry moves the already-tracking hands instead of constructing
		# a second set that needs to initialize against a live browser source.
		tracked.reparent(controller.get_parent(), false)


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
	var in_room_cached: bool = Networking.room_networking.current_room != null and not ui.world_loading
	var panel_visible := is_instance_valid(panel) and panel.visible
	for index in range(pointers.size() - 1, -1, -1):
		var pointer := pointers[index]
		if not is_instance_valid(pointer):
			pointers.remove_at(index)
			_ray_cache.erase(pointer)
			continue
		var controller := pointer.get_parent() as XRController3D
		if controller == null:
			continue
		var in_lobby := is_instance_valid(lobby_origin) and controller.get_parent() == lobby_origin
		var correct_rig: bool = in_lobby != in_room_cached
		var hand := "left" if controller.tracker == &"left_hand" else "right"
		# A briefly lost optical tracker must not reveal a frozen controller hand
		# or enable its stale aim ray while optical tracking reacquires.
		var tracked := PlatformXRInput.hand_tracker(hand, false)
		pointer.enabled = panel_visible and correct_rig and controller.get_is_active() and not PlatformXRInput.optical_hand(tracked)
		# Legacy controller hands stay local to the moving rig. Optical hands
		# are rendered from joint data by the tracked-hand sibling instead.
		var grip := controller.get_parent().get_node_or_null("LeftHand" if hand == "left" else "RightHand")
		if grip != null and grip.get_child_count() > 0:
			grip.get_child(0).visible = correct_rig and not PlatformXRInput.optical_hand(tracked) and grip.get_is_active()


func _process(delta: float) -> void:
	if not xr_active:
		return
	_update_pointers()
	if not is_instance_valid(panel) or not panel.visible:
		return
	var stick := Vector2.ZERO
	var point := Vector2(-1, -1)
	if _panel_body_cache == null or not is_instance_valid(_panel_body_cache):
		_panel_body_cache = panel.get_node("StaticBody3D")
	var body = _panel_body_cache
	for pointer in pointers:
		if not is_instance_valid(pointer) or not pointer.enabled:
			continue
		var controller := pointer.get_parent() as XRController3D
		# is_instance_valid guards the freed-safe check; `as` errors on
		# freed instances, so it must come second.
		var ray: RayCast3D = null
		var cached_ray: Variant = _ray_cache.get(pointer)
		if cached_ray != null and is_instance_valid(cached_ray):
			ray = cached_ray as RayCast3D
		else:
			ray = pointer.get_node("RayCast") as RayCast3D
			_ray_cache[pointer] = ray
		if ray == null or not ray.is_colliding() or ray.get_collider() != body:
			continue
		var input := PlatformXRInput.stick(controller)
		if input.length_squared() > stick.length_squared():
			stick = input
			point = body.global_to_viewport(ray.get_collision_point())
	ui.get_node("Navigation").handle_stick(stick, point, delta)
