extends SceneTree
## Visual smoke check, not a unit test. Run with a graphical renderer and XR off.
func _initialize() -> void:
	call_deferred("render")

func render() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1440, 900)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene: Node3D = load("res://worlds/briarwick_manor/briarwick_manor.tscn").instantiate()
	viewport.add_child(scene)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.fov = 78
	camera.current = true
	var views := {
		"library": [Vector3(-4.5, 1.8, -2), Vector3(-8, 1.7, -9)],
		"hall": [Vector3(1.7, 1.75, 8), Vector3(-0.5, 2, -6)],
		"dining": [Vector3(-4.5, 1.75, 1.5), Vector3(-8, 1.4, 7)],
		"gallery": [Vector3(4.5, 1.75, -1.5), Vector3(9, 2, -8)],
		"parlour": [Vector3(4.5, 1.75, 1.5), Vector3(9, 1.3, 8)],
		"doorway": [Vector3(0, 1.75, -7.5), Vector3(-7, 1.75, -7.5)]
	}
	for title: String in views:
		camera.position = views[title][0]
		camera.look_at(views[title][1])
		for frame in range(8):
			await process_frame
		await RenderingServer.frame_post_draw
		var shot := viewport.get_texture().get_image()
		shot.save_png("/tmp/briarwick-" + title + ".png")
		if title == "library":
			shot.save_png("res://worlds/briarwick_manor/preview.png")
	# Exercise furnishings through desktop input with the actual player controls.
	var player = load("res://player/network_player.tscn").instantiate()
	scene.add_child(player)
	player.motor.set_physics_process(false)
	var eye: Camera3D = player.controls.head
	camera.current = false
	eye.current = true
	eye.fov = 68
	var objects := [
		scene.get_node("Library").find_child("CandleStick_Triple_*", false, false),
		scene.get_node("Architecture").find_child("WindowDressing*", false, false),
		scene.get_node("WinterGallery/ClockworkOrrery"),
		scene.get_node("GuestParlour/MusicBoxControl")
	]
	for object: Node3D in objects:
		var point: Vector3 = object.get_node("TouchPoint").global_position
		var offset := Vector3(0, 0.5, 1.35)
		if object.action == 1:
			offset = object.global_basis * Vector3(0, 0.35, 1.35)
		eye.global_position = point + offset
		eye.look_at(point)
		await physics_frame
		for state in ["before", "after"]:
			if state == "after":
				var key := InputEventKey.new()
				key.physical_keycode = KEY_F
				key.pressed = true
				viewport.push_input(key)
				key = InputEventKey.new()
				key.physical_keycode = KEY_F
				viewport.push_input(key)
			# Let the curtain tween and extinguishing smoke become visible.
			await create_timer(0.8).timeout
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png("/tmp/briarwick-interaction-%d-%s.png" % [object.action, state])
		print("Furnishing ", object.name, " active after F: ", object.active)
	viewport.queue_free()
	for frame in range(8):
		await process_frame
	# Audio playback releases are queued to the mixer thread. Allow its next
	# update before quitting, including when this utility runs without vsync.
	await create_timer(0.2).timeout
	print("Briarwick: room previews and four desktop interactions captured.")
	quit()
