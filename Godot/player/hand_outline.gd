class_name HandOutline
extends RefCounted
## A shared shader style for the raw hand mesh and controller fallback.
const SHADER := preload("res://player/hand_outline.gdshader")
static var _overlay_shader: Shader

static func material_for(mesh: MeshInstance3D, skeleton: Skeleton3D = null, side := "") -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	if skeleton != null:
		var suffix := "_L" if skeleton.find_bone("Wrist_L") >= 0 else "_R"
		var tips := PackedVector3Array()
		var to_mesh := mesh.global_transform.affine_inverse() * skeleton.global_transform
		for finger in ["Thumb", "Index", "Middle", "Ring", "Little"]:
			var bone := skeleton.find_bone(side + finger + "Tip" if not side.is_empty() else finger + "_Tip" + suffix)
			if bone < 0:
				return material
			tips.append(to_mesh * skeleton.get_bone_global_rest(bone).origin)
		var wrist := skeleton.find_bone(side + "Hand" if not side.is_empty() else "Wrist" + suffix)
		if wrist >= 0:
			var origin := to_mesh * skeleton.get_bone_global_rest(wrist).origin
			var forward := tips[2] - origin
			material.set_shader_parameter("has_masks", 1.0 if _bake_masks(mesh, origin, forward, tips) else 0.0)
	return material

static func set_appearance(material: ShaderMaterial, alpha: float, overlay: bool) -> void:
	if overlay and _overlay_shader == null:
		_overlay_shader = Shader.new()
		_overlay_shader.code = SHADER.code.replace("depth_draw_never;", "depth_draw_never, depth_test_disabled;")
	var shader := _overlay_shader if overlay else SHADER
	if material.shader != shader:
		material.shader = shader
	material.render_priority = 1 if overlay else 0
	material.set_shader_parameter("opacity", clampf(alpha, 0.0, 1.0))


static func _bake_masks(instance: MeshInstance3D, wrist: Vector3, forward: Vector3, tips: PackedVector3Array) -> bool:
	var source := instance.mesh as ArrayMesh
	if source == null or forward.length_squared() < 0.000001:
		return false
	var length := forward.length()
	var axis := forward / length
	var mesh := ArrayMesh.new()
	mesh.resource_name = source.resource_name
	mesh.blend_shape_mode = source.blend_shape_mode
	for shape in source.get_blend_shape_count():
		mesh.add_blend_shape(source.get_blend_shape_name(shape))
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors := PackedColorArray()
		colors.resize(vertices.size())
		for i in vertices.size():
			var along := (vertices[i] - wrist).dot(axis) / length
			var nearest := INF
			for tip in tips:
				nearest = minf(nearest, vertices[i].distance_to(tip))
			var tip := 1.0 - smoothstep(0.012, 0.035, nearest)
			colors[i] = Color(maxf(smoothstep(0.03, 0.65, along), tip), tip, 0, 1)
		arrays[Mesh.ARRAY_COLOR] = colors
		mesh.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays, source.surface_get_blend_shape_arrays(surface), {}, source.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		mesh.surface_set_material(surface, source.surface_get_material(surface))
	instance.mesh = mesh
	return true
