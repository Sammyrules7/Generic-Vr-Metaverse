extends Node

var failures := 0
var assertions := 0
var completed := 0
var last_spawn: Marker3D
var _measure_frames := false
var _last_frame_usec := 0
var _longest_frame_usec := 0

func _process(_delta: float) -> void:
	if _measure_frames:
		var now := Time.get_ticks_usec()
		_longest_frame_usec = maxi(_longest_frame_usec, now - _last_frame_usec)
		_last_frame_usec = now

func _ready() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(message)

func _load_world(game: Node, id: String) -> void:
	last_spawn = await game.load_world(id)
	completed += 1

func _run() -> void:
	var profile_existed := FileAccess.file_exists("user://profile.cfg")
	var profile_backup := FileAccess.get_file_as_bytes("user://profile.cfg") if profile_existed else PackedByteArray()
	Networking.set_process(false)
	Networking.ws.close(-1)
	Networking.room_networking.reset()
	var game = load("res://Main.tscn").instantiate()
	get_tree().root.add_child(game)
	var ui = game.get_node("roomSelector")
	var manager = game.get_node("PlayerManager")
	var state: RoomNetworking = Networking.room_networking
	state.current_room = roomClass.new(10, "Loading test", 1, "moon_garden")
	manager._room_joined(state.current_room)
	ui._room_joined(state.current_room)
	ui._operation_finished(RoomNetworking.Operation.JOIN, true, "")
	check(ui.world_loading and ui.menu_open and ui.get_node("%WorldLoading").visible, "Join must show loading until the player exists")
	ui.set_menu_open(false)
	check(ui.menu_open and ui.get_node("%Resume").disabled, "Menu cannot resume into an unfinished world")
	check(ui.xr_point_is_visible(ui.get_node("%CancelWorldLoading").get_global_rect().get_center()), "Loading screen must support VR touch cancellation")
	await get_tree().process_frame
	check(manager.local_player == null and ui.world_loading, "Loading must render before cached scene creation")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/world-loading.png")
	for frame in 600:
		if manager.local_player != null and not ui.world_loading:
			break
		await get_tree().process_frame
	check(manager.local_player != null and not ui.world_loading and not ui.menu_open, "Player readiness must dismiss the loading screen")
	check(not ui.get_node("%WorldLoading").visible, "Loading overlay remained after entry")
	state.current_room = null
	state.room_left.emit()
	check(not ui.world_loading and ui.menu_open, "Leave must restore the lobby")

	# A leave between loading feedback and resource acquisition must not install a world.
	_load_world(game, "moon_garden")
	state.room_left.emit()
	for frame in 5:
		await get_tree().process_frame
	check(completed == 1 and last_spawn == null and game.get_node_or_null("World") == null, "Cancelled cached load installed a stale world")

	# Exercise cancellation while procedural geometry is actively yielding.
	_load_world(game, "prairie_crossing")
	for frame in 600:
		if game.get_node_or_null("PendingWorld") != null:
			break
		await get_tree().process_frame
	check(game.get_node_or_null("PendingWorld") != null, "Procedural load never started")
	state.room_left.emit()
	for frame in 10:
		await get_tree().process_frame
	check(completed == 2 and last_spawn == null, "Procedural cancellation did not finish")
	check(game.get_node_or_null("World") == null and game.get_node_or_null("CancelledWorld") == null, "Cancelled geometry leaked into the lobby")

	# Unknown IDs must fail without substituting content or retiring the old world.
	var retained := Node3D.new()
	retained.name = "World"
	game.add_child(retained)
	var unknown: Marker3D = await game.load_world("not_a_bundled_world")
	check(unknown == null and game.get_node_or_null("World") == retained, "Unknown ID replaced the current world")

	# A malformed bundled scene should leave an actionable error, never blank UI.
	var definition := WorldDefinition.new()
	definition.id = "invalid_spawn"
	definition.title = "Invalid spawn"
	definition.scene_path = "res://UI/vr_panel.tscn"
	WorldCatalog.WORLDS[definition.id] = definition
	state.current_room = roomClass.new(11, "Invalid test", 1, definition.id)
	var point: Marker3D = await game.load_world(definition.id)
	check(point == null and not ui.world_loading and ui.menu_open, "Failed load must restore the menu")
	check(ui.get_node("%Resume").disabled and ui.get_node("%SessionStatus").text.contains("Could not load"), "Failed load needs an error and disabled Resume")
	var escape := InputEventAction.new()
	escape.action = "exit"
	escape.pressed = true
	ui._input(escape)
	check(ui.menu_open, "Escape must not dismiss a failed world load")
	game._controller_button_pressed("menu_button", &"left_hand")
	check(ui.menu_open, "Controller menu must not dismiss a failed world load")
	check(game.get_node_or_null("World") == retained, "Invalid adapter retired the current world")
	WorldCatalog.WORLDS.erase(definition.id)
	state.current_room = null
	state.room_left.emit()

	# Compare deterministic immediate and incremental generation and record its cost.
	var scene = load("res://worlds/prairie_crossing/prairie_crossing.tscn")
	var immediate = scene.instantiate()
	var started := Time.get_ticks_usec()
	get_tree().root.add_child(immediate)
	var immediate_ms := (Time.get_ticks_usec() - started) / 1000.0
	var expected_nodes: int = immediate.get_child_count()
	var expected_faces: int = _collision_faces(immediate).size()
	immediate.free()
	var incremental = scene.instantiate()
	incremental.set_meta("defer_world_build", true)
	get_tree().root.add_child(incremental)
	var frames_before := Engine.get_process_frames()
	started = Time.get_ticks_usec()
	_last_frame_usec = started
	_measure_frames = true
	await incremental.prepare_world()
	_measure_frames = false
	var incremental_ms := (Time.get_ticks_usec() - started) / 1000.0
	var yielded := Engine.get_process_frames() - frames_before
	check(yielded > 5, "Procedural generation must yield to UI and headset updates")
	check(incremental.get_child_count() == expected_nodes and _collision_faces(incremental).size() == expected_faces, "Incremental build changed world geometry")
	check(incremental.has_node("WeatherControl") and incremental.has_node("SpawnPoint"), "Prepared world must include weather controls and a spawn")
	print("Prairie startup: immediate %.1f ms; incremental %.1f ms across %d frames; longest frame interval %.1f ms" % [immediate_ms, incremental_ms, yielded, _longest_frame_usec / 1000.0])
	incremental.free()
	# Blackthorn previously did its entire build in _ready, stalling XR input.
	var house_scene = load("res://worlds/blackthorn_house/blackthorn_house.tscn")
	var house = house_scene.instantiate()
	get_tree().root.add_child(house)
	var expected_house_meshes: int = house.find_children("*", "MeshInstance3D", true, false).size()
	var expected_colliders: int = house.get_node("ArchitectureCollision").get_child_count()
	house.free()
	house = house_scene.instantiate()
	house.set_meta("defer_world_build", true)
	get_tree().root.add_child(house)
	check(not house.has_node("ArchitectureCollision"), "Deferred Blackthorn built synchronously in _ready")
	frames_before = Engine.get_process_frames()
	started = Time.get_ticks_usec()
	_last_frame_usec = started
	_longest_frame_usec = 0
	_measure_frames = true
	await house.prepare_world()
	_measure_frames = false
	check(Engine.get_process_frames() > frames_before, "Blackthorn preparation never yielded to hand tracking")
	check(house.find_children("*", "MeshInstance3D", true, false).size() == expected_house_meshes and house.get_node("ArchitectureCollision").get_child_count() == expected_colliders, "Incremental Blackthorn changed its geometry/collision")
	for emitter in house.find_children("*", "CPUParticles3D", true, false):
		check(emitter.preprocess == 0.0, "Blackthorn particle prewarm blocks entry")
	print("Blackthorn startup: %.1f ms across %d frames; longest frame interval %.1f ms" % [(Time.get_ticks_usec() - started) / 1000.0, Engine.get_process_frames() - frames_before, _longest_frame_usec / 1000.0])
	house.free()
	_load_world(game, "blackthorn_house")
	for frame in 600:
		if game.get_node_or_null("PendingWorld") != null:
			break
		await get_tree().process_frame
	state.room_left.emit()
	for frame in 10:
		await get_tree().process_frame
	check(completed == 3 and last_spawn == null and game.get_node_or_null("CancelledWorld") == null, "Cancelled Blackthorn build leaked or installed a world")
	_test_runtime_policy()
	var render_started := Time.get_ticks_usec()
	var frames_started := Engine.get_process_frames()
	await preload("res://worlds/world_runtime.gd").wait_for_rendering(get_tree(), func(): return true)
	check(Engine.get_process_frames() - frames_started >= 8 and Time.get_ticks_usec() - render_started >= 250000, "Loading dismissed before the rendering settling window")
	frames_started = Engine.get_process_frames()
	await preload("res://worlds/world_runtime.gd").wait_for_rendering(get_tree(), func(): return false)
	check(Engine.get_process_frames() == frames_started, "Cancelled entry waited for rendering")
	var retired := Node.new()
	var callback := Callable(retired, "is_inside_tree")
	retired.free()
	await preload("res://worlds/world_runtime.gd").wait_for_rendering(get_tree(), callback)
	check(Engine.get_process_frames() == frames_started, "Freed world owner did not cancel rendering wait")
	await _test_staged_entry(game)
	await _test_tracked_world_entry(game)
	game.free()
	await get_tree().create_timer(0.08).timeout
	if profile_existed:
		FileAccess.open("user://profile.cfg", FileAccess.WRITE).store_buffer(profile_backup)
	else:
		DirAccess.remove_absolute("user://profile.cfg")
	print("World loading: %d assertions, %d failures" % [assertions, failures])
	get_tree().quit(1 if failures else 0)


func _test_tracked_world_entry(game: Node) -> void:
	var trackers: Array[XRHandTracker] = []
	for side in ["left", "right"]:
		var tracker := XRHandTracker.new()
		tracker.name = "/user/hand_tracker/" + side
		tracker.hand = XRPositionalTracker.TRACKER_HAND_LEFT if side == "left" else XRPositionalTracker.TRACKER_HAND_RIGHT
		# WebXR reports UNKNOWN even with valid optical joints.
		tracker.has_tracking_data = true
		var pose := Transform3D(Basis.IDENTITY, Vector3(-0.2 if side == "left" else 0.2, 1.3, -0.4))
		for joint in XRHandTracker.HAND_JOINT_MAX:
			tracker.set_hand_joint_flags(joint, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID)
			tracker.set_hand_joint_transform(joint, pose)
		tracker.set_pose("default", pose, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		XRServer.add_tracker(tracker)
		trackers.append(tracker)
	game._enable_xr_lobby()
	await get_tree().process_frame
	await get_tree().process_frame
	var hands: Dictionary = game.tracked_hands.duplicate()
	var manager: PlayerManager = game.get_node("PlayerManager")
	var ui: Control = game.ui
	for entry in 2:
		var room := roomClass.new(900 + entry, "Tracked entry", 1, "moon_garden")
		Networking.room_networking.current_room = room
		manager._room_joined(room)
		for frame in 600:
			if manager.local_player != null and not ui.world_loading:
				break
			await get_tree().process_frame
		check(manager.local_player != null and not ui.world_loading, "Tracked world entry never completed")
		if manager.local_player == null:
			break
		var origin: XROrigin3D = manager.local_player.controls.get_node("Origin")
		for side in ["left", "right"]:
			var hand: XRNode3D = hands[side]
			check(game.tracked_hands[side] == hand and hand.get_parent() == origin, "World entry replaced or abandoned a live " + side + " hand")
			check(hand.is_visible_in_tree() and hand.modifier.active, "World entry hid a continuously tracked " + side + " hand")
		# Update joints without changing tracking validity or publishing a new
		# default pose. The hand must move without an occlusion/reconnection.
		var moved := Transform3D(Basis(Vector3.UP, 0.3), Vector3(0.35, 1.4, -0.6))
		trackers[1].set_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM, moved)
		await get_tree().process_frame
		await get_tree().process_frame
		var right: XRNode3D = hands.right
		var expected := origin.global_transform * XRServer.get_reference_frame() * moved
		check(right.global_transform.is_equal_approx(expected), "World-entry hand froze until a new tracking event")
		manager._clear_players()
		for hand in hands.values():
			check(is_instance_valid(hand) and hand.get_parent() == game.lobby_origin, "Player cleanup freed a live session hand")
		Networking.room_networking.current_room = null
		game._left()
		await get_tree().process_frame
	game._disable_xr_lobby()
	for tracker in trackers:
		XRServer.remove_tracker(tracker)


func _test_runtime_policy() -> void:
	var runtime = preload("res://worlds/world_runtime.gd")
	var world := Node3D.new()
	var environment_node := WorldEnvironment.new()
	var authored := Environment.new()
	authored.ssao_enabled = true
	authored.glow_enabled = true
	authored.volumetric_fog_enabled = true
	environment_node.environment = authored
	world.add_child(environment_node)
	var weather_environment := WorldEnvironment.new()
	var live_weather := Environment.new()
	weather_environment.environment = live_weather
	world.add_child(weather_environment)
	var lamp := OmniLight3D.new()
	lamp.light_bake_mode = Light3D.BAKE_STATIC
	lamp.shadow_enabled = true
	world.add_child(lamp)
	var sun := DirectionalLight3D.new()
	sun.directional_shadow_max_distance = 100.0
	world.add_child(sun)
	var particles := GPUParticles3D.new()
	particles.preprocess = 12.0
	world.add_child(particles)
	runtime.prepare_particles(world)
	check(particles.preprocess == 0.0, "GPU particle prewarm must be cleared before entering the scene tree")
	runtime.set_xr_mode(world, true)
	check(not environment_node.environment.ssao_enabled and not environment_node.environment.glow_enabled and not environment_node.environment.volumetric_fog_enabled, "XR retained costly screen effects")
	check(authored.ssao_enabled and authored.glow_enabled and authored.volumetric_fog_enabled, "XR modified shared authored resources")
	check(weather_environment.environment == live_weather, "XR replaced procedural weather's cached environment")
	check(lamp.visible and lamp.light_bake_mode == Light3D.BAKE_STATIC and lamp.distance_fade_enabled, "XR must retain nearby baked lights for dynamic objects")
	check(is_equal_approx(sun.directional_shadow_max_distance, 25.0), "XR shadow distance was not limited")
	runtime.set_xr_mode(world, false)
	check(environment_node.environment == authored and not lamp.distance_fade_enabled and is_equal_approx(sun.directional_shadow_max_distance, 100.0), "Leaving XR did not restore desktop lighting")
	world.free()


func _collision_faces(world: Node3D) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for collider: CollisionShape3D in world.get_node("TerrainAndLandmarkCollision").get_children():
		faces.append_array(collider.shape.get_faces())
	return faces


func _test_staged_entry(game: Node3D) -> void:
	var fixture := Node3D.new()
	var spawn := Marker3D.new()
	spawn.name = "SpawnPoint"
	spawn.position = Vector3(12, 0, 9)
	spawn.rotation.y = 0.7
	fixture.add_child(spawn)
	spawn.owner = fixture
	var environment := WorldEnvironment.new()
	environment.name = "TestEnvironment"
	environment.environment = Environment.new()
	environment.environment.glow_enabled = true
	fixture.add_child(environment)
	environment.owner = fixture
	var cube := BoxMesh.new()
	for index in 97:
		var mesh := MeshInstance3D.new()
		mesh.name = "Geometry%d" % index
		mesh.mesh = cube
		mesh.visible = index != 96
		fixture.add_child(mesh)
		mesh.owner = fixture
	var packed := PackedScene.new()
	packed.pack(fixture)
	var path := "user://staged_loading_test.tscn"
	check(ResourceSaver.save(packed, path) == OK, "Could not save staged-entry fixture")
	fixture.free()
	var definition := WorldDefinition.new()
	definition.id = "staged_entry"
	definition.title = "Staged entry"
	definition.scene_path = path
	WorldCatalog.WORLDS[definition.id] = definition
	var before := completed
	var saw_partial := false
	var drawing_frames := 0
	_load_world(game, definition.id)
	for frame in 600:
		if completed != before:
			break
		var pending := game.get_node_or_null("PendingWorld")
		if pending != null:
			var visible_count := 0
			for mesh in pending.find_children("*", "MeshInstance3D", true, false):
				if mesh.is_visible_in_tree():
					visible_count += 1
			if visible_count > 0 and visible_count < 96:
				if not saw_partial:
					var camera := get_viewport().get_camera_3d()
					check(camera != null and pending.is_ancestor_of(camera), "Staged entry has no drawing camera")
					check(camera.global_position.is_equal_approx(pending.get_node("SpawnPoint").global_position + Vector3.UP * 1.7), "Staged entry warmed the wrong viewpoint")
				saw_partial = true
				drawing_frames += 1
		await get_tree().process_frame
	check(saw_partial and drawing_frames >= 4, "First-use world draws were not staged across frames")
	check(completed == before + 1 and last_spawn != null, "Staged world did not finish loading")
	check(not game.get_node("World/Geometry96").visible, "Staging revealed authored-hidden geometry")
	Networking.room_networking.room_left.emit()
	# Leaving during drawing must also cancel, rather than install a partial world.
	before = completed
	_load_world(game, definition.id)
	for frame in 600:
		var pending := game.get_node_or_null("PendingWorld")
		if pending != null and pending.visible:
			break
		await get_tree().process_frame
	Networking.room_networking.room_left.emit()
	for frame in 10:
		await get_tree().process_frame
	check(completed == before + 1 and last_spawn == null and game.get_node_or_null("World") == null, "Cancelled staged entry installed a partial world")
	# The XR drawing stage must use the live tracking camera at the new spawn,
	# keeping hands and the loading tablet bound to that same origin.
	game._enable_xr_lobby()
	for side in ["LeftHand", "RightHand"]:
		var grip := game.lobby_origin.get_node(side) as XRController3D
		check(not grip.find_children("*", "MeshInstance3D", true, false).is_empty(), "Lobby controller has no hand model: " + side)
		for mesh: MeshInstance3D in grip.find_children("*", "MeshInstance3D", true, false):
			check(mesh.gi_mode == GeometryInstance3D.GI_MODE_DYNAMIC, "Moving controller hand must receive lightmap probes: " + side)
	_load_world(game, definition.id)
	var checked_xr_pose := false
	before = completed
	for frame in 600:
		if completed != before:
			break
		var pending := game.get_node_or_null("PendingWorld")
		if pending != null and pending.visible and not checked_xr_pose:
			checked_xr_pose = true
			check(not pending.get_node("TestEnvironment").environment.glow_enabled, "Pending world ignored XR rendering settings")
			game._disable_xr_lobby()
			check(pending.get_node("TestEnvironment").environment.glow_enabled, "Pending world did not restore desktop settings on XR exit")
			game._enable_xr_lobby()
			check(not pending.get_node("TestEnvironment").environment.glow_enabled, "Pending world did not apply settings on XR re-entry")
			check(game.lobby_origin.global_transform.is_equal_approx(pending.get_node("SpawnPoint").global_transform), "XR drawing did not use the spawn origin")
			check(game.panel.origin == game.lobby_origin and get_viewport().get_camera_3d() == game.lobby_camera, "XR drawing detached the loading tablet or tracking camera")
		await get_tree().process_frame
	check(checked_xr_pose and last_spawn != null, "XR drawing fixture did not complete")
	Networking.room_networking.room_left.emit()
	game._disable_xr_lobby()
	WorldCatalog.WORLDS.erase(definition.id)
	DirAccess.remove_absolute(path)
