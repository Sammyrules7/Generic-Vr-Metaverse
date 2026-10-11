extends Node3D
## Deterministic, texture-free prairie ravine. Geometry is batched by material.

signal world_build_progress(progress: float)

const SEED := 70926

@export_enum("daylight", "rain", "night") var weather_preset: String = "rain"
var rng := RandomNumberGenerator.new()
var batches: Dictionary = {}
var materials: Dictionary = {}
var trails: Array[PackedVector3Array] = []
var trail_widths: Array[float] = []
var solid_vertices := PackedVector3Array()
var _interactive_load := false
var _build_deadline := 0
var _build_cancelled := false


func cancel_world_preparation() -> void:
	_build_cancelled = true


func height_at(x: float, z: float) -> float:
	var valley := -18.0 * (1.0 - smoothstep(-65.0, -12.0, x))
	var far_bank := 21.0 * (1.0 - smoothstep(-145.0, -95.0, x))
	return valley + far_bank + 0.55 * sin(x * 0.055) * sin(z * 0.06)


func ground(x: float, z: float, lift: float = 0.0) -> Vector3:
	return Vector3(x, height_at(x, z) + lift, z)


func _ready() -> void:
	if not get_meta("defer_world_build", false):
		_build_world()


## Room entry yields between geometry batches; offline previews build immediately.
func prepare_world() -> void:
	_interactive_load = true
	_build_deadline = Time.get_ticks_usec() + 4000
	await _build_world()


func _build_world() -> void:
	rng.seed = SEED
	_palette()
	_lighting()
	_build_trails()
	await _terrain()
	if _build_cancelled:
		return
	_landmarks()
	_weather_station()
	await _build_frame()
	await _vegetation()
	if _build_cancelled:
		return
	await _flush()
	if _build_cancelled:
		return
	$SpawnPoint.position = ground(12, 12, 0.15)
	$SpawnPoint.rotation.y = 0.7
	$SpawnPoint.scale = Vector3.ONE / scale.x
	_boundaries()
	var weather := Node3D.new()
	weather.set_script(load("res://worlds/prairie_crossing/weather.gd"))
	weather.name = "Weather"
	add_child(weather)
	weather.configure(self, weather_preset)
	var control := Node3D.new()
	control.name = "WeatherControl"
	control.set_script(load("res://worlds/prairie_crossing/weather_control.gd"))
	control.position = ground(14, 9)
	add_child(control)


func _build_frame() -> void:
	if _interactive_load and Time.get_ticks_usec() >= _build_deadline:
		await get_tree().process_frame
		_build_deadline = Time.get_ticks_usec() + 4000


func _palette() -> void:
	var colors := {
		"meadow": "929f67", "meadow_light": "97a36c", "meadow_dark": "8d9b63",
		"earth": "b1a180", "gravel": "d8c7a6", "asphalt": "647576", "line": "e8c878",
		"wood": "70624f", "bench": "b7764d", "steel": "596d70", "insulator": "9ec4bd",
		"pine": "385e56", "pine_light": "4c7764", "leaf": "93ab74", "silver": "bbcc9c",
		"grass": "b4b66c", "grass_dark": "7b955b", "flower": "efd392", "stone": "98a5a0",
		"roof": "617779", "house": "e3d5b6", "sign": "eee6cf", "teal": "4c9a91", "slate": "243f3e"
	}
	for key: String in colors:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(colors[key])
		mat.roughness = 0.93
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		materials[key] = mat


func _lighting() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("789ba8")
	sky_mat.sky_horizon_color = Color("d9dfcc")
	sky_mat.ground_bottom_color = Color("7d957f")
	sky_mat.ground_horizon_color = Color("d9dfcc")
	sky_mat.sky_curve = 0.22
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c7dbdc")
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.fog_enabled = true
	env.fog_light_color = Color("b7ceca")
	env.fog_density = 0.0027
	var environment := WorldEnvironment.new()
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.name = "LateAfternoon"
	sun.rotation_degrees = Vector3(-36, -38, 0)
	sun.light_color = Color("fff0cd")
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 100
	add_child(sun)
	# Broad, flattened cloud silhouettes keep the open prairie sky soft.
	var cloud_mat := StandardMaterial3D.new()
	cloud_mat.albedo_color = Color("e3e8dd")
	cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	materials["cloud"] = cloud_mat
	for i in 30:
		var p := Vector3(rng.randf_range(-240, 220), rng.randf_range(75, 105), rng.randf_range(-240, 150))
		for j in 3:
			_ball(p + Vector3(j * 13, rng.randf_range(-2, 2), 0), Vector3(24, 4.5, 12), "cloud")


func _surface(key: String) -> SurfaceTool:
	if not batches.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		batches[key] = st
	return batches[key]


func _triangle(a: Vector3, b: Vector3, c: Vector3, key: String, solid: bool = false) -> void:
	var st := _surface(key)
	var normal := (c - a).cross(b - a).normalized()
	for p in [a, b, c]:
		st.set_normal(normal)
		if key in ["grass", "grass_dark"]:
			st.set_color(Color(1, 1, 1, 1 if p == b else 0))
		st.add_vertex(p)
		if solid:
			solid_vertices.append(p)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, key: String, solid: bool = false) -> void:
	_triangle(a, b, c, key, solid)
	_triangle(a, c, d, key, solid)


func _primitive(mesh: PrimitiveMesh, p: Vector3, scale: Vector3, key: String, basis: Basis = Basis.IDENTITY, solid: bool = false) -> void:
	var transform := Transform3D(basis.scaled_local(scale), p)
	_surface(key).append_from(mesh, 0, transform)
	if solid:
		for v in mesh.get_faces():
			solid_vertices.append(transform * v)


func _box(p: Vector3, size: Vector3, key: String, solid: bool = false, yaw: float = 0.0) -> void:
	_primitive(BoxMesh.new(), p, size, key, Basis(Vector3.UP, yaw), solid)


func _ball(p: Vector3, size: Vector3, key: String) -> void:
	var mesh := SphereMesh.new()
	mesh.radial_segments = 7
	mesh.rings = 3
	mesh.radius = 1
	mesh.height = 2
	_primitive(mesh, p, size, key)


func _beam(a: Vector3, b: Vector3, radius: float, key: String, solid: bool = false) -> void:
	var direction := b - a
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = direction.length()
	mesh.radial_segments = 5
	var basis := Basis(Quaternion(Vector3.UP, direction.normalized()))
	_primitive(mesh, (a + b) / 2, Vector3.ONE, key, basis, solid)


func _terrain() -> void:
	for x in range(-200, 121, 3):
		await _build_frame()
		if _build_cancelled:
			return
		if _interactive_load:
			world_build_progress.emit(0.25 * float(x + 200) / 321.0)
		for z in range(-170, 171, 3):
			var key: String = ["meadow", "meadow_light", "meadow_dark"][int(clampf((sin(x * 0.13) + cos(z * 0.09)) * 0.8 + 1.0, 0, 2))]
			if x < -20 and x > -48:
				key = "earth" if rng.randf() < 0.32 else key
			_quad(ground(x, z), ground(x + 3, z), ground(x + 3, z + 3), ground(x, z + 3), key, x >= -11 and x <= 25 and z >= -21 and z <= 21)


func _path(points: Array[Vector2], width: float, key: String) -> PackedVector3Array:
	var curve := Curve3D.new()
	for i in points.size():
		var prev: Vector2 = points[maxi(0, i - 1)]
		var next: Vector2 = points[mini(points.size() - 1, i + 1)]
		var tangent := (next - prev) * 0.16
		curve.add_point(Vector3(points[i].x, 0, points[i].y), Vector3(-tangent.x, 0, -tangent.y), Vector3(tangent.x, 0, tangent.y))
	curve.bake_interval = 0.8
	var pts := curve.get_baked_points()
	for i in pts.size():
		pts[i] = ground(pts[i].x, pts[i].z, 0.065)
	for i in range(pts.size() - 1):
		var tangent := (pts[i + 1] - pts[maxi(0, i - 1)]).normalized()
		var tangent_next := (pts[mini(pts.size() - 1, i + 2)] - pts[i]).normalized()
		var side := Vector3(-tangent.z, 0, tangent.x).normalized() * width * 0.5
		var side_next := Vector3(-tangent_next.z, 0, tangent_next.x).normalized() * width * 0.5
		var a := pts[i] + side
		var b := pts[i] - side
		var c := pts[i + 1] - side_next
		var d := pts[i + 1] + side_next
		_quad(ground(a.x, a.z, 0.07), ground(b.x, b.z, 0.07), ground(c.x, c.z, 0.07), ground(d.x, d.z, 0.07), key)
		if key == "asphalt" and i % 5 < 3:
			var s := side.normalized() * 0.055
			_quad(pts[i] + s + Vector3.UP * 0.02, pts[i] - s + Vector3.UP * 0.02, pts[i + 1] - s + Vector3.UP * 0.02, pts[i + 1] + s + Vector3.UP * 0.02, "line")
	trails.append(pts)
	trail_widths.append(width)
	return pts


func _build_trails() -> void:
	_path([Vector2(17, 12), Vector2(8, 8), Vector2(1, -1), Vector2(-3, -4)], 2.2, "gravel")
	_path([Vector2(8, 8), Vector2(1, 11), Vector2(-3, 10)], 2.2, "gravel")
	_path([Vector2(17, 65), Vector2(17, 33), Vector2(9, 12), Vector2(11, -10), Vector2(22, -34), Vector2(37, -40), Vector2(53, -21), Vector2(51, 8), Vector2(34, 24), Vector2(17, 33)], 2.5, "gravel")
	_path([Vector2(11, -10), Vector2(-2, -1), Vector2(-12, 13), Vector2(-18, 29), Vector2(-27, 49), Vector2(-35, 52), Vector2(-35, 34), Vector2(-35, 4), Vector2(-42, -7), Vector2(-50, 8), Vector2(-54, 32), Vector2(-66, 45), Vector2(-82, 37), Vector2(-86, -5), Vector2(-85, -90)], 3.2, "asphalt")
	# The bench clearing is the playable pocket; the valley trail is scenery.
	for segment in [[-78, 78]]:
		for z in range(segment[0], segment[1], 4):
			_fence(ground(-8, z), ground(-8, z + 4))
	for x in range(-8, 22, 3):
		_fence(ground(x, -18), ground(x + 3, -18))
		_fence(ground(x, 18), ground(x + 3, 18))
	for z in range(-18, 18, 3):
		_fence(ground(22, z), ground(22, z + 3))
	var path := trails[3]
	for i in range(24, path.size() - 5, 5):
		if path[i].x > -12:
			continue
		var dir := (path[i + 5] - path[i]).normalized()
		var side := Vector3(-dir.z, 0, dir.x).normalized() * 2.0
		_fence(ground(path[i].x + side.x, path[i].z + side.z), ground(path[i + 5].x + side.x, path[i + 5].z + side.z))


func _fence(a: Vector3, b: Vector3) -> void:
	_beam(a, a + Vector3.UP * 1.25, 0.085, "wood", true)
	for h in [0.48, 1.02]:
		_beam(a + Vector3.UP * h, b + Vector3.UP * h, 0.065, "wood", true)


func _pylon(p: Vector3, size: float) -> void:
	var levels := [0.0, 6.0, 13.0, 20.0, 27.0, 33.0, 39.0]
	var widths := [5.0, 3.7, 2.6, 1.7, 1.35, 1.1, 0.65]
	for i in range(levels.size() - 1):
		for j in 4:
			var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
			var a: Vector2 = corners[j]
			var b: Vector2 = corners[(j + 1) % 4]
			var v0 := p + Vector3(a.x * widths[i], levels[i], a.y * widths[i]) * size
			var v1 := p + Vector3(a.x * widths[i + 1], levels[i + 1], a.y * widths[i + 1]) * size
			var v2 := p + Vector3(b.x * widths[i], levels[i], b.y * widths[i]) * size
			var v3 := p + Vector3(b.x * widths[i + 1], levels[i + 1], b.y * widths[i + 1]) * size
			_beam(v0, v1, 0.12 * size, "steel", i == 0)
			_beam(v0, v2, 0.075 * size, "steel")
			_beam(v0, v3, 0.06 * size, "steel")
			_beam(v2, v1, 0.06 * size, "steel")
	for h in [25.0, 32.0, 38.0]:
		for side in [-1.0, 1.0]:
			var tip := p + Vector3(side * 7, h, 0) * size
			_beam(p + Vector3(0, h - 1.7, 0) * size, tip, 0.095 * size, "steel")
			_beam(p + Vector3(0, h + 1, 0) * size, tip, 0.095 * size, "steel")
			_beam(tip, tip - Vector3.UP * 1.8 * size, 0.14 * size, "insulator")
	for x in [-5, 5]:
		for z in [-5, 5]:
			_box(p + Vector3(x, 0.15, z) * size, Vector3(0.9, 0.5, 0.9) * size, "stone", true)


func _landmarks() -> void:
	var towers := [ground(0, -24), ground(-139, -90), ground(82, 92)]
	for p: Vector3 in towers:
		_pylon(p, 1.0)
	for pair in [[0, 1], [0, 2]]:
		for h in [23.2, 30.2, 36.2]:
			for side in [-7, 7]:
				var start: Vector3 = towers[pair[0]] + Vector3(side, h, 0)
				var end: Vector3 = towers[pair[1]] + Vector3(side, h, 0)
				for i in 24:
					var t := float(i) / 24
					var u := float(i + 1) / 24
					_beam(start.lerp(end, t) - Vector3.UP * (sin(t * PI) * 5), start.lerp(end, u) - Vector3.UP * (sin(u * PI) * 5), 0.028, "steel")
	for z in [-4, 10]:
		_bench(ground(-3.5, z), PI / 2)
	_sign(ground(19, 16), "PRAIRIE\nCROSSING", "THE BENCH OVERLOOK")
	_sign(ground(-5, -12), "RAVINE OVERLOOK", "STAY A LITTLE WHILE")
	# Small homes along the opposite ridge, as in the reference photographs.
	for i in 12:
		var p := ground(-153 - rng.randf_range(0, 14), -125 + i * 21)
		_box(p + Vector3(0, 1.6, 0), Vector3(7, 3.2, 5), "house")
		_box(p + Vector3(0, 3.35, 0), Vector3(8, 0.4, 6), "roof")
		for z in [-1.5, 1.5]:
			_box(p + Vector3(3.51, 1.9, z), Vector3(0.03, 1.15, 1.25), "teal")


func _weather_station() -> void:
	var p := ground(14, 9)
	for x in [-1.1, 1.1]:
		_box(p + Vector3(x, 0.9, 0), Vector3(0.12, 1.8, 0.12), "wood", true)
	_box(p + Vector3(0, 1.7, 0), Vector3(2.9, 1.0, 0.16), "slate", true)
	_box(p + Vector3(0, 2.23, 0), Vector3(3.05, 0.08, 0.28), "wood")


func _bench(p: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	for x in [-1.0, 1.0]:
		_box(p + basis * Vector3(x, 0.35, 0), Vector3(0.12, 0.7, 0.75), "steel", true, yaw)
	for z in [-0.25, 0.0, 0.25]:
		_box(p + basis * Vector3(0, 0.65, z), Vector3(2.6, 0.1, 0.2), "bench", true, yaw)
	for y in [0.98, 1.23]:
		_box(p + basis * Vector3(0, y, 0.36), Vector3(2.6, 0.19, 0.09), "bench", true, yaw)
	for x in [-1, 1]:
		_beam(p + basis * Vector3(x, 0.35, 0.36), p + basis * Vector3(x, 1.36, 0.36), 0.05, "steel")


func _sign(p: Vector3, title: String, subtitle: String) -> void:
	_box(p + Vector3(0, 1.25, 0), Vector3(0.13, 2.5, 0.13), "wood", true)
	_box(p + Vector3(0, 2.35, 0), Vector3(2.4, 1.15, 0.14), "teal", true)
	var label := Label3D.new()
	label.text = title
	label.font_size = 52
	label.pixel_size = 0.006
	label.position = p + Vector3(0, 2.47, 0.081)
	label.modulate = Color("fff1d3")
	label.outline_size = 0
	add_child(label)
	var small := Label3D.new()
	small.text = subtitle
	small.font_size = 24
	small.pixel_size = 0.0035
	small.position = p + Vector3(0, 1.97, 0.081)
	small.outline_size = 0
	add_child(small)


func _near_trail(p: Vector3, margin: float) -> bool:
	if Vector2(p.x - 14, p.z - 9).length() < 1.8 + margin:
		return true
	for z in [-4, 10]:
		if Vector2(p.x + 3.5, p.z - z).length() < 2.0 + margin:
			return true
	for j in trails.size():
		var path := trails[j]
		for i in range(0, path.size(), 3):
			if Vector2(p.x - path[i].x, p.z - path[i].z).length_squared() < pow(trail_widths[j] * 0.5 + margin, 2):
				return true
	return false


func _tree(p: Vector3, size: float, pine: bool) -> void:
	_beam(p, p + Vector3.UP * 4.6 * size, 0.16 * size, "wood")
	if pine:
		for i in 3:
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0
			mesh.bottom_radius = (2.2 - i * 0.45) * size
			mesh.height = 3.8 * size
			mesh.radial_segments = 7
			_primitive(mesh, p + Vector3.UP * (2.8 + i * 1.4) * size, Vector3.ONE, "pine" if i % 2 == 0 else "pine_light")
	else:
		for i in 4:
			_ball(p + Vector3(rng.randf_range(-1.1, 1.1), 3.8 + i * 0.45, rng.randf_range(-1.0, 1.0)) * size, Vector3(1.7, 1.6, 1.6) * size, "silver" if i % 2 == 0 else "leaf")


func _vegetation() -> void:
	for i in 650:
		if i % 8 == 0:
			await _build_frame()
			if _interactive_load:
				world_build_progress.emit(0.25 + 0.2 * float(i) / 650.0)
		if _build_cancelled:
			return
		var x := rng.randf_range(-183, 103)
		var z := rng.randf_range(-155, 155)
		var p := ground(x, z)
		if x > -17 and x < 65 and absf(z) < 70:
			continue
		if _near_trail(p, 2.8):
			continue
		_tree(p, rng.randf_range(0.65, 1.65), rng.randf() < 0.7)
	for p in [Vector2(35, 9), Vector2(44, -7), Vector2(31, -48), Vector2(61, 24), Vector2(-18, -43)]:
		_tree(ground(p.x, p.y), 1.1, false)
	# Thousands of crossed, tapered blades share two meshes rather than nodes.
	for i in 12500:
		if i % 32 == 0:
			await _build_frame()
			if _interactive_load:
				world_build_progress.emit(0.45 + 0.45 * float(i) / 12500.0)
		if _build_cancelled:
			return
		var x := rng.randf_range(-65, 78)
		var z := rng.randf_range(-95, 95)
		var p := ground(x, z, 0.02)
		if _near_trail(p, 0.35) or (x > -6 and x < 6 and z > -30 and z < -18):
			continue
		var h := rng.randf_range(0.25, 0.85)
		var key := "grass" if rng.randf() > 0.4 else "grass_dark"
		for j in 3:
			var angle := rng.randf() * TAU
			var side := Vector3(cos(angle), 0, sin(angle)) * 0.065
			_triangle(p - side, p + Vector3(0.18, h, 0.06), p + side, key)
		if i % 31 == 0:
			_ball(p + Vector3(0, h, 0), Vector3(0.13, 0.08, 0.13), "flower")
	for i in 140:
		if i % 8 == 0:
			await _build_frame()
		if _build_cancelled:
			return
		var p := ground(rng.randf_range(-45, -12), rng.randf_range(-90, 90))
		if not _near_trail(p, 1.2):
			_ball(p + Vector3.UP * 0.65, Vector3(1.2, 1.05, 1.15), "silver")


func _flush() -> void:
	var completed_batches := 0
	for key: String in batches:
		await _build_frame()
		if _build_cancelled:
			return
		if _interactive_load:
			world_build_progress.emit(0.9 + 0.1 * float(completed_batches) / batches.size())
		completed_batches += 1
		var instance := MeshInstance3D.new()
		instance.name = key.to_pascal_case()
		instance.mesh = batches[key].commit()
		instance.material_override = materials[key]
		if key in ["grass", "grass_dark"]:
			var grass_material := ShaderMaterial.new()
			grass_material.shader = load("res://worlds/prairie_crossing/meadow.gdshader")
			grass_material.set_shader_parameter("grass_color", materials[key].albedo_color)
			instance.material_override = grass_material
		if key in ["grass", "grass_dark", "cloud", "flower"]:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
	var body := StaticBody3D.new()
	body.name = "TerrainAndLandmarkCollision"
	var collider := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(solid_vertices)
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	batches.clear()
	solid_vertices.clear()


func _physics_process(_delta: float) -> void:
	var players := get_parent().get_node_or_null("Players")
	if players == null:
		return
	for player in players.get_children():
		if player is CharacterBody3D and player.is_multiplayer_authority():
			var p := to_local(player.global_position)
			if p.y < -5 or p.x < -10 or p.x > 24 or absf(p.z) > 20:
				player.global_transform = $SpawnPoint.global_transform
				player.velocity = Vector3.ZERO


func _boundaries() -> void:
	# Tall blockers above the visible rails keep the scenic ravine out of play,
	# including for desktop jump and room-scale movement near the perimeter.
	var bounds := StaticBody3D.new()
	bounds.name = "OverlookBounds"
	for entry in [
		[Vector3(-8, 3, 0), Vector3(0.25, 8, 36)],
		[Vector3(22, 3, 0), Vector3(0.25, 8, 36)],
		[Vector3(7, 3, -18), Vector3(30, 8, 0.25)],
		[Vector3(7, 3, 18), Vector3(30, 8, 0.25)],
	]:
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = entry[1]
		collider.shape = shape
		collider.position = entry[0]
		bounds.add_child(collider)
	add_child(bounds)
