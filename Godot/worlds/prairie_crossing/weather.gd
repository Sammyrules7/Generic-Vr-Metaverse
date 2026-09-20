extends Node3D
## Atmospheric variations of the same overlook; all positions are world-local.

var _world: Node3D
var _rng := RandomNumberGenerator.new()


func configure(world: Node3D, preset: String) -> void:
	_world = world
	_rng.seed = 20260820
	if preset == "daylight":
		return
	var environment: Environment
	for child in world.get_children():
		if child is WorldEnvironment:
			environment = child.environment
			break
	if environment == null:
		return
	var sun := world.get_node("LateAfternoon") as DirectionalLight3D
	var sky := environment.sky.sky_material as ProceduralSkyMaterial
	if preset == "rain":
		_rain_lighting(environment, sky, sun)
		_rainfall()
		_puddles()
		_rain_audio()
	elif preset == "night":
		_night_lighting(environment, sky, sun)
		_city_lights()
		_path_lamp(Vector2(17, 11))
		_path_lamp(Vector2(14, -12))
		_path_lamp(Vector2(0, -3))


func _rain_lighting(env: Environment, sky: ProceduralSkyMaterial, sun: DirectionalLight3D) -> void:
	sky.sky_top_color = Color("637783")
	sky.sky_horizon_color = Color("a7babd")
	sky.ground_horizon_color = Color("a7babd")
	sky.ground_bottom_color = Color("647769")
	sun.light_color = Color("c8d9e2")
	sun.light_energy = 0.32
	sun.shadow_enabled = false
	env.ambient_light_color = Color("a9c1cc")
	env.ambient_light_energy = 0.56
	env.fog_light_color = Color("92a9ad")
	env.fog_density = 0.005
	_world.materials["cloud"].albedo_color = Color("929fa5")
	for key in ["gravel", "asphalt", "earth", "wood", "bench", "stone"]:
		var material: StandardMaterial3D = _world.materials[key]
		material.albedo_color = material.albedo_color.darkened(0.18)
		material.roughness = 0.38


func _night_lighting(env: Environment, sky: ProceduralSkyMaterial, sun: DirectionalLight3D) -> void:
	sky.sky_top_color = Color("07132b")
	sky.sky_horizon_color = Color("354254")
	sky.ground_horizon_color = Color("354254")
	sky.ground_bottom_color = Color("0a1523")
	sky.sky_energy_multiplier = 0.6
	sun.rotation_degrees = Vector3(-27, -125, 0)
	sun.light_color = Color("849fdb")
	sun.light_energy = 0.18
	sun.shadow_enabled = false
	env.ambient_light_color = Color("7189b5")
	env.ambient_light_energy = 0.24
	env.fog_light_color = Color("172238")
	env.fog_density = 0.0022
	env.glow_enabled = true
	env.glow_intensity = 0.65
	env.glow_hdr_threshold = 1.0
	_world.materials["cloud"].albedo_color = Color("15233b")
	_world.materials["steel"].albedo_color = Color("28353e")
	# Text remains readable without floating white signs illuminating the landscape.
	for child in _world.get_children():
		if child is Label3D:
			child.modulate = Color("919baa")


func _rainfall() -> void:
	# Native world-space rain is visible in both headset eyes and on desktop.
	var rain := CPUParticles3D.new()
	rain.name = "OverlookRain"
	rain.amount = 1400
	rain.lifetime = 1.6
	rain.preprocess = 1.6
	rain.local_coords = true
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(19, 0.25, 21)
	rain.position = Vector3(7, 14, 0)
	rain.direction = Vector3(-0.12, -1, 0.025)
	rain.spread = 3.0
	rain.gravity = Vector3(0, -2.5, 0)
	rain.initial_velocity_min = 9.0
	rain.initial_velocity_max = 12.0
	rain.scale_amount_min = 0.7
	rain.scale_amount_max = 1.15
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.012, 0.34, 0.012)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.66, 0.8, 0.86, 0.34)
	mesh.material = material
	rain.mesh = mesh
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain)


func _puddles() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float rings = sin(radius * 58.0 - TIME * 4.5);
	float pulse = (1.0 - smoothstep(0.1, 1.0, radius)) * 0.018;
	ALBEDO = vec3(0.25, 0.35, 0.38) + rings * pulse;
	ROUGHNESS = 0.13;
	METALLIC = 0.18;
	NORMAL_MAP = vec3(0.5 + p.x * rings * pulse, 0.5 + p.y * rings * pulse, 1.0);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	for entry in [Vector4(9.2, 9.0, 0.85, 1.4), Vector4(9.3, 1.0, 0.7, 1.2), Vector4(10.5, -8.0, 0.65, 1.0), Vector4(12.1, 16.0, 0.8, 1.25)]:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var center: Vector3 = _world.ground(entry.x, entry.y, 0.082)
		for i in 18:
			var a := float(i) * TAU / 18.0
			var b := float(i + 1) * TAU / 18.0
			for uv in [Vector2.ZERO, Vector2(sin(b), cos(b)), Vector2(sin(a), cos(a))]:
				var x: float = center.x + uv.x * entry.z
				var z: float = center.z + uv.y * entry.w
				surface.set_uv(uv * 0.5 + Vector2.ONE * 0.5)
				surface.set_normal(Vector3.UP)
				surface.add_vertex(_world.ground(x, z, 0.082))
		var puddle := MeshInstance3D.new()
		puddle.name = "RainPuddle"
		puddle.mesh = surface.commit()
		puddle.material_override = material
		puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(puddle)


func _glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


func _city_lights() -> void:
	# Batched emissive windows read as distant lights without costly point lights.
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.35, 0.3, 0.45)
	mesh.material = _glow_material(Color("ffcf86"), 3.2)
	mesh.material.vertex_color_use_as_albedo = true
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_colors = true
	instances.mesh = mesh
	instances.instance_count = 230
	for i in instances.instance_count:
		var p: Vector3
		if i < 95:
			p = _world.ground(_rng.randf_range(-168, -148), _rng.randf_range(-140, 145), _rng.randf_range(2.0, 4.0))
		else:
			p = _world.ground(_rng.randf_range(-35, 60), _rng.randf_range(-166, -148), _rng.randf_range(4.0, 9.0))
		var size := _rng.randf_range(0.5, 1.5)
		instances.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), p))
		instances.set_instance_color(i, Color("aec9e8") if i % 9 == 0 else Color.WHITE * _rng.randf_range(0.6, 1.0))
	var lights := MultiMeshInstance3D.new()
	lights.name = "DistantNeighborhoodLights"
	lights.multimesh = instances
	lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lights)


func _path_lamp(point: Vector2) -> void:
	var p: Vector3 = _world.ground(point.x, point.y)
	var post := MeshInstance3D.new()
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.075
	post_mesh.bottom_radius = 0.10
	post_mesh.height = 1.05
	post_mesh.radial_segments = 6
	post.mesh = post_mesh
	post.material_override = _world.materials["steel"]
	post.position = p + Vector3.UP * 0.525
	add_child(post)
	var lens := MeshInstance3D.new()
	var lens_mesh := CylinderMesh.new()
	lens_mesh.top_radius = 0.11
	lens_mesh.bottom_radius = 0.11
	lens_mesh.height = 0.12
	lens_mesh.radial_segments = 6
	lens.mesh = lens_mesh
	lens.material_override = _glow_material(Color("ffcc87"), 1.1)
	lens.position = p + Vector3.UP * 0.99
	add_child(lens)
	var light := OmniLight3D.new()
	light.position = p + Vector3.UP * 1.1
	light.light_color = Color("ffcd93")
	light.light_energy = 0.8
	light.omni_range = 6
	light.shadow_enabled = false
	add_child(light)


func _rain_audio() -> void:
	# Quiet filtered noise, generated once with a seamless loop and no asset download.
	var sample_rate := 22050
	var count := sample_rate * 6
	var samples := PackedFloat32Array()
	samples.resize(count)
	var noise_rng := RandomNumberGenerator.new()
	noise_rng.seed = 70626
	var filtered := 0.0
	for i in count:
		filtered = lerpf(filtered, noise_rng.randf_range(-1.0, 1.0), 0.32)
		samples[i] = filtered * 0.45
	var overlap := sample_rate / 4
	for i in overlap:
		var t := float(i) / float(overlap)
		samples[count - overlap + i] = lerpf(samples[count - overlap + i], samples[i], t)
	var data := PackedByteArray()
	data.resize((count - overlap) * 2)
	for i in count - overlap:
		data.encode_s16(i * 2, int(samples[i + overlap] * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = count - overlap
	var audio := AudioStreamPlayer.new()
	audio.name = "SoftRainAmbience"
	audio.stream = stream
	audio.volume_db = -19
	add_child(audio)
	audio.play()
