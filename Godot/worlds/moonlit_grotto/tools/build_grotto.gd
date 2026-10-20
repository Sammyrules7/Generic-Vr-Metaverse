extends SceneTree
## Deterministic authoring tool; the saved world has no procedural startup cost.
const OUT = "res://worlds/moonlit_grotto/moonlit_grotto.tscn"
var world: Node3D
var rng := RandomNumberGenerator.new()

func _initialize() -> void:
	call_deferred("build")

func put(node: Node, label: String, parent: Node = null) -> Node:
	node.name = label
	(parent if parent else world).add_child(node)
	node.owner = world
	return node

func material(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.75
	if emission > 0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	return mat

func mesh_node(label: String, mesh: Mesh, pos: Vector3, mat: Material, parent: Node = null) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	put(node, label, parent)
	return node

func light_at(label: String, pos: Vector3, color: Color, energy: float, reach: float) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	put(light,label)

func own_descendants(node: Node) -> void:
	for child in node.get_children():
		child.owner = world
		own_descendants(child)

func crystal(pos: Vector3, height: float, mat: Material, tilt: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in range(6):
		var a := float(side)*TAU/6.0
		var b := float(side+1)*TAU/6.0
		var v0 := Vector3(cos(a)*height*.2,-height*.5,sin(a)*height*.2)
		var v1 := Vector3(cos(b)*height*.2,-height*.5,sin(b)*height*.2)
		var v2 := Vector3(cos(a)*height*.17,height*.2,sin(a)*height*.17)
		var v3 := Vector3(cos(b)*height*.17,height*.2,sin(b)*height*.17)
		for vertex in [v0,v1,v2,v1,v3,v2,v2,v3,Vector3(0,height*.5,0)]:
			surface.add_vertex(vertex)
	surface.generate_normals()
	var mesh := surface.commit()
	var node := mesh_node("Moon quartz", mesh, pos + Vector3.UP*height*.5, mat)
	node.rotation = Vector3(tilt, rng.randf_range(0,TAU),tilt*.7)

func particles(label: String, pos: Vector3, box: Vector3, count: int, size: float, tint: Color, velocity: float, kind: String = "ambient") -> void:
	var p := GPUParticles3D.new()
	p.position = pos
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount = count
	p.lifetime = 12.0
	p.preprocess = 12.0
	p.explosiveness = 0.0
	p.randomness = 1.0
	p.visibility_aabb = AABB(Vector3(-20,-15,-25),Vector3(40,40,50))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = box
	process.direction = Vector3(0.3,1.0,0.1)
	process.spread = 75.0
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = velocity*.4
	process.initial_velocity_max = velocity
	process.scale_min = .5
	process.scale_max = 1.4
	# Explicit offsets avoid accidentally changing the second stop after insertion.
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0,.18,.72,1.0])
	fade.colors = PackedColorArray([Color(1,1,1,0),Color.WHITE,Color.WHITE,Color(1,1,1,0)])
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0,0))
	scale_curve.add_point(Vector2(.18,1))
	scale_curve.add_point(Vector2(.72,1))
	scale_curve.add_point(Vector2(1,0))
	var scale_texture := CurveTexture.new()
	scale_texture.curve = scale_curve
	process.scale_curve = scale_texture
	if kind == "fall":
		p.lifetime = 1.8
		p.preprocess = 2.0
		process.direction = Vector3.DOWN
		process.spread = 8.0
		process.gravity = Vector3(0,-4,0)
	elif kind == "splash":
		p.lifetime = 2.0
		p.preprocess = 2.0
		process.direction = Vector3.UP
		process.spread = 65.0
		process.gravity = Vector3(0,-1.8,0)
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	p.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE*size
	var mat := ShaderMaterial.new()
	mat.shader = load("res://worlds/moonlit_grotto/shaders/mote.gdshader")
	mat.set_shader_parameter("tint",tint)
	quad.material = mat
	p.draw_pass_1 = quad
	put(p,label)

func build() -> void:
	rng.seed = 1709
	world = Node3D.new()
	world.name = "MoonlitGrotto"
	root.add_child(world)
	var geology: Node3D = load("res://worlds/moonlit_grotto/models/grotto_geology.glb").instantiate()
	geology.scene_file_path = ""
	put(geology,"Geology")
	var rock_mat := ShaderMaterial.new()
	rock_mat.shader = load("res://worlds/moonlit_grotto/shaders/limestone.gdshader")
	for node in geology.find_children("*","MeshInstance3D",true,false):
		node.material_override = rock_mat
		if not node.name.begins_with("Distant"):
			node.create_trimesh_collision()
	own_descendants(geology)
	var water := PlaneMesh.new()
	water.size = Vector2(24,32)
	water.subdivide_width = 80
	water.subdivide_depth = 80
	var water_mat := ShaderMaterial.new()
	water_mat.shader = load("res://worlds/moonlit_grotto/shaders/water.gdshader")
	water_mat.set_shader_parameter("lagoon",true)
	var pool_surface := mesh_node("Stillwater",water,Vector3(0,-.13,-3),water_mat)
	pool_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ocean := PlaneMesh.new()
	ocean.size = Vector2(2400,2400)
	var ocean_mat := water_mat.duplicate() as ShaderMaterial
	ocean_mat.set_shader_parameter("lagoon",false)
	ocean_mat.set_shader_parameter("deep_color",Color(.014,.034,.065))
	ocean_mat.set_shader_parameter("crest_color",Color(.045,.09,.14))
	var sea_surface := mesh_node("Open sea",ocean,Vector3(0,-2.5,0),ocean_mat)
	sea_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var moon_direction := Vector3(-.38,.48,-.79).normalized()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://worlds/moonlit_grotto/shaders/night_sky.gdshader")
	sky_mat.set_shader_parameter("moon_direction",moon_direction)
	sky.sky_material = sky_mat
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("6387b0")
	environment.ambient_light_energy = .3
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = .65
	environment.fog_enabled = true
	environment.fog_light_color = Color("173048")
	environment.fog_density = .0015
	environment.fog_sky_affect = .12
	var env := WorldEnvironment.new()
	env.environment = environment
	put(env,"Night atmosphere")
	var moonlight := DirectionalLight3D.new()
	moonlight.basis = Basis.looking_at(-moon_direction)
	moonlight.light_color = Color("a1c7ff")
	moonlight.light_energy = .85
	moonlight.light_specular = .3
	moonlight.shadow_enabled = true
	moonlight.directional_shadow_max_distance = 160
	put(moonlight,"Moonlight")
	var moon := SphereMesh.new()
	moon.radius = 29.0
	moon.height = 58.0
	var moon_mat := ShaderMaterial.new()
	moon_mat.shader = load("res://worlds/moonlit_grotto/shaders/moon.gdshader")
	var moon_disc := mesh_node("Moon",moon,moon_direction*900.0,moon_mat)
	# The luminous sky decoration must not eclipse its own directional light.
	moon_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cyan := material(Color("64dce6"),.35)
	var lilac := material(Color("ada4ff"),.35)
	# A tall central cluster provides the focal point, with smaller shoreline echoes.
	for i in range(9):
		var a := float(i)*2.4
		var h := 2.0 if i == 0 else rng.randf_range(.5,1.4)
		crystal(Vector3(sin(a)*float(i)*.16,.4,-7.3+cos(a)*float(i)*.12),h,cyan if i%3 else lilac,rng.randf_range(-.22,.22))
	light_at("Shrine radiance",Vector3(0,2.1,-7),Color("59e9f3"),1.2,9)
	for i in range(12):
		var side := -1.0 if i%2 == 0 else 1.0
		var pos := Vector3(side*rng.randf_range(7.8,9.3),.3,rng.randf_range(-12,7))
		for j in range(3):
			crystal(pos+Vector3(j*.24,0,j*.15),rng.randf_range(.35,1.2),lilac if i%3 == 0 else cyan,.2)
		if i%3 == 0:
			light_at("Shore glow",pos+Vector3.UP,Color("579ea8"),1.3,5)
	# Tiny bioluminescent mushrooms make the shore feel alive.
	var stalk_mat := material(Color("688f9c"))
	var cap_mat := material(Color("4eefd0"),1.3)
	for i in range(65):
		var pos := Vector3(rng.randf_range(5.8,9.3)*(-1 if i%2 else 1),.3,rng.randf_range(-13,9))
		var h := rng.randf_range(.12,.38)
		var stalk := CylinderMesh.new()
		stalk.top_radius = .025
		stalk.bottom_radius = .04
		stalk.height = h
		stalk.radial_segments = 5
		mesh_node("Glowcap stem",stalk,pos+Vector3.UP*h*.5,stalk_mat)
		var cap := SphereMesh.new()
		cap.radius = h*.55
		cap.height = h*.45
		cap.radial_segments = 8
		cap.rings = 4
		mesh_node("Glowcap",cap,pos+Vector3.UP*h,cap_mat)
	# Weathered lanterns guide the arrival and provide a warm color counterpoint.
	var bronze := material(Color("524638"))
	var amber := material(Color("ffc780"),3.0)
	for x in [-3.8,3.8]:
		var foot := CylinderMesh.new()
		foot.top_radius = .22
		foot.bottom_radius = .32
		foot.height = .7
		foot.radial_segments = 8
		mesh_node("Lantern plinth",foot,Vector3(x,.57,6.9),rock_mat)
		var core := CylinderMesh.new()
		core.top_radius = .12
		core.bottom_radius = .12
		core.height = .35
		core.radial_segments = 8
		mesh_node("Lantern flame",core,Vector3(x,1.06,6.9),amber)
		var lid := CylinderMesh.new()
		lid.top_radius = 0
		lid.bottom_radius = .27
		lid.height = .17
		lid.radial_segments = 8
		mesh_node("Lantern hood",lid,Vector3(x,1.31,6.9),bronze)
		light_at("Amber welcome",Vector3(x,1.3,6.9),Color("ffbd73"),1.5,5)
	# Layered ribbons fall behind the altar; each has a distinct flow phase.
	for i in range(3):
		var ribbon := PlaneMesh.new()
		ribbon.orientation = PlaneMesh.FACE_Z
		ribbon.size = Vector2(1.4,7.7)
		ribbon.subdivide_width = 12
		ribbon.subdivide_depth = 48
		var flow := ShaderMaterial.new()
		flow.shader = load("res://worlds/moonlit_grotto/shaders/waterfall.gdshader")
		flow.set_shader_parameter("phase",float(i)*2.1)
		mesh_node("Waterfall curtain",ribbon,Vector3((i-1)*.85,3.85,-9.35+abs(i-1)*.15),flow)
	var altar := CylinderMesh.new()
	altar.top_radius = 1.65
	altar.bottom_radius = 1.9
	altar.height = .28
	altar.radial_segments = 12
	var altar_node := mesh_node("Shrine dais",altar,Vector3(0,.4,-7.3),rock_mat)
	altar_node.create_trimesh_collision()
	own_descendants(altar_node)
	var ripple_mesh := PlaneMesh.new()
	ripple_mesh.size = Vector2(8,7)
	var ripple_mat := ShaderMaterial.new()
	ripple_mat.shader = load("res://worlds/moonlit_grotto/shaders/ripples.gdshader")
	mesh_node("Cascade ripples",ripple_mesh,Vector3(0,-.08,-9.4),ripple_mat)
	particles("Waterfall spray",Vector3(0,.55,-8.95),Vector3(1.6,.1,.35),200,.22,Color(.65,.88,1,.9),2.1,"splash")
	particles("Falling waterfall droplets",Vector3(0,7.5,-9.1),Vector3(1.25,.1,.2),180,.13,Color(.55,.8,1,.85),2.8,"fall")
	particles("Waterfall mist",Vector3(0,.65,-8.9),Vector3(1.8,.4,.7),38,2.8,Color(.35,.65,.8,.42),.25)
	light_at("Cascade silver light",Vector3(0,4.5,-7.5),Color("8dccff"),1.3,10)
	particles("Drifting moon motes",Vector3(0,2,-3),Vector3(9,2,12),150,.09,Color(.3,.85,1,1),.18)
	particles("Pool mist",Vector3(0,.25,-4),Vector3(8,.15,10),24,3.5,Color(.16,.35,.45,.1),.055)
	var waterfall_audio := AudioStreamPlayer3D.new()
	var stream: AudioStreamOggVorbis = load("res://worlds/moonlit_grotto/audio/waterfall.ogg")
	waterfall_audio.stream = stream
	waterfall_audio.position = Vector3(0,2.5,-9.3)
	waterfall_audio.unit_size = 5.0
	waterfall_audio.max_distance = 32
	waterfall_audio.volume_db = -12
	waterfall_audio.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	waterfall_audio.autoplay = true
	put(waterfall_audio,"Waterfall ambience")
	var spawn := Marker3D.new()
	spawn.position = Vector3(0,.5,9)
	put(spawn,"SpawnPoint")
	var camera := Camera3D.new()
	camera.position = Vector3(0,2.8,11.5)
	camera.rotation_degrees.x = -3
	camera.fov = 72
	put(camera,"PreviewCamera")
	world.set_script(load("res://worlds/moonlit_grotto/grotto.gd"))
	var packed := PackedScene.new()
	var result := packed.pack(world)
	if result == OK:
		result = ResourceSaver.save(packed,OUT)
	print("Grotto saved: ",error_string(result),"; nodes: ",world.find_children("*","",true,false).size())
	quit(result)
