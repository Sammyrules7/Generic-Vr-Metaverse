class_name AvatarSprings
extends RefCounted

const VRMSecondary = preload("res://addons/vrm/vrm_secondary.gd")
const VRMSpringBone = preload("res://addons/vrm/vrm_spring_bone.gd")
const VRMCollider = preload("res://addons/vrm/vrm_collider.gd")
const VRMColliderGroup = preload("res://addons/vrm/vrm_collider_group.gd")

const MAX_SPRING_CHAINS := 64
const MAX_JOINTS_PER_CHAIN := 64
const MAX_COLLIDERS_PER_CHAIN := 64

static func install(model: Node3D) -> Array[SpringBoneSimulator3D]:
	var result: Array[SpringBoneSimulator3D] = []
	if model == null or not is_instance_valid(model):
		push_error("AvatarSprings.install: model is null")
		return result
	if not model.is_inside_tree():
		push_error("AvatarSprings.install: model must be added to the scene tree first")
		return result

	var skeleton: Skeleton3D = _find_skeleton(model)
	if skeleton == null:
		push_error("AvatarSprings.install: no Skeleton3D found in model")
		return result

	var spring_sources: Array = []
	var secondary_nodes: Array[Node] = []
	for node in _all_nodes(model):
		if node is VRMSecondary:
			secondary_nodes.append(node)
			var secondary: VRMSecondary = node as VRMSecondary
			if secondary.skel == null:
				secondary.skel = skeleton
			if secondary.spring_bones != null:
				for spring in secondary.spring_bones:
					if spring != null:
						spring_sources.append({"spring": spring, "secondary": secondary})
	if spring_sources.is_empty() and model.get("spring_bones") != null:
		for spring in (model.get("spring_bones") as Array):
			if spring != null:
				spring_sources.append({"spring": spring, "secondary": null})

	if spring_sources.size() > MAX_SPRING_CHAINS:
		push_error("AvatarSprings.install: too many spring chains (%d > %d); skipping conversion" % [spring_sources.size(), MAX_SPRING_CHAINS])
		_disable_secondary_nodes(secondary_nodes)
		return result

	var chain_index := 0
	for source in spring_sources:
		if chain_index >= MAX_SPRING_CHAINS:
			break
		var spring: VRMSpringBone = source["spring"] as VRMSpringBone
		var secondary: VRMSecondary = source["secondary"] as VRMSecondary
		var simulator := _convert_chain(skeleton, spring, secondary, model)
		if simulator != null:
			result.append(simulator)
			chain_index += 1

	_disable_secondary_nodes(secondary_nodes)
	return result

static func _convert_chain(skeleton: Skeleton3D, spring: VRMSpringBone, secondary: Node, model: Node3D) -> SpringBoneSimulator3D:
	var joints: PackedStringArray = spring.joint_nodes
	var bone_names: Array[String] = []
	for name in joints:
		if not String(name).is_empty():
			bone_names.append(String(name))
	if bone_names.is_empty():
		push_error("AvatarSprings: spring chain has no joints")
		return null
	if bone_names.size() > MAX_JOINTS_PER_CHAIN:
		push_error("AvatarSprings: too many joints in chain '%s' (%d > %d)" % [bone_names[0], bone_names.size(), MAX_JOINTS_PER_CHAIN])
		return null

	for bone_name in bone_names:
		if skeleton.find_bone(bone_name) == -1:
			push_error("AvatarSprings: missing bone '%s' in skeleton" % bone_name)
			return null
	for index in range(1, bone_names.size()):
		if skeleton.get_bone_parent(skeleton.find_bone(bone_names[index])) != skeleton.find_bone(bone_names[index - 1]):
			push_warning("AvatarSprings: skipping a non-linear spring chain")
			return null

	var has_virtual_tail := joints.size() > 0 and String(joints[joints.size() - 1]).is_empty()
	if bone_names.size() == 1:
		has_virtual_tail = true

	var root_name := bone_names[0]
	var end_name := bone_names[bone_names.size() - 1]
	var extend_tail := has_virtual_tail

	var simulator := SpringBoneSimulator3D.new()
	skeleton.add_child(simulator)
	simulator.setting_count = 1
	var idx := 0
	simulator.set_root_bone_name(idx, root_name)
	simulator.set_end_bone_name(idx, end_name)
	if extend_tail:
		simulator.set_extend_end_bone(idx, true)
		simulator.set_end_bone_direction(idx, SkeletonModifier3D.BONE_DIRECTION_FROM_PARENT)
		simulator.set_end_bone_length(idx, 0.07)

	simulator.set_individual_config(idx, true)
	var joint_count := simulator.get_joint_count(idx)
	if joint_count <= 0:
		joint_count = bone_names.size()
	for joint in range(joint_count):
		var source_index := joint if joint < bone_names.size() else bone_names.size() - 1

		var stiffness := _effective_value(spring.stiffness_force, spring.stiffness_scale, source_index)
		var drag := _effective_value(spring.drag_force, spring.drag_force_scale, source_index)
		var gravity := _effective_value(spring.gravity_power, spring.gravity_scale, source_index)
		var radius := _effective_value(spring.hit_radius, spring.hit_radius_scale, source_index)

		simulator.set_joint_stiffness(idx, joint, stiffness)
		simulator.set_joint_drag(idx, joint, drag)
		simulator.set_joint_gravity(idx, joint, gravity)

		var gravity_dir := spring.gravity_dir_default
		if not spring.gravity_dir.is_empty():
			var dir_index := joint if joint < spring.gravity_dir.size() else spring.gravity_dir.size() - 1
			if dir_index >= 0:
				gravity_dir = spring.gravity_dir[dir_index]
		simulator.set_joint_gravity_direction(idx, joint, gravity_dir)

		simulator.set_joint_radius(idx, joint, radius)

	if spring.center_bone != "":
		simulator.set_center_from(idx, 2)
		simulator.set_center_bone_name(idx, spring.center_bone)
	elif spring.center_node != NodePath():
		simulator.set_center_from(idx, 1)
		var center_node: Node = null
		if secondary != null and is_instance_valid(secondary):
			var resolved: Node = secondary.get_node_or_null(spring.center_node)
			if resolved != secondary:
				center_node = resolved
		if center_node == null:
			center_node = model.get_node_or_null(spring.center_node)
		if center_node == secondary:
			center_node = null
		if center_node != null:
			var node_path := simulator.get_path_to(center_node)
			simulator.set_center_node(idx, node_path)
		else:
			simulator.set_center_from(idx, 1)
			simulator.set_center_node(idx, NodePath())
	else:
		simulator.set_center_from(idx, 1)
		simulator.set_center_node(idx, NodePath())

	_add_colliders(simulator, spring, secondary, model, skeleton)

	simulator.set_rotation_axis(idx, SkeletonModifier3D.ROTATION_AXIS_ALL)

	return simulator

static func _effective_value(per_joint: PackedFloat64Array, scale: float, index: int) -> float:
	if per_joint.is_empty():
		return scale
	var source_index := index if index < per_joint.size() else per_joint.size() - 1
	if source_index < 0:
		return scale
	var ratio := per_joint[source_index]
	return ratio * scale

static func _add_colliders(simulator: SpringBoneSimulator3D, spring: VRMSpringBone, secondary: Node, model: Node3D, skeleton: Skeleton3D) -> void:
	var seen: Dictionary = {}
	var colliders: Array = []
	for group in spring.collider_groups:
		if group == null:
			continue
		for collider in group.colliders:
			if collider == null:
				continue
			var key := collider.get_instance_id()
			if seen.has(key):
				continue
			seen[key] = true
			colliders.append(collider)
	if colliders.size() > MAX_COLLIDERS_PER_CHAIN:
		push_error("AvatarSprings: too many colliders for chain (%d > %d)" % [colliders.size(), MAX_COLLIDERS_PER_CHAIN])
		colliders = colliders.slice(0, MAX_COLLIDERS_PER_CHAIN)

	simulator.set_enable_all_child_collisions(0, true)
	for collider in colliders:
		var c: VRMCollider = collider as VRMCollider
		var collision_node: Node3D
		if c.is_capsule:
			var capsule := SpringBoneCollisionCapsule3D.new()
			capsule.radius = c.radius
			var tail_vec := c.tail - c.offset
			var distance := tail_vec.length()
			capsule.mid_height = maxf(distance, 0.001)
			if distance > 0.0001:
				var from := Vector3.UP
				var to := tail_vec.normalized()
				var axis := from.cross(to)
				if axis.length() <= 0.0001:
					# Opposite directions: pick a perpendicular axis.
					axis = Vector3.RIGHT
					if from.dot(to) > 0.999:
						axis = Vector3.FORWARD
				capsule.rotation_offset = Quaternion(axis.normalized(), from.angle_to(to))
			collision_node = capsule
		else:
			var sphere := SpringBoneCollisionSphere3D.new()
			sphere.radius = c.radius
			collision_node = sphere

		if c.bone != "":
			collision_node.set("bone_name", c.bone)
			if c.is_capsule:
				collision_node.set("position_offset", (c.offset + c.tail) * 0.5)
			else:
				collision_node.set("position_offset", c.offset)
		elif c.node_path != NodePath():
			var target: Node3D = null
			if secondary != null and is_instance_valid(secondary):
				target = secondary.get_node_or_null(c.node_path) as Node3D
			if target == null:
				target = model.get_node_or_null(c.node_path) as Node3D
			if target != null:
				var sim_space: Transform3D = skeleton.global_transform.affine_inverse() * simulator.global_transform
				var target_space: Transform3D = skeleton.global_transform.affine_inverse() * target.global_transform
				collision_node.transform = sim_space.affine_inverse() * target_space
				if c.is_capsule:
					collision_node.set("position_offset", (c.offset + c.tail) * 0.5)
				else:
					collision_node.set("position_offset", c.offset)
			else:
				push_error("AvatarSprings: collider node not found: %s" % str(c.node_path))
				collision_node.queue_free()
				continue
		else:
			if c.is_capsule:
				collision_node.set("position_offset", (c.offset + c.tail) * 0.5)
			else:
				collision_node.set("position_offset", c.offset)

		simulator.add_child(collision_node)

static func _disable_secondary_nodes(nodes: Array[Node]) -> void:
	for node in nodes:
		if not is_instance_valid(node):
			continue
		node.set("is_child_of_vrm", false)
		node.set_process(false)
		node.set_physics_process(false)
		# Remove the addon's internal skeleton modifier if it was created.
		var skel: Skeleton3D = node.get("skel") as Skeleton3D
		if skel != null and is_instance_valid(skel):
			var modifier := skel.get_node_or_null("VRM_internal_skeleton_modifier")
			if modifier != null:
				skel.remove_child(modifier)
				modifier.queue_free()
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.queue_free()

static func _find_skeleton(model: Node3D) -> Skeleton3D:
	for node in _all_nodes(model):
		if node is Skeleton3D:
			return node as Skeleton3D
	return null

static func _all_nodes(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		out.append(node)
		for child in node.get_children():
			stack.append(child)
	return out
