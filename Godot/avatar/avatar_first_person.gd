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
		if not enabled or (instance.layers & (AvatarView.FIRST_PERSON | 2)) == 0:
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


static func prepare(model: Node3D) -> void:
	# Persist the immutable stripped meshes in the cached PackedScene so wearing
	# an already-previewed avatar only switches references, not vertex data.
	use_tracked_hands(model, true)
	use_tracked_hands(model, false)


static func prepare_async(model: Node3D, tree: SceneTree, active_jobs: Array[AvatarHandMeshJob]) -> void:
	var skeleton := model.find_child("GeneralSkeleton", true, false) as Skeleton3D
	if skeleton == null:
		return
	var hidden_bones := {}
	for hand in ["LeftHand", "RightHand"]:
		var bone := skeleton.find_bone(hand)
		if bone >= 0:
			VRM_UTILS._recurse_bones(hidden_bones, skeleton, bone)
	for instance: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if (instance.layers & 2) == 0 or instance.skin == null or not instance.mesh is ArrayMesh:
			continue
		var mesh := instance.mesh as ArrayMesh
		var importer := ImporterMesh.new()
		importer.set_blend_shape_mode(mesh.blend_shape_mode)
		for blend in mesh.get_blend_shape_count():
			importer.add_blend_shape(mesh.get_blend_shape_name(blend))
		for surface in mesh.get_surface_count():
			importer.add_surface(mesh.surface_get_primitive_type(surface), mesh.surface_get_arrays(surface), mesh.surface_get_blend_shape_arrays(surface), {}, mesh.surface_get_material(surface), mesh.surface_get_name(surface))
		var job := AvatarHandMeshJob.new()
		active_jobs.append(job)
		job.mesh = importer
		job.skin = instance.skin
		job.hidden_bones = hidden_bones
		if OS.has_feature("web") and not OS.has_feature("threads"):
			job.run()
		else:
			job.task_id = WorkerThreadPool.add_task(job.run, false, "Prepare avatar hands")
			while not WorkerThreadPool.is_task_completed(job.task_id):
				await tree.process_frame
			WorkerThreadPool.wait_for_task_completion(job.task_id)
		active_jobs.erase(job)
		instance.set_meta("avatar_full_mesh", mesh)
		instance.set_meta("avatar_handless_mesh", job.result.get_mesh() if job.result != null else null)
		await tree.process_frame
