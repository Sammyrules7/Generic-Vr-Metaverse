extends SceneTree
## Authoring tool only. The saved scene has no dependency on this builder at runtime.
## Running this again replaces the authored scene; edit the .tscn directly afterwards.
const BASE := "res://worlds/briarwick_manor/"
var manor: Node3D
var serial := 0
var collision_cache: Dictionary = {}
var wood := StandardMaterial3D.new()
var gold := StandardMaterial3D.new()
var carpet := StandardMaterial3D.new()

func _initialize() -> void:
	call_deferred("build")

func add(node: Node, parent: Node, title: String) -> Node:
	node.name = title
	parent.add_child(node, true)
	node.owner = manor
	return node

func group(title: String) -> Node3D:
	return add(Node3D.new(), manor, title)

func mark(title: String, pos: Vector3, parent: Node = null) -> Marker3D:
	var node := Marker3D.new()
	add(node, manor if parent == null else parent, title)
	node.position = pos
	return node

func model(asset: String, pos: Vector3, parent: Node, yaw := 0.0, size := Vector3.ONE, solid := false) -> Node3D:
	var category := "village" if asset.begins_with("Wall_") or asset.begins_with("Floor_") or asset.begins_with("Window_") or asset.begins_with("DoorFrame_") or asset.begins_with("Prop_") or asset.begins_with("Roof_") else "props"
	var node := Node3D.new()
	serial += 1
	add(node, parent, asset + "_%03d" % serial)
	node.position = pos
	node.rotation.y = deg_to_rad(yaw)
	node.scale = size
	var imported: Node3D = load(BASE + "assets/" + category + "/" + asset + ".gltf").instantiate()
	add(imported, node, "Model")
	if solid:
		for mesh: MeshInstance3D in imported.find_children("*", "MeshInstance3D", true, false):
			var body := StaticBody3D.new()
			add(body, node, "Collision")
			body.transform = imported.transform * mesh.transform
			var shape := CollisionShape3D.new()
			if not collision_cache.has(mesh.mesh):
				collision_cache[mesh.mesh] = mesh.mesh.create_trimesh_shape()
			shape.shape = collision_cache[mesh.mesh]
			add(shape, body, "Shape")
	return node

func box(title: String, pos: Vector3, size: Vector3, material: Material, parent: Node, solid := false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.add_uv2 = true
	node.mesh = mesh
	node.material_override = material
	node.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	add(node, parent, title)
	node.position = pos
	if solid:
		var body := StaticBody3D.new()
		add(body, node, "Collision")
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		add(collision, body, "Shape")
	return node

func lamp(pos: Vector3, parent: Node, energy := 1.4, color := Color(1.0, 0.72, 0.4), radius := 7.0, shadows := false) -> OmniLight3D:
	var light := OmniLight3D.new()
	add(light, parent, "Candlelight")
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.shadow_enabled = shadows
	light.shadow_blur = 2.0
	light.light_size = 0.18
	light.light_bake_mode = Light3D.BAKE_STATIC
	return light

func chandelier(pos: Vector3, parent: Node) -> void:
	model("Chandelier", pos, parent, 0, Vector3.ONE * 1.2)
	lamp(pos - Vector3(0, 1.7, 0), parent, 1.7, Color(1, 0.76, 0.49), 8, true)

func rug(pos: Vector3, size: Vector2, parent: Node) -> void:
	box("WovenBorder", pos, Vector3(size.x, 0.016, size.y), gold, parent)
	box("VelvetRunner", pos + Vector3(0, 0.01, 0), Vector3(size.x - 0.14, 0.012, size.y - 0.14), carpet, parent)
	for x in [-1, 1]:
		box("FineBorder", pos + Vector3(x * (size.x / 2 - 0.22), 0.018, 0), Vector3(0.025, 0.008, size.y - 0.4), gold, parent)

func wall(pos: Vector3, yaw: float, kind: String, parent: Node) -> void:
	model("Wall_Plaster_" + kind, pos, parent, yaw, Vector3.ONE * 1.5, true)
	if kind == "Window_Wide_Round":
		model("Window_Wide_Round1", pos, parent, yaw, Vector3.ONE * 1.5)
		# A solid pane blocks players and thrown/dropped items without filling the arch.
		var body := StaticBody3D.new()
		add(body, parent, "WindowBarrier")
		body.position = pos + Vector3(0, 2.6, 0)
		body.rotation.y = deg_to_rad(yaw)
		var shape := CollisionShape3D.new()
		var bounds := BoxShape3D.new()
		bounds.size = Vector3(1.75, 2.8, 0.12)
		shape.shape = bounds
		add(shape, body, "Pane")
		var offset := Vector3(0, 2.8, 0.8).rotated(Vector3.UP, deg_to_rad(yaw))
		lamp(pos + offset, parent, 0.5, Color(0.39, 0.61, 1.0), 4.5)
	elif kind == "Door_Round":
		model("DoorFrame_Round_WoodDark", pos, parent, yaw, Vector3.ONE * 1.5)

func sound(file: String, pos: Vector3, volume: float, parent: Node) -> void:
	var player := AudioStreamPlayer3D.new()
	add(player, parent, file)
	var stream: AudioStreamWAV = load("res://worlds/blackthorn_house/audio/" + file + ".wav").duplicate()
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	player.stream = stream
	player.position = pos
	player.volume_db = volume
	player.unit_size = 2.5
	player.max_distance = 15
	player.autoplay = true

func build() -> void:
	manor = Node3D.new()
	manor.name = "BriarwickManor"
	root.add_child(manor)
	wood.albedo_color = Color("36242e")
	gold.albedo_color = Color("b69457")
	gold.metallic = 0.25
	gold.roughness = 0.65
	carpet.albedo_color = Color("364951")
	carpet.roughness = 1.0
	var shell := group("Architecture")
	var floors := add(Node3D.new(), shell, "Floors")
	var ceilings := add(Node3D.new(), shell, "Ceilings")
	for x in range(8):
		for z in range(8):
			var pos := Vector3(-10.5 + x * 3, 0, -10.5 + z * 3)
			var tile := "Floor_Brick" if x in [3, 4] or (x > 4 and z < 4) else "Floor_WoodLight"
			model(tile, pos, floors, 0, Vector3(1.5, 1, 1.5))
			model("Floor_WoodDark", pos + Vector3(0, 4.52, 0), ceilings, 0, Vector3(1.5, 1, 1.5))
	box("Foundation", Vector3(0, -0.18, 0), Vector3(24.4, 0.32, 24.4), wood, shell, true)
	for i in range(8):
		var p := -10.5 + i * 3
		for side in [-1, 1]:
			wall(Vector3(p, 0, side * 12), 0 if side == -1 else 180, "Window_Wide_Round" if i % 2 == 0 else "Straight", shell)
			wall(Vector3(side * 12, 0, p), 90 if side == -1 else -90, "Window_Wide_Round" if i % 2 == 0 else "Straight", shell)
			wall(Vector3(side * 3, 0, p), 90 if side == -1 else -90, "Door_Round" if i in [1, 6] else "Straight", shell)
	for side in [-1, 1]:
		for i in range(3):
			wall(Vector3(side * (4.5 + i * 3), 0, 0), 0, "Door_Round" if i == 1 else "Straight", shell)
		model("Roof_RoundTiles_8x14", Vector3(side * 6, 5.4, 0), shell, 0, Vector3(1.5, 1, 1.75))
	for z in [-9, -3, 3, 9]:
		box("HallCrossbeam", Vector3(0, 4.26, z), Vector3(6, 0.32, 0.28), wood, shell)

	var hall := group("EntranceHall")
	rug(Vector3(0, 0.037, 0), Vector2(2.9, 19.5), hall)
	for z in [-7.0, 0.0, 7.0]:
		chandelier(Vector3(0, 4.4, z), hall)
	model("Table_Large", Vector3(0, 0.025, 10), hall, 0, Vector3(1, 1.15, 1), true)
	model("CandleStick_Triple", Vector3(-0.95, 0.97, 10), hall)
	model("Book_Stack_1", Vector3(0.95, 0.97, 10.05), hall)
	for side in [-1, 1]:
		model("Bench", Vector3(side * 2.35, 0.03, 3.5), hall, side * -90, Vector3.ONE, true)
		model("Vase_4", Vector3(side * 2.2, 0.03, -10.8), hall, 0, Vector3.ONE * 1.6, true)
		model("Prop_Vine1", Vector3(side * 2.4, 4.2, -10.8), hall, side * -90)
	mark("SpawnPoint", Vector3(0, 0.12, 7.8))
	mark("GameTable", Vector3(0, 1.02, 9.8))
	mark("GameDisplay", Vector3(0, 1.00, 9.65)).rotation_degrees = Vector3(-70, 180, 0)

	var library := group("Library")
	rug(Vector3(-7.5, 0.037, -6), Vector2(5.5, 6.5), library)
	for placement in [Vector3(-7.5, 0, -11.6), Vector3(-11.5, 90, -7.5), Vector3(-3.55, -90, -4.5), Vector3(-10.2, 180, -0.45)]:
		var shelf_pos := Vector3(placement.x, 0.03, placement.z)
		var shelf_yaw: float = placement.y
		model("Bookcase_2", shelf_pos, library, shelf_yaw, Vector3.ONE * 1.3, true)
		for y in [0.74, 1.3, 1.86, 2.45]:
			model("BookGroup_Medium_1" if int(y * 10) % 2 else "BookGroup_Medium_2", shelf_pos + Vector3(0, y, 0.04).rotated(Vector3.UP, deg_to_rad(shelf_yaw)), library, shelf_yaw, Vector3.ONE * 1.15)
	model("Table_Large", Vector3(-7.6, 0.03, -6.5), library, 90, Vector3(1.3, 1, 1.2), true)
	for z in [-7.5, -5.5]:
		model("Chair_1", Vector3(-6.45, 0.03, z), library, -90, Vector3.ONE, true)
	model("CandleStick_Triple", Vector3(-7.6, 0.86, -6.5), library)
	model("Book_Stack_1", Vector3(-7.6, 0.86, -7.7), library, 25)
	model("Scroll_1", Vector3(-7.5, 0.86, -5.5), library, 25)
	model("BookStand", Vector3(-10.9, 0.03, -2.8), library, 30, Vector3.ONE, true)
	model("Shelf_Arch", Vector3(-4.25, 1.75, -0.32), library, 180, Vector3.ONE * 1.2)
	chandelier(Vector3(-7.5, 4.4, -5.5), library)

	var dining := group("DiningRoom")
	rug(Vector3(-7.5, 0.037, 6), Vector2(5.5, 7), dining)
	for z in [4.55, 7.45]:
		model("Table_Large", Vector3(-7.5, 0.03, z), dining, 90, Vector3.ONE, true)
		model("CandleStick_Triple", Vector3(-7.5, 0.86, z), dining)
	for z in [3.6, 4.8, 7.2, 8.4]:
		for side in [-1, 1]:
			model("Chair_1", Vector3(-7.5 + side * 1.1, 0.03, z), dining, side * -90, Vector3.ONE, true)
			model("Table_Plate", Vector3(-7.5 + side * 0.36, 0.85, z), dining, 0, Vector3.ONE * 0.8)
			model("Chalice", Vector3(-7.5 + side * 0.34, 0.85, z + 0.24), dining, 0, Vector3.ONE * 0.8)
	for x in [-10.3, -8.3]:
		model("Cabinet", Vector3(x, 0.03, 11.55), dining, 180, Vector3(1.25, 1.2, 1.4), true)
		model("Bottle_1", Vector3(x, 1.25, 11.5), dining)
	chandelier(Vector3(-7.5, 4.4, 6), dining)

	var gallery := group("WinterGallery")
	for z in [-9.5, -3.2]:
		model("Bench", Vector3(8, 0.03, z), gallery, 90, Vector3.ONE * 1.15, true)
	for z in [-10.5, -4.5]:
		model("Vase_4", Vector3(10.9, 0.03, z), gallery, 0, Vector3.ONE * 1.8, true)
		model("Prop_Vine4", Vector3(11.7, 3.95, z), gallery, -90, Vector3.ONE * 1.5)
	for x in [4.8, 8.7]:
		model("Prop_Vine1", Vector3(x, 4.25, -11.75), gallery, 0, Vector3.ONE * 1.3)
	model("Table_Large", Vector3(5, 0.03, -4), gallery, 90, Vector3.ONE, true)
	model("SmallBottles_1", Vector3(5, 0.86, -4), gallery)
	model("Vase_2", Vector3(5, 0.86, -5), gallery)
	chandelier(Vector3(7.5, 4.4, -6), gallery)

	var parlour := group("GuestParlour")
	rug(Vector3(7.5, 0.037, 6), Vector2(5.5, 6.5), parlour)
	model("Bed_Twin1", Vector3(9.8, 0.03, 9.7), parlour, 180, Vector3.ONE, true)
	model("Nightstand_Shelf", Vector3(7.9, 0.03, 10.6), parlour, 180, Vector3.ONE, true)
	model("Chest_Wood", Vector3(10, 0.03, 7.5), parlour, 0, Vector3.ONE, true)
	model("Table_Large", Vector3(7, 0.03, 3.5), parlour, 0, Vector3.ONE, true)
	model("Chair_1", Vector3(7, 0.03, 4.5), parlour, 180, Vector3.ONE, true)
	model("Mug", Vector3(6.5, 0.86, 3.5), parlour)
	model("Book_7", Vector3(7.2, 0.86, 3.5), parlour, 15)
	model("CandleStick_Triple", Vector3(8.15, 0.86, 3.5), parlour)
	model("Shelf_Small_Bottles", Vector3(3.4, 1.6, 3), parlour, 90)
	chandelier(Vector3(7.5, 4.4, 6), parlour)
	# A quietly abandoned place setting; no exposition or floating labels.
	model("Bag", Vector3(8.05, 0.03, 9.4), parlour)
	model("Scroll_1", Vector3(9.8, 0.87, 9.7), parlour)

	var outside := group("WindowGardens")
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("69778a")
	var leaves := StandardMaterial3D.new()
	leaves.albedo_color = Color("304e58")
	for side in [-1, 1]:
		box("GardenWall", Vector3(side * 17, 0.7, 0), Vector3(0.4, 1.4, 33), stone, outside)
		box("GardenWall", Vector3(0, 0.7, side * 17), Vector3(33, 1.4, 0.4), stone, outside)
		for p in [-10.5, -4.5, 1.5, 7.5]:
			for pos in [Vector3(side * 15, 0, p), Vector3(p, 0, side * 15)]:
				box("Planter", pos + Vector3(0, 0.4, 0), Vector3(1.6, 0.8, 1.6), stone, outside)
				var shrub := MeshInstance3D.new()
				var mesh := SphereMesh.new()
				mesh.radius = 0.9
				mesh.height = 2.2
				mesh.add_uv2 = true
				shrub.mesh = mesh
				shrub.material_override = leaves
				shrub.gi_mode = GeometryInstance3D.GI_MODE_STATIC
				add(shrub, outside, "ClippedTopiary")
				shrub.position = pos + Vector3(0, 1.65, 0)
	box("GardenGround", Vector3(0, -0.38, 0), Vector3(40, 0.1, 40), leaves, outside)

	var atmosphere := group("Atmosphere")
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("536789")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("a3b8dc")
	env.ambient_light_energy = 0.38
	# Ambient reflections without a live probe: in Godot 4.7 the probe left
	# seven GPU textures allocated even after the world and viewport were freed.
	var reflection_sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("1c293e")
	sky_material.sky_horizon_color = Color("495363")
	sky_material.ground_horizon_color = Color("495363")
	sky_material.ground_bottom_color = Color("30241c")
	reflection_sky.sky_material = sky_material
	reflection_sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = reflection_sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color("67788f")
	env.fog_density = 0.003
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add(world_env, atmosphere, "DuskEnvironment")
	var sun := DirectionalLight3D.new()
	add(sun, atmosphere, "BlueHour")
	sun.rotation_degrees = Vector3(-25, -35, 0)
	sun.light_color = Color("8bafff")
	sun.light_energy = 0.65
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45
	var lightmap := LightmapGI.new()
	add(lightmap, manor, "LightmapGI")
	lightmap.texel_scale = 1.0
	sound("rain", Vector3(11.8, 2, -6), -23, atmosphere)
	sound("gramophone", Vector3(7, 1, 3.5), -26, atmosphere)
	# A small music box gives the existing original waltz a physical source.
	model("Chest_Wood", Vector3(7.7, 0.86, 3.5), parlour, 0, Vector3.ONE * 0.22)
	var particles := CPUParticles3D.new()
	add(particles, atmosphere, "DriftingDust")
	particles.position = Vector3(0, 2.4, 0)
	particles.amount = 60
	particles.lifetime = 16
	particles.preprocess = 12
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(2.8, 1.8, 10)
	particles.gravity = Vector3(0.012, -0.007, 0.008)
	particles.initial_velocity_min = 0.008
	particles.initial_velocity_max = 0.018
	particles.scale_amount_min = 0.008
	particles.scale_amount_max = 0.018
	var dust_mesh := SphereMesh.new()
	dust_mesh.radial_segments = 6
	dust_mesh.rings = 3
	var dust_mat := StandardMaterial3D.new()
	dust_mat.albedo_color = Color(0.9, 0.8, 0.59, 0.28)
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_mesh.material = dust_mat
	particles.mesh = dust_mesh
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var adapter := Node.new()
	adapter.set_script(load("res://game_modes/murder_mystery/murder_map.gd"))
	add(adapter, manor, "MurderMap")
	var spawns := group("GameSpawns")
	var positions := [Vector3(0, 0.12, 5), Vector3(0, 0.12, -5), Vector3(-5, 0.12, -9), Vector3(-10, 0.12, -5), Vector3(-5, 0.12, -2), Vector3(-10, 0.12, 2), Vector3(-5, 0.12, 6), Vector3(-10, 0.12, 9), Vector3(5, 0.12, -9), Vector3(10, 0.12, -7), Vector3(10, 0.12, -1.5), Vector3(5, 0.12, 2), Vector3(10, 0.12, 4), Vector3(5, 0.12, 9), Vector3(0, 0.12, 0), Vector3(0, 0.12, -10)]
	for i in positions.size():
		mark("Guest%02d" % (i + 1), positions[i], spawns)
	var clues := group("ClueSpawns")
	var clue_positions := [Vector3(-7.4, 0.94, -7), Vector3(-10.7, 0.15, -9), Vector3(-4.5, 0.15, -4), Vector3(-9, 0.15, -1.5), Vector3(-7.5, 0.94, 4), Vector3(-7.5, 0.94, 8), Vector3(-10.3, 1.31, 11.4), Vector3(-4.7, 0.15, 3), Vector3(5, 0.94, -3), Vector3(10.5, 0.15, -8), Vector3(4.5, 0.15, -10.5), Vector3(9.8, 0.15, -1.7), Vector3(6, 0.94, 3.5), Vector3(4.5, 0.15, 10), Vector3(11, 0.15, 6), Vector3(9.8, 0.92, 10), Vector3(2, 0.15, -8), Vector3(-2, 0.15, -3), Vector3(2, 0.15, 6), Vector3(-1, 1.04, 10)]
	for i in clue_positions.size():
		mark("Letter%02d" % (i + 1), clue_positions[i], clues)
	var knives := group("KnifeSpawns")
	for pos in [Vector3(-10, 0.15, -3), Vector3(-4.5, 0.15, 10), Vector3(10, 0.15, -10), Vector3(5, 0.15, 6)]:
		mark("HiddenKnife%d" % knives.get_child_count(), pos, knives)
	group("GhostDetails").visible = false
	load(BASE + "decorate_scene.gd").new().decorate(self)
	var packed := PackedScene.new()
	var result := packed.pack(manor)
	if result == OK:
		result = ResourceSaver.save(packed, BASE + "briarwick_manor.tscn")
	print("Briarwick authored scene saved: ", error_string(result), "; kit instances: ", serial)
	manor.queue_free()
	await process_frame
	quit(0 if result == OK else 1)
