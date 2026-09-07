extends Node3D


func _ready() -> void:
	# Shared deterministic geometry keeps the bundled world identical for all peers.
	for index in range(8):
		var angle := TAU * index / 8.0
		var point := Vector3(cos(angle) * 12, 0, sin(angle) * 12)
		_box("Planter%d" % index, point + Vector3(0, 0.35, 0), Vector3(2.8, 0.7, 2.8), Color("#34364e"))
		_box("Trunk%d" % index, point + Vector3(0, 1.5, 0), Vector3(0.35, 2.4, 0.35), Color("#8276a6"))
		var canopy := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 1.5
		sphere.height = 2.4
		canopy.mesh = sphere
		canopy.position = point + Vector3(0, 3.2, 0)
		canopy.material_override = _material(Color("#9b7bbc"))
		add_child(canopy)
		_box("Bench%d" % index, point * 0.65 + Vector3(0, 0.35, 0), Vector3(2, 0.7, 0.8), Color("#697890"))
	for index in range(4):
		var angle := TAU * index / 4.0
		var point := Vector3(cos(angle) * 18, 0, sin(angle) * 18)
		_box("Beacon%d" % index, point + Vector3(0, 1.4, 0), Vector3(0.35, 2.8, 0.35), Color("#73e2c2"), true)
	# Low perimeter walls keep players inside the courtyard.
	_box("NorthWall", Vector3(0, 0.6, -19.8), Vector3(40, 1.2, 0.4), Color("#34364e"))
	_box("SouthWall", Vector3(0, 0.6, 19.8), Vector3(40, 1.2, 0.4), Color("#34364e"))
	_box("EastWall", Vector3(19.8, 0.6, 0), Vector3(0.4, 1.2, 40), Color("#34364e"))
	_box("WestWall", Vector3(-19.8, 0.6, 0), Vector3(0.4, 1.2, 40), Color("#34364e"))


func _material(color: Color, glow := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	material.emission_enabled = glow
	material.emission = color
	return material


func _box(label: String, point: Vector3, dimensions: Vector3, color: Color, glow := false) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.position = point
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	mesh.material = _material(color, glow)
	visual.mesh = mesh
	body.add_child(visual)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = dimensions
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
