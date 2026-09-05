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
	env.ambient_light_color = Color(0.48, 0.59, 0.8)
	env.ambient_light_energy = 0.22
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.18, 0.26, 0.4)
	env.fog_density = 0.0015
	env.fog_sky_affect = 0.05
	environment.environment = env
	own(environment, world)
	var moonlight := DirectionalLight3D.new()
	moonlight.name = "Moonlight"
	moonlight.rotation_degrees = Vector3(-42, -35, 0)
	moonlight.light_color = Color(0.62, 0.76, 1)
	moonlight.light_energy = 0.25
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
	for location in [Vector3(0, 3.8, 0), Vector3(0, 4.0, -8), Vector3(-8, 3, 5), Vector3(8, 3, 5)]:
		var lamp := OmniLight3D.new()
		lamp.name = "WarmPool"
		lamp.position = location
		lamp.light_color = Color(1, 0.63, 0.31)
		lamp.light_energy = 2.4
		lamp.omni_range = 9
		lamp.shadow_enabled = false
		own(lamp, world)
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
