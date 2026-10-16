extends Node3D
## Original, editable architectural model. One mesh per finish keeps the manor cheap in VR.
## Dimensions are metres. Game rules live entirely in MurderMap / MurderMystery.
var _surfaces: Dictionary = {}
var _materials: Dictionary = {}
var _collision: StaticBody3D
var _atmosphere: Node3D

func _ready() -> void:
	_material("plaster", Color("303b42"))
	_material("wood", Color("251b1a"))
	_material("oak", Color("765038"))
	_material("edge", Color("b18c57"), 0.4)
	_material("floor", Color("594137"))
	_material("alternate", Color("624b3c"))
	_material("velvet", Color("344e48"))
	_material("rug", Color("633338"))
	_material("paper", Color("baa887"))
	_material("stone", Color("555359"))
	_material("ink", Color("1a252c"))
	_material("book_red", Color("763e35"))
	_material("book_green", Color("405b50"))
	_material("book_blue", Color("3d505e"))
	_material("lamp", Color("ffdb92"), 1.0, 2.2)
	_collision = StaticBody3D.new()
	_collision.name = "ArchitectureCollision"
	add_child(_collision)
	_atmosphere = preload("res://worlds/blackthorn_house/house_atmosphere.gd").new()
	_atmosphere.name = "Atmosphere"
	add_child(_atmosphere)
	_build_shell()
	_build_library()
	_build_lounge()
	_build_dining()
	_build_gallery()
	_build_foyer()
	_atmosphere.build(self)
	_flush_meshes()

func _material(key: String, color: Color, roughness: float = 0.85, glow: float = 0.0) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	if glow > 0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
	_materials[key] = mat
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_surfaces[key] = surface

func _shape(mesh: Mesh, at: Vector3, finish: String, yaw: float = 0.0) -> void:
	_surfaces[finish].append_from(mesh, 0, Transform3D(Basis(Vector3.UP, yaw), at))

func _box(at: Vector3, size: Vector3, finish: String, solid: bool = false, yaw: float = 0.0) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_shape(mesh, at, finish, yaw)
	if solid:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		collision.position = at
		collision.rotation.y = yaw
		_collision.add_child(collision)

func _cylinder(at: Vector3, radius: float, height: float, finish: String, top: float = -1.0) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top < 0 else top
	mesh.height = height
	mesh.radial_segments = 12
	_shape(mesh, at, finish)

func _sphere(at: Vector3, radius: float, finish: String) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	mesh.radial_segments = 12
	mesh.rings = 6
	_shape(mesh, at, finish)

func _flush_meshes() -> void:
	for key: String in _surfaces:
		var mesh: ArrayMesh = _surfaces[key].commit()
		if mesh == null:
			continue
		var instance := MeshInstance3D.new()
		instance.name = "Finish_" + key
		instance.mesh = mesh
		instance.material_override = _materials[key]
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(instance)
	_surfaces.clear()

func _build_shell() -> void:
	_box(Vector3(0, -0.18, 0), Vector3(28, 0.36, 24), "wood", true)
	for x: int in range(28):
		for z: int in range(8):
			_box(Vector3(x - 13.5, 0.005, z * 3 - 10.5), Vector3(0.985, 0.025, 2.985), "floor" if (x + z) % 3 else "alternate")
	_box(Vector3(0, 4.45, 0), Vector3(28, 0.2, 24), "plaster", true)
	for x: float in [-14.0, 14.0]:
		_window_wall(Vector3(x, 0, 0), 24.0, [-8.0, -2.0, 5.0, 9.0], true)
	_window_wall(Vector3(0, 0, -12), 28.0, [-9.0, 0.0, 9.0], false)
	_wall(Vector3(0, 2.2, 12), Vector3(28, 4.4, 0.3))
	# Two spine walls, each with two generous door openings.
	for x: float in [-3.0, 3.0]:
		for segment: Vector2 in [Vector2(-12, -7.5), Vector2(-4.5, 3.5), Vector2(6.5, 12)]:
			_wall(Vector3(x, 2.2, (segment.x + segment.y) / 2), Vector3(0.24, 4.4, segment.y - segment.x))
		for z: float in [-6.0, 5.0]:
			_box(Vector3(x, 3.95, z), Vector3(0.3, 0.9, 3), "plaster", true)
			for offset: float in [-1.55, 1.55]:
				_box(Vector3(x, 1.8, z + offset), Vector3(0.4, 3.6, 0.16), "oak")
			_box(Vector3(x, 3.55, z), Vector3(0.4, 0.18, 3.3), "oak")
	# Side room loops connect without forcing players back through the foyer.
	for side: float in [-1.0, 1.0]:
		_wall(Vector3(side * 5.15, 2.2, 0), Vector3(4.3, 4.4, 0.24))
		_wall(Vector3(side * 12.15, 2.2, 0), Vector3(3.7, 4.4, 0.24))
		_box(Vector3(side * 8.8, 3.95, 0), Vector3(3, 0.9, 0.3), "plaster", true)
		_box(Vector3(side * 8.8, 3.5, 0), Vector3(3.25, 0.18, 0.4), "oak")
		for offset: float in [-1.55, 1.55]:
			_box(Vector3(side * 8.8 + offset, 1.75, 0), Vector3(0.16, 3.5, 0.4), "oak")
	for z: float in [-8.0, -2.0, 5.0, 9.0]:
		_window(Vector3(-13.8, 2.6, z), PI / 2)
		_window(Vector3(13.8, 2.6, z), -PI / 2)
	for x: float in [-9.0, 0.0, 9.0]:
		_window(Vector3(x, 2.6, -11.8), 0)
	# Coffered ceiling beams and room cornices.
	for x: float in [-13.7, -8.5, -3.3, 3.3, 8.5, 13.7]:
		_box(Vector3(x, 4.23, 0), Vector3(0.18, 0.24, 23.7), "wood")
	for z: float in [-11.7, -6.0, 0.0, 6.0, 11.7]:
		_box(Vector3(0, 4.22, z), Vector3(27.7, 0.26, 0.18), "wood")

func _wall(at: Vector3, size: Vector3) -> void:
	_box(at, size, "plaster", true)
	var panel := size
	panel.y = 1.05
	panel.x += 0.04
	panel.z += 0.04
	_box(Vector3(at.x, 0.53, at.z), panel, "wood")
	panel.y = 0.065
	panel.x += 0.035
	panel.z += 0.035
	_box(Vector3(at.x, 1.07, at.z), panel, "edge")
	_box(Vector3(at.x, 0.1, at.z), panel, "oak")
	_box(Vector3(at.x, 4.1, at.z), panel, "oak")

func _window_wall(at: Vector3, length: float, openings: Array, along_z: bool) -> void:
	# Real apertures reveal the garden. Glass keeps the original play bounds sealed.
	var low := 1.44
	var high := 3.79
	for band: Vector2 in [Vector2(0, low), Vector2(high, 4.4)]:
		var size := Vector3(0.3, band.y - band.x, length) if along_z else Vector3(length, band.y - band.x, 0.3)
		_box(at + Vector3(0, (band.x + band.y) * 0.5, 0), size, "plaster", true)
	var cursor := -length * 0.5
	for center: float in openings:
		var end := center - 1.1
		var p := at + (Vector3(0, 2.2, (cursor + end) * 0.5) if along_z else Vector3((cursor + end) * 0.5, 2.2, 0))
		_wall(p, Vector3(0.3, 4.4, end - cursor) if along_z else Vector3(end - cursor, 4.4, 0.3))
		cursor = center + 1.1
	var remaining := length * 0.5 - cursor
	_wall(at + (Vector3(0, 2.2, cursor + remaining * 0.5) if along_z else Vector3(cursor + remaining * 0.5, 2.2, 0)), Vector3(0.3, 4.4, remaining) if along_z else Vector3(remaining, 4.4, 0.3))
	for y: float in [0.53, 1.07]:
		_box(at + Vector3(0, y, 0), Vector3(0.36, 1.05 if y < 1 else 0.07, length) if along_z else Vector3(length, 1.05 if y < 1 else 0.07, 0.36), "wood" if y < 1 else "edge")

func _window(at: Vector3, yaw: float) -> void:
	var yaw_basis := Basis(Vector3.UP, yaw)
	_atmosphere.add_window(at, yaw)
	# Invisible solid pane, distinct from the animated rain shader.
	var pane := CollisionShape3D.new()
	var pane_shape := BoxShape3D.new()
	pane_shape.size = Vector3(2.2, 2.35, 0.08)
	pane.shape = pane_shape
	pane.position = at
	pane.rotation.y = yaw
	_collision.add_child(pane)
	for x: float in [-1.07, 0.0, 1.07]:
		_box(at + yaw_basis * Vector3(x, 0, 0.045), Vector3(0.065, 2.4, 0.09), "wood", false, yaw)
	for y: float in [-1.18, 0.05, 1.18]:
		_box(at + Vector3(0, y, 0), Vector3(2.22, 0.075, 0.12), "oak", false, yaw)
	_box(at + Vector3(0, -1.26, 0), Vector3(2.45, 0.12, 0.38), "stone", false, yaw)

func _rug(at: Vector3, width: float, depth: float) -> void:
	_box(at + Vector3(0, 0.035, 0), Vector3(width, 0.025, depth), "edge")
	_box(at + Vector3(0, 0.05, 0), Vector3(width - 0.15, 0.025, depth - 0.15), "rug")
	_box(at + Vector3(0, 0.065, 0), Vector3(width - 0.5, 0.025, depth - 0.5), "edge")
	_box(at + Vector3(0, 0.08, 0), Vector3(width - 0.56, 0.025, depth - 0.56), "rug")
	for z: float in [-0.25, 0.25]:
		_box(at + Vector3(0, 0.1, z * depth), Vector3(0.35, 0.02, 0.35), "edge", false, PI / 4)

func _table(at: Vector3, width: float, depth: float, height: float = 0.8) -> void:
	_box(at + Vector3(0, height, 0), Vector3(width, 0.13, depth), "oak", true)
	_box(at + Vector3(0, height - 0.14, 0), Vector3(width - 0.14, 0.18, depth - 0.14), "wood")
	for x: float in [-width / 2 + 0.16, width / 2 - 0.16]:
		for z: float in [-depth / 2 + 0.16, depth / 2 - 0.16]:
			_box(at + Vector3(x, height / 2, z), Vector3(0.1, height, 0.1), "wood")
			_box(at + Vector3(x, 0.12, z), Vector3(0.14, 0.1, 0.14), "edge")

func _lamp(at: Vector3, tall: bool = false) -> void:
	var height := 1.4 if tall else 0.42
	_cylinder(at, 0.18, 0.055, "edge")
	_cylinder(at + Vector3(0, height / 2, 0), 0.035, height, "edge")
	_cylinder(at + Vector3(0, height, 0), 0.28, 0.32, "paper", 0.17)
	_cylinder(at + Vector3(0, height - 0.12, 0), 0.245, 0.018, "lamp")
	_light(at + Vector3(0, height - 0.05, 0), Color("ffce89"), 1.0, 4.5)

func _light(at: Vector3, color: Color, energy: float, reach: float) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	light.shadow_enabled = false
	add_child(light)

func _chandelier(at: Vector3) -> void:
	_cylinder(at + Vector3(0, 0.6, 0), 0.025, 1.2, "edge")
	_cylinder(at, 0.2, 0.25, "edge", 0.08)
	for i: int in range(6):
		var angle := i * TAU / 6
		var p := at + Vector3(cos(angle), 0, sin(angle)) * 0.72
		_box((at + p) / 2, Vector3(0.74, 0.035, 0.045), "edge", false, -angle)
		_cylinder(p + Vector3(0, 0.13, 0), 0.055, 0.28, "paper")
		_sphere(p + Vector3(0, 0.3, 0), 0.06, "lamp")
	_light(at, Color("ffcb89"), 1.8, 9)

func _bookshelf(at: Vector3, yaw: float = 0.0) -> void:
	var yaw_basis := Basis(Vector3.UP, yaw)
	_box(at + Vector3(0, 1.5, 0), Vector3(2.6, 3, 0.45), "wood", true, yaw)
	for level: int in range(5):
		_box(at + Vector3(0, 0.3 + level * 0.54, 0) + yaw_basis * Vector3(0, 0, 0.25), Vector3(2.7, 0.09, 0.6), "oak", false, yaw)
		for i: int in range(12):
			var height := 0.3 + fmod(i * 0.073 + level * 0.037, 0.18)
			var p := at + yaw_basis * Vector3(-1.1 + i * 0.2, 0.35 + level * 0.54 + height / 2, 0.29)
			_box(p, Vector3(0.14, height, 0.3), ["book_red", "book_green", "book_blue"][posmod(i + level, 3)], false, yaw)
			_box(p + Vector3(0, height * 0.3, 0) + yaw_basis * Vector3(0, 0, 0.155), Vector3(0.11, 0.018, 0.012), "edge", false, yaw)
	_box(at + Vector3(0, 3.03, 0), Vector3(2.82, 0.16, 0.62), "oak", false, yaw)

func _sofa(at: Vector3, yaw: float = 0.0) -> void:
	var yaw_basis := Basis(Vector3.UP, yaw)
	_box(at + Vector3(0, 0.36, 0), Vector3(2.8, 0.52, 1), "wood", true, yaw)
	_box(at + Vector3(0, 0.85, 0) + yaw_basis * Vector3(0, 0, -0.43), Vector3(2.8, 0.9, 0.25), "velvet", false, yaw)
	for x: float in [-1.27, 1.27]:
		_box(at + yaw_basis * Vector3(x, 0.62, 0), Vector3(0.25, 0.55, 1.05), "velvet", false, yaw)
	for x: float in [-0.77, 0.0, 0.77]:
		_box(at + yaw_basis * Vector3(x, 0.64, 0.02), Vector3(0.74, 0.18, 0.77), "velvet", false, yaw)
		_box(at + yaw_basis * Vector3(x, 0.9, -0.22), Vector3(0.72, 0.52, 0.12), "velvet", false, yaw)

func _chair(at: Vector3, yaw: float = 0.0) -> void:
	var yaw_basis := Basis(Vector3.UP, yaw)
	_box(at + Vector3(0, 0.5, 0), Vector3(0.6, 0.16, 0.65), "velvet", true, yaw)
	_box(at + yaw_basis * Vector3(0, 0.91, -0.26), Vector3(0.62, 0.72, 0.12), "wood", false, yaw)
	_box(at + yaw_basis * Vector3(0, 0.95, -0.18), Vector3(0.44, 0.48, 0.055), "velvet", false, yaw)
	for x: float in [-0.24, 0.24]:
		for z: float in [-0.24, 0.24]:
			_box(at + yaw_basis * Vector3(x, 0.25, z), Vector3(0.075, 0.5, 0.075), "wood", false, yaw)

func _portrait(at: Vector3, yaw: float = 0.0, missing: bool = false) -> void:
	var yaw_basis := Basis(Vector3.UP, yaw)
	_box(at, Vector3(1.45, 1.85, 0.07), "edge", false, yaw)
	_box(at + yaw_basis * Vector3(0, 0, 0.05), Vector3(1.28, 1.68, 0.04), "wood", false, yaw)
	_box(at + yaw_basis * Vector3(0, 0, 0.08), Vector3(1.12, 1.52, 0.025), "ink", false, yaw)
	if missing:
		return
	# Geometric portrait painted into the frame, deliberately anonymous.
	_box(at + yaw_basis * Vector3(0, -0.3, 0.11), Vector3(0.64, 0.65, 0.015), "book_green", false, yaw)
	_box(at + yaw_basis * Vector3(0.02, 0.24, 0.12), Vector3(0.32, 0.44, 0.018), "oak", false, yaw)
	_box(at + yaw_basis * Vector3(0.02, 0.49, 0.14), Vector3(0.4, 0.11, 0.018), "wood", false, yaw)

func _build_library() -> void:
	_rug(Vector3(-8.5, 0, -6), 6.5, 6.5)
	for x: float in [-12.0, -8.8, -5.6]:
		_bookshelf(Vector3(x, 0, -11.5))
	_bookshelf(Vector3(-3.5, 0, -9), -PI / 2)
	_table(Vector3(-9, 0, -6), 3.2, 1.5)
	_chair(Vector3(-9, 0, -7.1))
	_lamp(Vector3(-10.1, 0.88, -6))
	_box(Vector3(-8.8, 0.885, -6), Vector3(0.65, 0.03, 0.42), "paper", false, 0.1)
	_box(Vector3(-8.8, 0.902, -6), Vector3(0.012, 0.008, 0.42), "wood", false, 0.1)
	_sofa(Vector3(-11, 0, -2.5), PI)
	_table(Vector3(-6, 0, -2), 1.0, 0.8, 0.65)
	_cylinder(Vector3(-6, 1.02, -2), 0.16, 0.6, "edge", 0.045)
	_sphere(Vector3(-6, 1.38, -2), 0.27, "book_blue")
	_chandelier(Vector3(-8.5, 3.2, -5.5))

func _build_lounge() -> void:
	_rug(Vector3(-8.5, 0, 6), 7, 6)
	_sofa(Vector3(-8.5, 0, 8.4), PI)
	_sofa(Vector3(-11.2, 0, 5.6), PI / 2)
	_sofa(Vector3(-5.5, 0, 6.8), -PI / 2)
	_table(Vector3(-8.5, 0, 5.8), 2.5, 1.4, 0.48)
	# A quiet chess game, playable space rather than a narrative display.
	for x: int in range(8):
		for z: int in range(8):
			_box(Vector3(-8.85 + x * 0.1, 0.56, 5.45 + z * 0.1), Vector3(0.1, 0.012, 0.1), "paper" if (x + z) % 2 else "wood")
	for p: Vector3 in [Vector3(-8.75, 0.62, 5.55), Vector3(-8.25, 0.62, 5.55), Vector3(-8.55, 0.62, 5.95), Vector3(-8.35, 0.62, 5.85)]:
		_cylinder(p, 0.03, 0.1, "paper", 0.018)
		_sphere(p + Vector3(0, 0.07, 0), 0.03, "paper")
	_lamp(Vector3(-11.4, 0.05, 9), true)
	_lamp(Vector3(-5.2, 0.05, 9.3), true)
	# Static logs and embers; the atmosphere component adds flames and a few sparks.
	_box(Vector3(-8.5, 0.85, 11.3), Vector3(3.6, 1.7, 0.85), "stone", true)
	_box(Vector3(-8.5, 0.78, 10.85), Vector3(2.2, 1.32, 0.06), "ink")
	_box(Vector3(-8.5, 1.75, 11.1), Vector3(4.0, 0.18, 1.1), "oak")
	for i: int in range(5):
		_box(Vector3(-9.2 + i * 0.36, 0.25, 10.73), Vector3(0.25, 0.13, 0.45), "wood", false, i * 0.32)
		_sphere(Vector3(-9.1 + i * 0.3, 0.26, 10.72), 0.055, "lamp")
	_light(Vector3(-8.5, 0.75, 10.3), Color("ff8d45"), 1.4, 5)
	_portrait(Vector3(-8.5, 2.85, 11.76), PI)
	_chandelier(Vector3(-8.5, 3.2, 5.5))

func _build_dining() -> void:
	_rug(Vector3(8.5, 0, -6), 6.0, 7.5)
	_table(Vector3(8.5, 0, -6), 2.4, 4.8)
	for z: float in [-7.6, -6, -4.4]:
		_chair(Vector3(6.7, 0, z), PI / 2)
		_chair(Vector3(10.3, 0, z), -PI / 2)
		for x: float in [7.7, 9.3]:
			_cylinder(Vector3(x, 0.88, z), 0.23, 0.025, "paper")
			_cylinder(Vector3(x, 0.9, z), 0.17, 0.02, "stone")
			_cylinder(Vector3(x + 0.24, 0.95, z - 0.27), 0.055, 0.15, "edge", 0.075)
	for z: float in [-7.1, -4.9]:
		_cylinder(Vector3(8.5, 1.07, z), 0.09, 0.4, "edge", 0.035)
		_cylinder(Vector3(8.5, 1.34, z), 0.045, 0.2, "paper")
		_sphere(Vector3(8.5, 1.48, z), 0.045, "lamp")
	_table(Vector3(8.5, 0, -10.8), 3.6, 0.8)
	_box(Vector3(8.5, 0.45, -10.8), Vector3(3.3, 0.7, 0.7), "wood", true)
	for x: float in [7.45, 8.5, 9.55]:
		_box(Vector3(x, 0.49, -10.42), Vector3(0.91, 0.53, 0.035), "oak")
		_sphere(Vector3(x, 0.57, -10.37), 0.035, "edge")
	_chandelier(Vector3(8.5, 3.1, -6))
	_lamp(Vector3(9.7, 0.88, -10.8))

func _build_gallery() -> void:
	_rug(Vector3(8.5, 0, 6), 3.8, 8.8)
	for z: float in [2.5, 7.8, 10.1]:
		_portrait(Vector3(3.2, 2.4, z), PI / 2, is_equal_approx(z, 7.8))
	for x: float in [6.0, 9.0, 12.0]:
		_portrait(Vector3(x, 2.5, 11.75), PI)
	_table(Vector3(12.5, 0, 2.5), 1.0, 1.0, 0.95)
	_cylinder(Vector3(12.5, 1.32, 2.5), 0.25, 0.6, "stone", 0.18)
	_sphere(Vector3(12.5, 1.81, 2.5), 0.26, "stone")
	_sofa(Vector3(11.8, 0, 6), -PI / 2)
	_lamp(Vector3(12.4, 0.05, 8.8), true)
	_chandelier(Vector3(8.5, 3.2, 5.5))

func _build_foyer() -> void:
	_rug(Vector3(0, 0, 0), 3.6, 17)
	_chandelier(Vector3(0, 3.2, 6))
	_chandelier(Vector3(0, 3.2, -5))
	# Opt-in game table tucked beside the entry; its small interface is supplied by the mode.
	_table(Vector3(0, 0, 10), 2.3, 1.15, 0.78)
	_box(Vector3(0, 0.87, 10), Vector3(1.6, 0.045, 0.75), "velvet")
	_lamp(Vector3(0.85, 0.87, 10))
	for x: float in [-0.32, 0.0, 0.32]:
		_box(Vector3(x, 0.9, 9.9), Vector3(0.19, 0.01, 0.28), "paper", false, x)
	# The mechanism is animated by the atmosphere component.
	_box(Vector3(2.6, 1.25, -1.2), Vector3(0.55, 2.5, 0.8), "wood", true)
	_box(Vector3(2.28, 2.1, -1.2), Vector3(0.05, 0.58, 0.6), "edge")
	_box(Vector3(2.24, 2.1, -1.2), Vector3(0.03, 0.5, 0.52), "paper")
	_box(Vector3(2.28, 0.95, -1.2), Vector3(0.03, 1.3, 0.35), "ink")
	# Entry door and small brass numerals, no lore plaques.
	_box(Vector3(0, 1.6, 11.79), Vector3(2.0, 3.2, 0.12), "wood")
	for x: float in [-0.5, 0.5]:
		for y: float in [0.8, 2.1]:
			_box(Vector3(x, y, 11.7), Vector3(0.78, 1.0, 0.08), "oak")
	_sphere(Vector3(0.75, 1.3, 11.61), 0.06, "edge")
