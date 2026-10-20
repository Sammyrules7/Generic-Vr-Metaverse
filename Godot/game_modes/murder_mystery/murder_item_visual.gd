class_name MurderItemVisual
extends Node3D
## Small original mesh props. Their forward direction is -Z, matching aim poses.

var kind := ""


func set_highlighted(enabled: bool) -> void:
	for child in get_children():
		if child is MeshInstance3D and child.material_override is StandardMaterial3D:
			child.material_override.emission_enabled = enabled
			child.material_override.emission = Color("b09b68")
			child.material_override.emission_energy_multiplier = 0.2


func configure(item_kind: String) -> void:
	kind = item_kind
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var steel := _material(Color("79858a"), 0.75)
	var dark := _material(Color("262c30"), 0.65)
	var wood := _material(Color("503a2d"), 0.0)
	match kind:
		"knife":
			_box(Vector3(0.034, 0.035, 0.13), Vector3(0, 0, 0.03), wood)
			_box(Vector3(0.092, 0.022, 0.018), Vector3(0, 0, -0.045), dark)
			var blade := MeshInstance3D.new()
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			var points: Array[Vector3] = [Vector3(-0.026, 0, -0.055), Vector3(0.026, 0, -0.055), Vector3(0, 0, -0.3), Vector3(0, 0.008, -0.055), Vector3(0, -0.008, -0.055)]
			for index in [0, 3, 2, 3, 1, 2, 1, 4, 2, 4, 0, 2, 0, 4, 3, 4, 1, 3]:
				surface.add_vertex(points[index])
			surface.generate_normals()
			blade.mesh = surface.commit()
			blade.material_override = steel
			add_child(blade)
		"gun":
			_box(Vector3(0.045, 0.06, 0.11), Vector3(0, 0.026, -0.015), dark)
			var grip := _box(Vector3(0.043, 0.105, 0.047), Vector3(0, -0.042, 0.045), wood)
			grip.rotation.x = -0.22
			_cylinder(0.027, 0.066, Vector3(0, 0.044, -0.052), steel)
			_cylinder(0.014, 0.15, Vector3(0, 0.058, -0.158), dark)
			_box(Vector3(0.008, 0.012, 0.016), Vector3(0, 0.078, -0.207), steel)
			_box(Vector3(0.008, 0.033, 0.01), Vector3(0, -0.022, -0.049), dark)
			_box(Vector3(0.008, 0.008, 0.055), Vector3(0, -0.036, -0.022), dark)
		"clue":
			var paper := _material(Color("c9bea3"), 0.0)
			_box(Vector3(0.16, 0.006, 0.105), Vector3.ZERO, paper)
			var fold := _box(Vector3(0.09, 0.001, 0.002), Vector3(0.025, 0.004, 0), wood)
			fold.rotation.y = 0.42
			var seal := MeshInstance3D.new()
			var disc := CylinderMesh.new()
			disc.top_radius = 0.012
			disc.bottom_radius = 0.013
			disc.height = 0.004
			disc.radial_segments = 10
			seal.mesh = disc
			seal.position = Vector3(0.015, 0.006, 0)
			seal.material_override = _material(Color("61382f"), 0.0)
			add_child(seal)


func _material(color: Color, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.55
	return material


func _box(size: Vector3, offset: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = offset
	instance.material_override = material
	add_child(instance)
	return instance


func _cylinder(radius: float, length: float, offset: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 12
	instance.mesh = mesh
	instance.rotation.x = PI / 2.0
	instance.position = offset
	instance.material_override = material
	add_child(instance)
