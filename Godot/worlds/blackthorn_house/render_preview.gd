extends SceneTree
## Run: godot --xr-mode off --path Godot --script res://worlds/blackthorn_house/render_preview.gd
func _initialize() -> void:
	call_deferred("_render")

func _render() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1440, 900)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene: Node3D = load("res://worlds/blackthorn_house/blackthorn_house.tscn").instantiate()
	viewport.add_child(scene)
	if not scene.has_node("Finish_plaster"):
		push_error("The manor did not build; refusing to overwrite its preview")
		quit(1)
		return
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(-4.5, 1.85, 1.7)
	camera.look_at(Vector3(-8.7, 1.4, 7.6))
	camera.fov = 85
	camera.current = true
	for frame in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("/tmp/blackthorn-lounge.png")
	viewport.get_texture().get_image().save_png("res://worlds/blackthorn_house/preview.png")
	camera.position = Vector3(-4.2, 1.9, -2.0)
	camera.look_at(Vector3(-9.3, 1.4, -7.8))
	await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("/tmp/blackthorn-library.png")
	camera.position = Vector3(-10.4, 1.65, 3.2)
	camera.look_at(Vector3(-13.8, 2.45, 5.0))
	await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("/tmp/blackthorn-windows.png")
	# Render the real local presentation: the private card must not be public text.
	var players := Node3D.new()
	scene.add_child(players)
	var player = load("res://player/network_player.tscn").instantiate()
	players.add_child(player)
	player.motor.set_physics_process(false)
	player.controls.set_process_unhandled_input(false)
	player.controls.head.current = false
	camera.current = true
	var presentation = load("res://game_modes/murder_mystery/murder_presentation.gd").new()
	scene.add_child(presentation)
	presentation.setup(players, player, scene)
	presentation.apply_snapshot({"phase": "waiting", "self": {"participating": false}, "players": {}, "items": {}})
	camera.position = Vector3(0.15, 1.65, 8.6)
	camera.look_at(Vector3(-0.15, 0.95, 9.93))
	await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("/tmp/blackthorn-guestbook.png")
	camera.position = Vector3(-4.5, 1.85, 1.7)
	camera.look_at(Vector3(-8.7, 1.4, 7.6))
	player.controls.head.global_transform = camera.global_transform
	presentation.apply_snapshot({"phase": "active", "round_id": 1, "remaining": 195.0, "self": {"participating": true, "alive": true, "role": "bystander", "clues": 2}, "players": {}, "items": {}})
	await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("/tmp/blackthorn-card.png")
	presentation.clear()
	viewport.queue_free()
	await process_frame
	await process_frame
	print("Blackthorn previews saved: lounge, library, windows, guestbook, card")
	quit()
