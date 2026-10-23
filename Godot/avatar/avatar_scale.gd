class_name AvatarScale
extends RefCounted
## Bake standing eye height into geometry/rest data, keeping native solvers unscaled.


static func normalize(model: Node3D, eye_height := 1.7) -> void:
	var skeleton := model.find_child("GeneralSkeleton", true, false) as Skeleton3D
	if skeleton == null:
		return
	var head := skeleton.find_bone("Head")
	if head < 0:
		return
	var eye := (skeleton.transform * skeleton.get_bone_global_rest(head)) * AvatarEyes.offset(model, skeleton)
	if eye.y < 0.3 or eye.y > 3.0:
		return
	var factor := clampf(eye_height / eye.y, 0.5, 3.0)
	var meshes := {}
	var skins := {}
	var springs := {}
	var colliders := {}
	var nodes: Array[Node] = [model]
	nodes.append_array(model.find_children("*", "", true, false))
	for node in nodes:
		if node is Node3D and not node is BoneAttachment3D:
			node.position *= factor
		if node is Skeleton3D:
			for bone in node.get_bone_count():
				var rest: Transform3D = node.get_bone_rest(bone)
				rest.origin *= factor
				node.set_bone_rest(bone, rest)
				node.set_bone_pose_position(bone, node.get_bone_pose_position(bone) * factor)
			node.motion_scale *= factor
		if node is MeshInstance3D:
			if node.mesh is ArrayMesh:
				if not meshes.has(node.mesh):
					meshes[node.mesh] = _scale_mesh(node.mesh, factor)
				node.mesh = meshes[node.mesh]
			if node.skin != null:
				if not skins.has(node.skin):
					var skin := node.skin.duplicate() as Skin
					for bind in skin.get_bind_count():
						var pose := skin.get_bind_pose(bind)
						pose.origin *= factor
						skin.set_bind_pose(bind, pose)
					skins[node.skin] = skin
				node.skin = skins[node.skin]
		if node is VRMSecondary:
			for spring: VRMSpringBone in node.spring_bones:
				if springs.has(spring):
					continue
				springs[spring] = true
				for joint in spring.hit_radius.size():
					spring.hit_radius[joint] *= factor
				for group: VRMColliderGroup in spring.collider_groups:
					for collider: VRMCollider in group.colliders:
						if not colliders.has(collider):
							colliders[collider] = true
							collider.offset *= factor
							collider.tail *= factor
							collider.radius *= factor
		if node is AnimationPlayer:
			for animation_name in node.get_animation_list():
				var animation: Animation = node.get_animation(animation_name)
				for track in animation.get_track_count():
					if animation.track_get_type(track) == Animation.TYPE_POSITION_3D:
						for key in animation.track_get_key_count(track):
							animation.track_set_key_value(track, key, animation.track_get_key_value(track, key) * factor)
	model.set_meta("avatar_height_scale", factor)


static func _scale_mesh(source: ArrayMesh, factor: float) -> ArrayMesh:
	var result := ArrayMesh.new()
	result.resource_name = source.resource_name
	result.blend_shape_mode = source.blend_shape_mode
	for blend in source.get_blend_shape_count():
		result.add_blend_shape(source.get_blend_shape_name(blend))
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		arrays[Mesh.ARRAY_VERTEX] = _scale_vertices(arrays[Mesh.ARRAY_VERTEX], factor)
		var shapes := source.surface_get_blend_shape_arrays(surface)
		for shape in shapes:
			shape[Mesh.ARRAY_VERTEX] = _scale_vertices(shape[Mesh.ARRAY_VERTEX], factor)
		result.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays, shapes, {}, source.surface_get_format(surface))
		result.surface_set_material(surface, source.surface_get_material(surface))
		result.surface_set_name(surface, source.surface_get_name(surface))
	return result


static func _scale_vertices(vertices: PackedVector3Array, factor: float) -> PackedVector3Array:
	# This packed-array transform runs in native code rather than a GDScript
	# iteration for every base/blend-shape vertex in the avatar.
	return Transform3D(Basis.from_scale(Vector3.ONE * factor), Vector3.ZERO) * vertices
