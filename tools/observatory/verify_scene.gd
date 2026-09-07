extends SceneTree
## Integration checks; --capture also writes three real Godot renders to /tmp.

var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene := load("res://worlds/starlight_observatory/preview.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	var player := scene.get_node("Players/PreviewPlayer") as CharacterBody3D
	var globe := scene.get_node("World/StarGlobe")
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
	globe._process(0.0)
	check(globe.selected_map == 2, "XR trigger must select the next constellation")
	globe._process(0.0)
	check(globe.selected_map == 2, "Held XR trigger must not repeat")
	tracker.set_input(&"trigger", 0.0)
	tracker.set_input(&"grip", 1.0)
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
	print("OBSERVATORY CHECKS: ", "PASS" if failures.is_empty() else failures, " | static bodies: ", bodies.size())
	if "--capture" in OS.get_cmdline_user_args():
		player.set_physics_process(false)
		player.get_node("HUD").visible = false
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1600, 1000)
		viewport.world_3d = scene.get_world_3d()
		viewport.msaa_3d = Viewport.MSAA_4X
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var camera := Camera3D.new()
		camera.fov = 65
		camera.far = 400
		viewport.add_child(camera)
		var shots := [
			["arrival", Vector3(0, 2.0, 12), Vector3(0, 3, -5)],
			["lounge", Vector3(7, 3.6, 7), Vector3(0, 2.5, -3)],
			["overview", Vector3(24, 18, 27), Vector3(0, 1.8, 0)]
		]
		for shot in shots:
			camera.global_position = shot[1]
			camera.look_at(shot[2])
			for i in 12:
				await process_frame
			await RenderingServer.frame_post_draw
			var path := "/tmp/observatory-" + str(shot[0]) + ".png"
			check(viewport.get_texture().get_image().save_png(path) == OK, "Screenshot save failed")
			print("Captured ", path)
		print("Draw calls: ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " | primitives: ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	quit(0 if failures.is_empty() else 1)
