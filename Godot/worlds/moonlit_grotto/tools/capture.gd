extends SceneTree
## Render a fixed-size image independently of the desktop window manager.
func _initialize() -> void:
	call_deferred("capture")
func capture() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1440,900)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world: Node3D = load("res://worlds/moonlit_grotto/moonlit_grotto.tscn").instantiate()
	viewport.add_child(world)
	world.get_node("PreviewCamera").current = true
	if OS.get_environment("GROTTO_CAPTURE_VIEW") == "overview":
		world.get_node("PreviewCamera").position = Vector3(24,19,29)
		world.get_node("PreviewCamera").look_at(Vector3(0,1,-2))
	var elapsed := OS.get_environment("GROTTO_CAPTURE_SECONDS").to_float()
	await create_timer(elapsed if elapsed > 0 else 3.0).timeout
	await RenderingServer.frame_post_draw
	var path := OS.get_environment("GROTTO_CAPTURE_PATH")
	if path.is_empty():
		path = "/tmp/moonlit-grotto.png"
	viewport.get_texture().get_image().save_png(path)
	print("Captured ",path)
	world.get_node("Waterfall ambience").stop()
	# Let the audio thread consume the stop before destroying the test viewport.
	await create_timer(.2).timeout
	viewport.queue_free()
	await process_frame
	await process_frame
	quit()
