extends SceneTree

var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	var svc = root.get_node("AvatarService")
	var req = svc.acquire("godette")
	if not req.finished:
		await req.completed
	check(req.scene != null, "godette did not load: " + str(req.error))
	if req.scene == null:
		quit(1)
		return
	var model = req.scene.instantiate() as Node3D
	root.add_child(model)
	await process_frame
	check(model.get_node_or_null("secondary") != null, "addon secondary exists before conversion")

	var simulators: Array = load("res://avatar/avatar_springs.gd").install(model)
	check(simulators.size() == 8, "expected 8 spring simulators, got %d" % simulators.size())

	var skeleton: Skeleton3D = null
	for node in _all(model):
		if node is Skeleton3D:
			skeleton = node
			break
	check(skeleton != null, "skeleton found")
	for sim in simulators:
		check(sim is SpringBoneSimulator3D, "returned native simulator")
		check(sim.get_parent() == skeleton, "simulator is child of skeleton")
		check(sim.active, "simulator active by default")
		check(sim.get_setting_count() == 1, "one setting per chain")

	# Old addon simulation removed.
	check(model.get_node_or_null("secondary") == null, "addon secondary removed")

	# Root/end/tail semantics for a representative chain.
	var sim0: SpringBoneSimulator3D = simulators[0]
	check(sim0.get_root_bone_name(0) == "FrontHair_Center_L", "root bone name")
	check(sim0.get_end_bone_name(0) == "FrontHair_Center_L_End", "end bone name")
	check(sim0.is_end_bone_extended(0), "virtual tail extended")

	# Find an extended-tail chain (HairBall has leaf? Actually all have trailing empty -> extended true).
	var extended_found := false
	for sim in simulators:
		if sim.is_end_bone_extended(0):
			extended_found = true
			check(sim.get_end_bone_length(0) > 0.0, "extended tail has length")
			break
	check(extended_found, "at least one extended virtual tail")

	# Colliders: hair chains have 2, ribbon has 2.
	var total_collisions := 0
	for sim in simulators:
		for child in sim.get_children():
			if child is SpringBoneCollision3D:
				total_collisions += 1
	check(total_collisions == 10, "expected 10 collider nodes, got %d" % total_collisions)

	# Observe actual bone deflection inside the modifier pass: Godot restores
	# original poses afterwards, and an extended leaf can rotate without moving.
	var sim_motion: SpringBoneSimulator3D = simulators[0]
	var bone_idx := skeleton.find_bone(sim_motion.get_root_bone_name(0))
	var baseline := skeleton.get_bone_global_rest(bone_idx).basis.get_rotation_quaternion()
	var motion := {"calls": 0, "max_angle": 0.0}
	var capture := func():
		var rotation := skeleton.get_bone_global_pose(bone_idx).basis.get_rotation_quaternion()
		motion.calls += 1
		motion.max_angle = maxf(motion.max_angle, rotation.angle_to(baseline))
	sim_motion.modification_processed.connect(capture)
	sim_motion.external_force = Vector3(3, 0, 5)
	for frame in 20:
		await create_timer(0.01).timeout
	check(motion.calls > 0, "Native modifier did not process")
	check(motion.max_angle > 0.001, "Native spring did not deflect under external force")
	sim_motion.modification_processed.disconnect(capture)
	sim_motion.external_force = Vector3.ZERO

	# Toggle active.
	for sim in simulators:
		sim.active = false
		sim.reset()
	for sim in simulators:
		check(not sim.active, "simulator disabled")
	for sim in simulators:
		sim.active = true
		sim.reset()



	# Synthetic zero-scale and capsule geometry checks.
	var synthetic_model := Node3D.new()
	root.add_child(synthetic_model)
	var synthetic_skel := Skeleton3D.new()
	synthetic_model.add_child(synthetic_skel)
	var pb := synthetic_skel.add_bone("Parent")
	synthetic_skel.set_bone_parent(pb, -1)
	var rb := synthetic_skel.add_bone("Root")
	synthetic_skel.set_bone_parent(rb, pb)
	var cb := synthetic_skel.add_bone("Child")
	synthetic_skel.set_bone_parent(cb, rb)
	synthetic_skel.set_bone_rest(cb, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await process_frame

	var synthetic_collider := VRMCollider.new()
	synthetic_collider.bone = "Root"
	synthetic_collider.offset = Vector3(0.1, 0.2, 0.3)
	synthetic_collider.tail = Vector3(0.1, 0.2, 0.1)  # downward-ish capsule
	synthetic_collider.radius = 0.05
	synthetic_collider.is_capsule = true

	var synthetic_group := VRMColliderGroup.new()
	synthetic_group.colliders = [synthetic_collider]

	var synthetic_spring := VRMSpringBone.new()
	synthetic_spring.joint_nodes = PackedStringArray(["Root", "Child", ""])
	synthetic_spring.stiffness_scale = 0.0
	synthetic_spring.gravity_scale = 0.0
	synthetic_spring.drag_force_scale = 0.0
	synthetic_spring.hit_radius_scale = 0.0
	synthetic_spring.collider_groups = [synthetic_group]

	var synthetic_secondary := VRMSecondary.new()
	synthetic_secondary.skeleton = NodePath("../" + synthetic_skel.name)
	synthetic_model.add_child(synthetic_secondary)
	synthetic_secondary.skel = synthetic_skel
	synthetic_secondary.spring_bones = [synthetic_spring]
	await process_frame

	var synthetic_sims: Array = load("res://avatar/avatar_springs.gd").install(synthetic_model)
	check(synthetic_sims.size() == 1, "synthetic spring converted")
	if synthetic_sims.size() == 1:
		var ssim: SpringBoneSimulator3D = synthetic_sims[0]
		check(is_zero_approx(ssim.get_joint_stiffness(0, 0)), "zero stiffness preserved")
		check(is_zero_approx(ssim.get_joint_gravity(0, 0)), "zero gravity preserved")
		check(is_zero_approx(ssim.get_joint_drag(0, 0)), "zero drag preserved")
		check(is_zero_approx(ssim.get_joint_radius(0, 0)), "zero radius preserved")
		var capsule_node: SpringBoneCollisionCapsule3D = null
		for child in ssim.get_children():
			if child is SpringBoneCollisionCapsule3D:
				capsule_node = child
		check(capsule_node != null, "capsule collider created")
		if capsule_node != null:
			var expected_mid := (synthetic_collider.offset + synthetic_collider.tail) * 0.5
			check(capsule_node.position_offset.is_equal_approx(expected_mid), "capsule center is midpoint")
			check(is_equal_approx(capsule_node.mid_height, (synthetic_collider.tail - synthetic_collider.offset).length()), "capsule length correct")

	# Opposite-direction capsule branch.
	var opp_model := Node3D.new()
	root.add_child(opp_model)
	var opp_skel := Skeleton3D.new()
	opp_model.add_child(opp_skel)
	var opb := opp_skel.add_bone("Parent")
	opp_skel.set_bone_parent(opb, -1)
	var orb := opp_skel.add_bone("Root")
	opp_skel.set_bone_parent(orb, opb)
	var ocb := opp_skel.add_bone("Child")
	opp_skel.set_bone_parent(ocb, orb)
	opp_skel.set_bone_rest(ocb, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await process_frame
	var opp_collider := VRMCollider.new()
	opp_collider.bone = "Root"
	opp_collider.offset = Vector3.ZERO
	opp_collider.tail = Vector3(0, -0.2, 0)
	opp_collider.radius = 0.05
	opp_collider.is_capsule = true
	var opp_group := VRMColliderGroup.new()
	opp_group.colliders = [opp_collider]
	var opp_spring := VRMSpringBone.new()
	opp_spring.joint_nodes = PackedStringArray(["Root", ""])
	opp_spring.collider_groups = [opp_group]
	var opp_secondary := VRMSecondary.new()
	opp_secondary.skeleton = NodePath("../" + opp_skel.name)
	opp_model.add_child(opp_secondary)
	opp_secondary.skel = opp_skel
	opp_secondary.spring_bones = [opp_spring]
	await process_frame
	var opp_sims: Array = load("res://avatar/avatar_springs.gd").install(opp_model)
	if opp_sims.size() == 1:
		var ocaps: SpringBoneCollisionCapsule3D = null
		for child in opp_sims[0].get_children():
			if child is SpringBoneCollisionCapsule3D:
				ocaps = child
		check(ocaps != null, "opposite capsule created")
		if ocaps != null:
			check((ocaps.rotation_offset * Vector3.UP).is_equal_approx(Vector3.DOWN), "Opposite capsule axis must rotate downward")
	model.free()
	synthetic_model.free()
	opp_model.free()
	req.release()

	print("avatar_springs_test: ", failures, " failures")
	quit(1 if failures else 0)

func _all(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		out.append(node)
		for child in node.get_children():
			stack.append(child)
	return out
