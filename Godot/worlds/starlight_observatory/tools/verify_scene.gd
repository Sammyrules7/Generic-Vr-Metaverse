extends SceneTree
## Production scene, collision, locomotion, globe interaction and recovery checks.

var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var world: Node3D = load("res://worlds/starlight_observatory/observatory.tscn").instantiate()
	scene.add_child(world)
	var players := Node3D.new()
	players.name = "Players"
	scene.add_child(players)
	var player = load("res://player/network_player.tscn").instantiate()
	players.add_child(player)
	player.global_transform = world.get_node("SpawnPoint").global_transform
	var globe := world.get_node("StarGlobe")
	for i in 90:
		await physics_frame
	check(player.is_on_floor(), "Spawn must settle on the terrace")
	check(absf(player.position.y) < 0.15, "Spawn floor should be at zero")
	var bodies := scene.find_children("*", "StaticBody3D", true, false)
	check(bodies.size() >= 5, "Imported architecture must contain static collisions")
	var space := scene.get_world_3d().direct_space_state
	for x in [-7.0, 0.0, 7.0]:
		for z in [-5.0, 5.0, 11.0]:
			var ray := PhysicsRayQueryParameters3D.create(Vector3(x, 0.3, z), Vector3(x, -1, z))
			check(not space.intersect_ray(ray).is_empty(), "Missing walkway floor at %s, %s" % [x, z])
	Input.action_press("move_forward")
	for i in 210:
		await physics_frame
	Input.action_release("move_forward")
	check(player.position.z < 3.0 and player.position.z > 1.2, "Walk from arrival to globe, stopping at plinth")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	key.pressed = true
	globe._unhandled_key_input(key)
	check(globe.selected_map == 1, "Nearby E input must select the next constellation")
	check(globe.get_node("Orbits/Constellations/Map1").visible, "Selected constellation should be visible")
	key.physical_keycode = KEY_R
	globe._unhandled_key_input(key)
	check(not globe.spinning, "R must pause the globe")
	# Exercise the OpenXR action path without needing physical controllers.
	var tracker := XRControllerTracker.new()
	tracker.name = &"left_hand"
	tracker.type = XRServer.TRACKER_CONTROLLER
	tracker.set_input(&"trigger", 1.0)
	tracker.set_input(&"grip", 0.0)
	XRServer.add_tracker(tracker)
	globe._poll_accum = 1.0
	globe._process(0.0)
	check(globe.selected_map == 2, "XR trigger must select the next constellation")
	globe._poll_accum = 1.0
	globe._process(0.0)
	check(globe.selected_map == 2, "Held XR trigger must not repeat")
	tracker.set_input(&"trigger", 0.0)
	tracker.set_input(&"grip", 1.0)
	globe._poll_accum = 1.0
	globe._process(0.0)
	check(globe.spinning, "XR grip must resume the orbit")
	XRServer.remove_tracker(tracker)
	globe.spinning = false
	player.position = Vector3(0, 0.1, 12)
	key.physical_keycode = KEY_E
	globe._unhandled_key_input(key)
	check(globe.selected_map == 2, "Distant inputs must not change the globe")
	# Walk into the outer rail and verify it prevents leaving the platform.
	player.position = Vector3(0, 0.1, 14)
	player.velocity = Vector3.ZERO
	Input.action_press("move_backwards")
	for i in 90:
		await physics_frame
	Input.action_release("move_backwards")
	check(player.position.z < 15.5 and player.is_on_floor(), "Balustrade must stop the player")
	# Recovery remains available if a developer moves the player outside the world.
	player.position = Vector3(0, -10, 0)
	await physics_frame
	await physics_frame
	check(player.position.z > 11 and player.position.y > -1, "Out-of-bounds recovery must return to spawn")
	print("OBSERVATORY CHECKS: ", "PASS" if failures.is_empty() else str(failures), " | static bodies: ", bodies.size())
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
