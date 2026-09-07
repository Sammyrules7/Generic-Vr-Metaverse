extends SceneTree
## Rebuild native, editor-visible world resources after importing the GLB.

var world: Node3D


func own(node: Node, parent: Node) -> Node:
	parent.add_child(node)
	node.owner = world
	return node


func material(color: Color, energy: float = 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.55
	if energy > 0:
		result.emission_enabled = true
		result.emission = color
		result.emission_energy_multiplier = energy
	return result


func sphere(parent: Node, at: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	mesh.radial_segments = 24
	mesh.rings = 12
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	own(node, parent)
	return node


func line(parent: Node, a: Vector3, b: Vector3, mat: Material) -> void:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.009
	mesh.bottom_radius = 0.009
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 6
	node.mesh = mesh
	node.material_override = mat
	node.position = (a + b) / 2
	var direction := (b - a).normalized()
	var x := direction.cross(Vector3.FORWARD).normalized()
	if x.length_squared() < 0.1:
		x = direction.cross(Vector3.RIGHT).normalized()
	node.basis = Basis(x, direction, x.cross(direction).normalized())
	own(node, parent)


func label(parent: Node, node_name: String, text: String, at: Vector3, size: int, color: Color) -> Label3D:
	var node := Label3D.new()
	node.name = node_name
	node.text = text
	node.position = at
	node.font_size = size
	node.pixel_size = 0.006
	node.modulate = color
	node.outline_size = 0
	node.no_depth_test = false
	own(node, parent)
	return node


func lantern(node_name: String, at: Vector3, color: Color, energy: float, radius: float, shadows: bool) -> void:
	var lamp := OmniLight3D.new()
	lamp.name = node_name
	lamp.position = at
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.omni_range = radius
	lamp.omni_attenuation = 1.4
	lamp.shadow_enabled = shadows
	lamp.shadow_bias = 0.1
	lamp.shadow_normal_bias = 1.0
	own(lamp, world)


func motes(node_name: String, at: Vector3, volume: Vector3, color: Color, count: int) -> void:
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.position = at
	particles.amount = count
	particles.lifetime = 14
	particles.preprocess = 3
	particles.fixed_fps = 30
	particles.use_fixed_seed = true
	particles.seed = 47 + count
	particles.visibility_aabb = AABB(-volume - Vector3.ONE * 3, volume * 2 + Vector3.ONE * 6)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = volume
	process.direction = Vector3.UP
	process.spread = 65
	process.gravity = Vector3(0.015, 0.008, 0)
	process.initial_velocity_min = 0.035
	process.initial_velocity_max = 0.12
	process.scale_min = 0.045
	process.scale_max = 0.11
	process.turbulence_enabled = true
	process.turbulence_noise_scale = 2.0
	process.turbulence_noise_strength = 0.25
	process.turbulence_influence_min = 0.08
	process.turbulence_influence_max = 0.18
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0, 0.15, 0.7, 1])
	fade.colors = PackedColorArray([Color(color, 0), color, color, Color(color, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	particles.process_material = process
	var sprite := GradientTexture2D.new()
	sprite.width = 64
	sprite.height = 64
	sprite.fill = GradientTexture2D.FILL_RADIAL
	sprite.fill_from = Vector2(0.5, 0.5)
	sprite.fill_to = Vector2(1, 0.5)
	var halo := Gradient.new()
	halo.offsets = PackedFloat32Array([0, 0.15, 0.5, 1])
	halo.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.22), Color(1, 1, 1, 0)])
	sprite.gradient = halo
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = sprite
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_texture = sprite
	mat.emission_energy_multiplier = 2.0
	var mesh := QuadMesh.new()
	mesh.material = mat
	particles.draw_pass_1 = mesh
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	own(particles, world)


func _initialize() -> void:
	world = Node3D.new()
	world.name = "World"
	world.set_script(load("res://observatory/world.gd"))
	var architecture := load("res://observatory/assets/observatory.glb").instantiate() as Node3D
	architecture.name = "Architecture"
	own(architecture, world)
	var spawn := Marker3D.new()
	spawn.name = "SpawnPoint"
	spawn.position = Vector3(0, 0.12, 12)
	own(spawn, world)
	var environment := WorldEnvironment.new()
	environment.name = "NightAtmosphere"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ShaderMaterial.new()
	sky_material.shader = load("res://observatory/shaders/starlight.gdshader")
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.44, 0.7)
	env.ambient_light_energy = 0.085
	env.ssao_enabled = true
	env.ssao_radius = 0.9
	env.ssao_intensity = 1.8
	env.ssao_power = 1.5
	env.ssao_detail = 0.65
	env.ssao_light_affect = 0.2
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.fog_enabled = true
	env.fog_light_color = Color(0.08, 0.14, 0.24)
	env.fog_density = 0.0018
	env.fog_sky_affect = 0.02
	environment.environment = env
	own(environment, world)
	var moonlight := DirectionalLight3D.new()
	moonlight.name = "Moonlight"
	moonlight.rotation_degrees = Vector3(-28, -55, 0)
	moonlight.light_color = Color(0.49, 0.68, 1)
	moonlight.light_energy = 0.65
	moonlight.shadow_enabled = true
	moonlight.directional_shadow_max_distance = 45
	own(moonlight, world)
	var clouds := MeshInstance3D.new()
	clouds.name = "SeaOfClouds"
	var cloud_plane := PlaneMesh.new()
	cloud_plane.size = Vector2(440, 440)
	clouds.mesh = cloud_plane
	clouds.position.y = -5.5
	var cloud_material := ShaderMaterial.new()
	cloud_material.shader = load("res://observatory/shaders/cloud_sea.gdshader")
	clouds.material_override = cloud_material
	clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	own(clouds, world)
	# Practical light sources create warm islands with dark space between them.
	lantern("GlobeAmberBounce", Vector3(0, 1.38, 0), Color(1, 0.47, 0.15), 3.2, 7, true)
	lantern("GlobeCyanAccent", Vector3(0, 2.8, 0.3), Color(0.16, 0.65, 1), 0.65, 3, false)
	lantern("DomeWarmKey", Vector3(-3.9, 3.5, -10.5), Color(1, 0.55, 0.22), 4.0, 10, true)
	lantern("DomeCoolRim", Vector3(3.8, 3.5, -10.5), Color(0.18, 0.65, 0.8), 1.8, 8, false)
	for location in [Vector3(-10, 1.35, 0), Vector3(10, 1.35, 0), Vector3(-8, 1.35, 9), Vector3(8, 1.35, 9)]:
		lantern("TableLantern", location, Color(1, 0.52, 0.18), 2.2, 5.2, false)
	for i in 12:
		var angle := TAU * i / 12
		lantern("PerimeterLantern", Vector3(cos(angle) * 14.9, 1.38, -sin(angle) * 14.9), Color(1, 0.56, 0.22), 0.85, 3.2, false)
	motes("LoungeFireflies", Vector3(0, 1.0, 0), Vector3(5.5, 0.75, 5.5), Color(1, 0.63, 0.22), 64)
	motes("ObservatoryStardust", Vector3(0, 3.0, -8), Vector3(3.5, 1.5, 3.5), Color(0.25, 0.8, 1), 36)
	label(world, "Welcome", "S T A R L I G H T\nO B S E R V A T O R Y", Vector3(0, 3.8, -3.2), 60, Color(0.93, 0.77, 0.45))
	label(world, "WelcomeSubtitle", "A   Q U I E T   P L A C E   A B O V E   T H E   C L O U D S", Vector3(0, 3.05, -3.2), 17, Color(0.58, 0.77, 0.85))
	label(world, "TelescopePlaque", "02  /  THE OBSERVATORY\nLook a little further.", Vector3(2.5, 1.25, -5.5), 23, Color(0.86, 0.8, 0.63))
	label(world, "TerracePlaque", "03  /  THE OVERLOOK\nStay for a while.", Vector3(-9, 1.4, 2), 23, Color(0.86, 0.8, 0.63))
	var globe := Node3D.new()
	globe.name = "StarGlobe"
	globe.position = Vector3(0, 2.15, 0)
	globe.set_script(load("res://observatory/globe.gd"))
	own(globe, world)
	var orbits := Node3D.new()
	orbits.name = "Orbits"
	own(orbits, globe)
	var gold := material(Color(0.8, 0.49, 0.16), 0.35)
	var stars := material(Color(0.35, 0.86, 1), 3)
	sphere(orbits, Vector3.ZERO, 0.76, material(Color(0.025, 0.09, 0.16)))
	for angles in [Vector3(0, 0, 24), Vector3(90, 0, 0), Vector3(25, 0, 90)]:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.98
		torus.outer_radius = 1.015
		torus.rings = 64
		torus.ring_segments = 8
		ring.mesh = torus
		ring.material_override = gold
		ring.rotation_degrees = angles
		own(ring, orbits)
	var maps := Node3D.new()
	maps.name = "Constellations"
	own(maps, orbits)
	var patterns := [
		[Vector2(-0.48, 0.28), Vector2(-0.18, 0.4), Vector2(0.22, 0.25), Vector2(0.44, -0.05), Vector2(0.18, -0.34), Vector2(-0.3, -0.35), Vector2(-0.48, 0.28)],
		[Vector2(-0.52, 0.22), Vector2(-0.33, -0.25), Vector2(0, 0.31), Vector2(0.33, -0.25), Vector2(0.52, 0.22)],
		[Vector2(-0.55, 0.15), Vector2(0, 0), Vector2(0.5, 0.35), Vector2(0, 0), Vector2(0.05, 0.55), Vector2(0, 0), Vector2(-0.12, -0.52)]
	]
	for i in patterns.size():
		var constellation := Node3D.new()
		constellation.name = "Map" + str(i)
		constellation.visible = i == 0
		own(constellation, maps)
		var last := Vector3.ZERO
		for point: Vector2 in patterns[i]:
			var position := Vector3(point.x, point.y, sqrt(0.83 * 0.83 - point.length_squared()))
			sphere(constellation, position, 0.032, stars)
			if last != Vector3.ZERO:
				line(constellation, last, position, stars)
			last = position
	# A fixed sprinkling of stars on the globe's far side.
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var dust := MultiMeshInstance3D.new()
	dust.name = "GlobeStars"
	var dust_mesh := SphereMesh.new()
	dust_mesh.radius = 0.012
	dust_mesh.height = 0.024
	dust_mesh.radial_segments = 8
	dust_mesh.rings = 4
	dust.multimesh = MultiMesh.new()
	dust.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	dust.multimesh.mesh = dust_mesh
	dust.multimesh.instance_count = 36
	dust.material_override = stars
	for i in 36:
		var point := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * 0.8
		dust.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, point))
	own(dust, orbits)
	label(globe, "Caption", "THE VOYAGER\nE / TRIGGER  ·  constellation\nR / GRIP  ·  pause orbit", Vector3(0, -1.1, 1.4), 22, Color(0.7, 0.89, 1))
	var packed := PackedScene.new()
	var error := packed.pack(world)
	if error == OK:
		error = ResourceSaver.save(packed, "res://observatory/observatory.tscn")
	world.free()
	print("Observatory scene saved: ", error_string(error))
	quit(error)
