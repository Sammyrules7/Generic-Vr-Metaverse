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
			material.set_shader_parameter("wrist_origin", origin)
			material.set_shader_parameter("hand_forward", forward.normalized())
			material.set_shader_parameter("hand_length", forward.length())
			material.set_shader_parameter("wrist_fade", 1.0)
		material.set_shader_parameter("fingertips", tips)
		material.set_shader_parameter("fingertip_highlight", 1.0)
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
