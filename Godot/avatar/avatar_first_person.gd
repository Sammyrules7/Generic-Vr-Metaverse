class_name AvatarFirstPerson
extends RefCounted
## Keep the existing tracked/controller hands, removing overlapping avatar hands.

const VRM_UTILS := preload("res://addons/vrm/vrm_utils.gd")


static func use_tracked_hands(model: Node3D, enabled: bool) -> void:
	var skeleton := model.find_child("GeneralSkeleton", true, false) as Skeleton3D
	if skeleton == null:
		return
	var hidden_bones := {}
	for hand in ["LeftHand", "RightHand"]:
		var bone := skeleton.find_bone(hand)
		if bone >= 0:
			VRM_UTILS._recurse_bones(hidden_bones, skeleton, bone)
	for instance: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if not instance.has_meta("avatar_full_mesh"):
			instance.set_meta("avatar_full_mesh", instance.mesh)
		if not enabled or (instance.layers & AvatarView.FULL_BODY) != 0:
			instance.mesh = instance.get_meta("avatar_full_mesh")
			continue
		if instance.has_meta("avatar_handless_mesh"):
			instance.mesh = instance.get_meta("avatar_handless_mesh")
			continue
		var mesh := instance.mesh as ArrayMesh
		if mesh == null or instance.skin == null:
			continue
		var importer := ImporterMesh.new()
		importer.set_blend_shape_mode(mesh.blend_shape_mode)
		for blend in mesh.get_blend_shape_count():
			importer.add_blend_shape(mesh.get_blend_shape_name(blend))
		for surface in mesh.get_surface_count():
			importer.add_surface(mesh.surface_get_primitive_type(surface), mesh.surface_get_arrays(surface), mesh.surface_get_blend_shape_arrays(surface), {}, mesh.surface_get_material(surface), mesh.surface_get_name(surface))
		var stripped: ImporterMesh = VRM_UTILS._generate_hide_bone_mesh(importer, instance.skin, hidden_bones, [])
		var handless: ArrayMesh = stripped.get_mesh() if stripped != null else null
		instance.set_meta("avatar_handless_mesh", handless)
		instance.mesh = handless
