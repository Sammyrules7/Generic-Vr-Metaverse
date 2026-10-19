extends Node3D
## Cosmetic, local-only atmosphere. No round or networking state lives here.
## Particle counts are capped; only the moon and hearth use shadow maps.
var _time := 0.0
var _flicker_accum := 0.0
var _lights: Array[Dictionary] = []
var _pendulum: Node3D
var _minute: Node3D
var _hour: Node3D
var _record: Node3D
var _flames: Array[Node3D] = []
var _glass := ShaderMaterial.new()
var _cloth := ShaderMaterial.new()
var _brass := StandardMaterial3D.new()
var _dark := StandardMaterial3D.new()
var _warm := StandardMaterial3D.new()
var _sound_players: Array[AudioStreamPlayer3D] = []

func _init() -> void:
	_glass.shader = preload("res://worlds/blackthorn_house/rain_glass.gdshader")
	_cloth.shader = preload("res://worlds/blackthorn_house/curtain.gdshader")
	_brass.albedo_color = Color("a08043")
	_brass.metallic = 0.75
	_brass.roughness = 0.36
	_dark.albedo_color = Color("151713")
	_warm.albedo_color = Color("e19440")
	_warm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_warm.emission_enabled = true
	_warm.emission = Color("ff9f39")
	_warm.emission_energy_multiplier = 2.5

func build(house: Node3D) -> void:
	_garden(house)
	_clock()
	_gramophone(house)
	_fireplace()
	for child in house.get_children():
		if child is OmniLight3D:
			_lights.append({"light": child, "energy": child.light_energy, "phase": float(_lights.size()) * 1.74})
	for at: Vector3 in [Vector3(-8.5, 2.3, 5.5), Vector3(-8.5, 2.3, -6), Vector3(8.5, 2.3, -6), Vector3(8.5, 2.3, 5.5), Vector3(0, 2.5, 3)]:
		_particles("DustMotes", at, 28, Vector3(3.8, 1.3, 3.3), Vector3(0.015, 0.006, 0), 0.014, Color(0.76, 0.69, 0.46, 0.25), 13.0)
	_sound("clock", Vector3(2.1, 1.6, -1.2), -15, 8)
	_sound("gramophone", Vector3(-12.2, 1.2, 2.8), -15, 11)
	_sound("fire", Vector3(-8.5, 0.6, 10.5), -20, 7)
	for at: Vector3 in [Vector3(-14, 2, 2), Vector3(14, 2, 2), Vector3(0, 2, -12)]:
		_sound("rain", at, -27, 12)

func add_window(at: Vector3, yaw: float) -> void:
	var frame := Node3D.new()
	frame.name = "RainWindow"
	frame.position = at
	frame.rotation.y = yaw
	add_child(frame)
	var pane := QuadMesh.new()
	pane.size = Vector2(2.12, 2.34)
	_mesh(frame, pane, Vector3.ZERO, _glass)
	# Leaded diamond lights above clear lower panes; an amber jewel in each crest.
	for x: float in [-0.53, 0.53]:
		for y: float in [0.39, 0.82]:
			var center := Vector3(x, y, 0.022)
			var corners: Array[Vector3] = [Vector3(0, 0.22, 0), Vector3(0.30, 0, 0), Vector3(0, -0.22, 0), Vector3(-0.30, 0, 0)]
			for i in 4:
				_segment(frame, center + corners[i], center + corners[(i + 1) % 4], 0.009, _brass)
		var jewel := SphereMesh.new()
		jewel.radius = 0.045
		jewel.height = 0.09
		_mesh(frame, jewel, Vector3(x, 0.82, 0.03), _brass)
	# Continuous folded fabric, with a very small breeze confined to its lower hem.
	for side: float in [-1.0, 1.0]:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for row in 14:
			for col in 12:
				for uv: Vector2 in [Vector2(col, row), Vector2(col + 1, row), Vector2(col, row + 1), Vector2(col + 1, row), Vector2(col + 1, row + 1), Vector2(col, row + 1)]:
					var p := uv / Vector2(12, 14)
					surface.set_uv(Vector2(p.x, 1.0 - p.y))
					surface.add_vertex(Vector3(side * (1.02 + p.x * 0.58), 1.28 - p.y * 2.9, 0.12 + sin(p.x * TAU * 4) * 0.075))
		surface.generate_normals()
		_mesh(frame, surface.commit(), Vector3.ZERO, _cloth)
		_segment(frame, Vector3(side * 1.3, -0.3, 0.19), Vector3(side * 1.42, -0.3, 0.25), 0.036, _brass)
	_segment(frame, Vector3(-1.72, 1.38, 0.12), Vector3(1.72, 1.38, 0.12), 0.024, _brass)
	# Quiet rain falling beyond the pane; particles never cross into the room.
	var rain := _particles("WindowRain", Vector3.ZERO, 30, Vector3(1.8, 1.8, 0.65), Vector3(0.07, -3.0, 0), 0.01, Color(0.42, 0.56, 0.67, 0.3), 1.25)
	rain.reparent(frame, false)
	rain.position = Vector3(0, 0.5, -0.9)
	var drop := BoxMesh.new()
	drop.size = Vector3(0.008, 0.12, 0.008)
	drop.material = rain.mesh.material
	rain.mesh = drop
	var wash := OmniLight3D.new()
	wash.light_color = Color("8aa9d1")
	wash.light_energy = 0.4
	wash.omni_range = 3.5
	frame.add_child(wash)
	wash.position = Vector3(0, -0.25, 0.45)

func _garden(house: Node3D) -> void:
	house._material("garden", Color("172522"))
	house._material("cypress", Color("18262b"))
	house._material("iron", Color("252c34"), 0.45)
	house._box(Vector3(0, -0.42, 0), Vector3(90, 0.18, 90), "garden")
	for side: float in [-1.0, 1.0]:
		for i in range(9):
			var at := Vector3(side * (18.5 + fmod(i * 3.7, 9)), 0, -17 + i * 4.8)
			house._cylinder(at + Vector3(0, 1.5, 0), 0.16, 3, "wood")
			for tier in 3:
				house._cylinder(at + Vector3(0, 2.4 + tier * 1.3, 0), 1.7 - tier * 0.36, 3.4, "cypress", 0.05)
		for z in range(-17, 20, 2):
			house._cylinder(Vector3(side * 17, 1.0, z), 0.035, 2.0, "iron")
			house._cylinder(Vector3(side * 17, 2.07, z), 0.085, 0.23, "iron", 0.0)
		for y: float in [0.65, 1.65]:
			house._box(Vector3(side * 17, y, 1), Vector3(0.055, 0.05, 38), "iron")
	for x in range(-20, 22, 5):
		for tier in 3:
			house._cylinder(Vector3(x, 2.4 + tier * 1.4, -19 - abs(x) * 0.3), 1.6 - tier * 0.3, 3.8, "cypress", 0.0)
	# A distant moon, visible through the side lights; no screens or skybox photos.
	var moon_material := StandardMaterial3D.new()
	moon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	moon_material.albedo_color = Color("d0dce5")
	moon_material.emission_enabled = true
	moon_material.emission = Color("9cabc9")
	var moon := SphereMesh.new()
	moon.radius = 1.7
	moon.height = 3.4
	_mesh(self, moon, Vector3(-39, 13, 12), moon_material)

func _clock() -> void:
	_pendulum = Node3D.new()
	_pendulum.name = "Pendulum"
	add_child(_pendulum)
	_pendulum.position = Vector3(2.21, 1.5, -1.2)
	_segment(_pendulum, Vector3.ZERO, Vector3(0, -0.85, 0), 0.012, _brass)
	var bob := SphereMesh.new()
	bob.radius = 0.115
	bob.height = 0.23
	_mesh(_pendulum, bob, Vector3(0, -0.85, 0), _brass).scale.x = 0.3
	_minute = _clock_hand(0.2, 0.014)
	_hour = _clock_hand(0.14, 0.026)
	for i in 12:
		var angle := i * TAU / 12
		var p := Vector3(2.215, 2.1 + cos(angle) * 0.21, -1.2 + sin(angle) * 0.21)
		var mark := BoxMesh.new()
		mark.size = Vector3(0.015, 0.025, 0.013)
		_mesh(self, mark, p, _dark).rotation.x = -angle

func _clock_hand(length: float, width: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(2.195, 2.1, -1.2)
	add_child(pivot)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.02, length, width)
	_mesh(pivot, mesh, Vector3(0, length * 0.5, 0), _dark)
	return pivot

func _gramophone(house: Node3D) -> void:
	var at := Vector3(-12.2, 0, 2.8)
	house._table(at, 1.35, 0.95, 0.88)
	house._box(at + Vector3(0, 1.0, 0), Vector3(0.9, 0.22, 0.65), "oak")
	house._box(at + Vector3(0, 1.13, 0), Vector3(0.94, 0.045, 0.69), "edge")
	_record = Node3D.new()
	_record.name = "SpinningRecord"
	_record.position = at + Vector3(-0.08, 1.165, 0)
	add_child(_record)
	var disc := CylinderMesh.new()
	disc.top_radius = 0.27
	disc.bottom_radius = 0.27
	disc.height = 0.015
	disc.radial_segments = 40
	_mesh(_record, disc, Vector3.ZERO, _dark)
	var label := CylinderMesh.new()
	label.top_radius = 0.074
	label.bottom_radius = 0.074
	label.height = 0.02
	_mesh(_record, label, Vector3(0, 0.005, 0), _brass)
	var stripe := BoxMesh.new()
	stripe.size = Vector3(0.1, 0.002, 0.008)
	_mesh(_record, stripe, Vector3(0, 0.017, 0), _dark)
	_segment(self, at + Vector3(0.35, 1.16, -0.2), at + Vector3(0.17, 1.21, 0.12), 0.017, _brass)
	_segment(self, at + Vector3(0.17, 1.21, 0.12), at + Vector3(0.05, 1.18, 0.14), 0.02, _dark)
	# Flared, curved brass horn built from rings, with a dark inner bell.
	var horn := SurfaceTool.new()
	horn.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in 12:
		for segment in 24:
			for uv: Vector2 in [Vector2(ring, segment), Vector2(ring + 1, segment), Vector2(ring, segment + 1), Vector2(ring + 1, segment), Vector2(ring + 1, segment + 1), Vector2(ring, segment + 1)]:
				var t := uv.x / 12.0
				var angle := uv.y * TAU / 24
				var radius := 0.035 + pow(t, 2.4) * 0.44
				var center := Vector3(0, t * 0.69, t * t * 0.42)
				horn.add_vertex(center + Vector3(cos(angle) * radius, sin(angle) * radius * 0.75, sin(angle) * radius * -0.66))
	horn.generate_normals()
	var brass := _brass.duplicate() as StandardMaterial3D
	brass.cull_mode = BaseMaterial3D.CULL_DISABLED
	brass.albedo_color = Color("c99a4f")
	brass.metallic = 0.45
	var bell := _mesh(self, horn.commit(), at + Vector3(0.32, 1.18, -0.21), brass)
	bell.rotation.y = PI / 2
	# Small crank on the cabinet side.
	_segment(self, at + Vector3(0.45, 1.0, 0.05), at + Vector3(0.62, 1.0, 0.05), 0.015, _brass)
	_segment(self, at + Vector3(0.62, 1.0, 0.05), at + Vector3(0.62, 1.12, 0.05), 0.015, _brass)
	# A small sconce catches the brass bell without lighting the whole room.
	var sconce := SphereMesh.new()
	sconce.radius = 0.065
	sconce.height = 0.18
	_mesh(self, sconce, Vector3(-13.58, 2.15, 2.8), _warm)
	_segment(self, Vector3(-13.75, 1.93, 2.8), Vector3(-13.55, 1.93, 2.8), 0.035, _brass)
	var light := OmniLight3D.new()
	light.position = Vector3(-12.65, 2.05, 2.9)
	light.light_color = Color("ffd09a")
	light.light_energy = 0.9
	light.omni_range = 2.5
	add_child(light)

func _fireplace() -> void:
	var light := OmniLight3D.new()
	light.position = Vector3(-8.5, 0.65, 10.45)
	light.light_color = Color("ff963a")
	light.light_energy = 1.1
	light.omni_range = 5.5
	light.shadow_enabled = true
	add_child(light)
	_lights.append({"light": light, "energy": 1.1, "phase": 0.0})
	for i in 7:
		var flame := SphereMesh.new()
		flame.radius = 0.065
		flame.height = 0.25 + float(i % 3) * 0.06
		var node := _mesh(self, flame, Vector3(-9.13 + i * 0.21, 0.38, 10.67), _warm)
		_flames.append(node)
	_particles("HearthEmbers", Vector3(-8.5, 0.4, 10.62), 18, Vector3(0.63, 0.08, 0.03), Vector3(0, 0.25, 0), 0.013, Color(1, 0.39, 0.075, 0.75), 2.5)

func _particles(label: String, at: Vector3, count: int, extent: Vector3, velocity: Vector3, size: float, color: Color, lifetime: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = label
	particles.amount = count
	particles.lifetime = lifetime
	particles.preprocess = 0.0
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = extent
	particles.gravity = velocity * 0.04
	particles.direction = velocity.normalized()
	particles.spread = 12.0
	particles.initial_velocity_min = velocity.length() * 0.7
	particles.initial_velocity_max = velocity.length()
	particles.local_coords = true
	var fade := Gradient.new()
	fade.set_color(0, Color(color, 0.0))
	fade.add_point(0.2, color)
	fade.add_point(0.7, color)
	fade.set_color(1, Color(color, 0.0))
	particles.color_ramp = fade
	var mesh := SphereMesh.new()
	mesh.radius = size * 0.5
	mesh.height = size
	mesh.radial_segments = 4
	mesh.rings = 2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	particles.mesh = mesh
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)
	particles.position = at
	return particles

func _sound(file: String, at: Vector3, volume: float, reach: float) -> void:
	var path := "res://worlds/blackthorn_house/audio/" + file + ".wav"
	if not ResourceLoader.exists(path):
		return
	var sound := AudioStreamPlayer3D.new()
	sound.name = file.capitalize() + "Sound"
	sound.stream = load(path)
	if sound.stream is AudioStreamWAV:
		sound.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		sound.stream.loop_end = sound.stream.data.size() / 2
	sound.volume_db = volume
	sound.unit_size = 2.0
	sound.max_distance = reach
	add_child(sound)
	sound.position = at
	sound.play()
	_sound_players.append(sound)

func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	parent.add_child(node)
	node.position = at
	return node

func _segment(parent: Node3D, from: Vector3, to: Vector3, radius: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = from.distance_to(to)
	mesh.radial_segments = 8
	var node := _mesh(parent, mesh, (from + to) * 0.5, material)
	var direction := (to - from).normalized()
	var x := direction.cross(Vector3.FORWARD)
	if x.length_squared() < 0.001:
		x = direction.cross(Vector3.RIGHT)
	x = x.normalized()
	node.basis = Basis(x, direction, x.cross(direction))

func _process(delta: float) -> void:
	_time += delta
	_flicker_accum += delta
	# 15Hz flicker is visually identical, 4x fewer light_energy writes.
	if _flicker_accum < 1.0 / 15.0:
		_update_slow(delta)
		return
	_flicker_accum = 0.0
	for record: Dictionary in _lights:
		var light: OmniLight3D = record.light
		light.light_energy = record.energy * (0.97 + 0.035 * sin(_time * 3.7 + record.phase) + 0.018 * sin(_time * 8.3 + record.phase))
	for i in _flames.size():
		_flames[i].scale = Vector3(1, 0.82 + 0.28 * sin(_time * 7 + i * 2.2), 1)
	_update_slow(delta)


func _update_slow(_delta: float) -> void:
	if is_instance_valid(_pendulum):
		_pendulum.rotation.x = cos(_time * TAU) * 0.13
		_minute.rotation.x = -_time * TAU / 3600.0
		_hour.rotation.x = -PI / 2 - _time * TAU / 43200.0
	if is_instance_valid(_record):
		_record.rotation.y = fmod(_time * TAU * 0.55, TAU)

func _exit_tree() -> void:
	for sound in _sound_players:
		if is_instance_valid(sound):
			sound.stop()
