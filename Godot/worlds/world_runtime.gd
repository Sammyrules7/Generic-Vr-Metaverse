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
