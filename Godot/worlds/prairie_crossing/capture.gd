extends SceneTree
## Capture each weather scene using the same cameras for a fair visual comparison.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.get_node("Networking").set_process(false)
	root.get_node("Networking").ws.close()
	for preset in ["rain", "daylight", "night"]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1440, 900)
		viewport.own_world_3d = true
		viewport.msaa_3d = Viewport.MSAA_4X
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var world := load("res://worlds/prairie_crossing/prairie_crossing.tscn").instantiate() as Node3D
		world.weather_preset = preset
		viewport.add_child(world)
		var camera := Camera3D.new()
		camera.far = 600
		camera.fov = 72
		viewport.add_child(camera)
		for shot in [["arrival", Vector3(17, 3.5, 14), Vector3(-10, 10, -30)], ["bench", Vector3(2, 2.3, 7), Vector3(-60, -1, -27)]]:
			camera.position = world.to_global(shot[1])
			camera.look_at(world.to_global(shot[2]))
			for i in 24:
				await process_frame
			await RenderingServer.frame_post_draw
			var img := viewport.get_texture().get_image()
			img.save_png("/tmp/prairie-" + preset + "-" + shot[0] + ".png")
			if shot[0] == "arrival":
				img.resize(640, 400, Image.INTERPOLATE_LANCZOS)
				var id: String = "prairie_crossing" if preset == "rain" else "prairie_" + preset
				img.save_png("res://worlds/previews/" + id + ".png")
		viewport.free()
	print("PRAIRIE CAPTURE COMPLETE")
	quit()
