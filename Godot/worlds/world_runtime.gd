extends RefCounted
## Runtime-only adjustments: authored lightmaps and desktop settings stay intact.

static func prepare_particles(world: Node3D) -> void:
	# Preprocess simulates seconds of particles in one frame, even after a
	# threaded resource load. Let effects fill naturally instead.
	for type in ["CPUParticles3D", "GPUParticles3D"]:
		for emitter in world.find_children("*", type, true, false):
			emitter.preprocess = 0.0


static func set_xr_mode(world: Node3D, enabled: bool) -> void:
	for node in world.find_children("*", "WorldEnvironment", true, false):
		if node.environment == null:
			continue
		if not node.has_meta("desktop_environment"):
			var current: Environment = node.environment
			# Keep procedural weather's live environment reference when there
			# are no costly effects to change.
			if not (current.ssao_enabled or current.ssil_enabled or current.ssr_enabled or current.volumetric_fog_enabled or current.glow_enabled):
				continue
			node.set_meta("desktop_environment", node.environment)
		var original: Environment = node.get_meta("desktop_environment")
		if enabled:
			var environment := original.duplicate() as Environment
			# Per-eye screen effects remain expensive after baking the lighting.
			environment.ssao_enabled = false
			environment.ssil_enabled = false
			environment.ssr_enabled = false
			environment.volumetric_fog_enabled = false
			environment.glow_enabled = false
			node.environment = environment
		else:
			node.environment = original
	for light in world.find_children("*", "Light3D", true, false):
		if light is DirectionalLight3D:
			if not light.has_meta("desktop_shadow_distance"):
				light.set_meta("desktop_shadow_distance", light.directional_shadow_max_distance)
			var distance: float = light.get_meta("desktop_shadow_distance")
			light.directional_shadow_max_distance = minf(distance, 25.0) if enabled else distance
		elif light.light_bake_mode == Light3D.BAKE_STATIC:
			# Baked lights still shade dynamic avatars. Keep nearby direct light,
			# but cull distant lamps rather than evaluating every room's lights.
			if not light.has_meta("desktop_distance_fade"):
				light.set_meta("desktop_distance_fade", [light.distance_fade_enabled, light.distance_fade_begin, light.distance_fade_length])
			var fade: Array = light.get_meta("desktop_distance_fade")
			if enabled:
				light.distance_fade_enabled = true
				light.distance_fade_begin = minf(fade[1], 16.0) if fade[0] else 16.0
				light.distance_fade_length = minf(fade[2], 8.0)
			else:
				light.distance_fade_enabled = fade[0]
				light.distance_fade_begin = fade[1]
				light.distance_fade_length = fade[2]


static func hide_visuals(world: Node3D) -> Array[GeometryInstance3D]:
	var visuals: Array[GeometryInstance3D] = []
	for node: GeometryInstance3D in world.find_children("*", "GeometryInstance3D", true, false):
		if node.visible:
			visuals.append(node)
			node.hide()
	return visuals


static func wait_for_rendering(tree: SceneTree, still_loading: Callable) -> void:
	# A process frame starts before rendering. Count completed draws instead,
	# and restart the settling window when a frame stalls or pipelines compile.
	# Headless validation has no render loop, so it uses process frames.
	var headless := DisplayServer.get_name() == "headless"
	var stable_frames := 0
	var settled_seconds := 0.0
	var previous := Time.get_ticks_usec()
	var pipelines := _pipeline_count()
	var deadline := previous + 10000000
	while still_loading.is_valid() and still_loading.call() and (stable_frames < 8 or settled_seconds < 0.25):
		await tree.process_frame
		if not headless:
			await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		if now >= deadline:
			push_warning("World rendering did not settle within 10 seconds; ending the loading overlay")
			return
		var elapsed := (now - previous) / 1000000.0
		var current_pipelines := _pipeline_count()
		if elapsed > 0.1 or current_pipelines != pipelines:
			stable_frames = 0
			settled_seconds = 0.0
		else:
			stable_frames += 1
			settled_seconds += elapsed
		previous = now
		pipelines = current_pipelines


static func _pipeline_count() -> int:
	var total := 0
	for metric in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		total += RenderingServer.get_rendering_info(metric)
	return total
