extends SceneTree
## Headless coverage for ground-aware leg/foot IK.
##
## Every test builds a real physics floor and runs the driver through actual
## physics + process frames. The fixture proportions match a normalized avatar:
## the eye anchor sits at 1.7 m and the legs are long enough to reach the floor.

var failures := 0

const FIXTURE_BONES := [
	["Hips", -1, Vector3(0, 0.95, 0)],
	["Spine", 0, Vector3(0, 0.1, 0)],
	["Chest", 1, Vector3(0, 0.2, 0)],
	["Neck", 2, Vector3(0, 0.2, 0)],
	["Head", 3, Vector3(0, 0.17, 0)],
	["LeftUpperArm", 2, Vector3(0.15, 0.15, 0)],
	["LeftLowerArm", 5, Vector3(0.3, 0, 0)],
	["LeftHand", 6, Vector3(0.25, 0, 0)],
	["RightUpperArm", 2, Vector3(-0.15, 0.15, 0)],
	["RightLowerArm", 8, Vector3(-0.3, 0, 0)],
	["RightHand", 9, Vector3(-0.25, 0, 0)],
	["LeftUpperLeg", 0, Vector3(0.1, -0.05, 0)],
	["LeftLowerLeg", 11, Vector3(0, -0.42, 0)],
	["LeftFoot", 12, Vector3(0, -0.45, 0)],
	["LeftToes", 13, Vector3(0, 0, 0.15)],
	["RightUpperLeg", 0, Vector3(-0.1, -0.05, 0)],
	["RightLowerLeg", 15, Vector3(0, -0.42, 0)],
	["RightFoot", 16, Vector3(0, -0.45, 0)],
	["RightToes", 17, Vector3(0, 0, 0.15)],
]

const UPPER_BONES := [
	["Hips", -1, Vector3(0, 0.95, 0)],
	["Spine", 0, Vector3(0, 0.1, 0)],
	["Chest", 1, Vector3(0, 0.2, 0)],
	["Neck", 2, Vector3(0, 0.2, 0)],
	["Head", 3, Vector3(0, 0.17, 0)],
	["LeftUpperArm", 2, Vector3(0.15, 0.15, 0)],
	["LeftLowerArm", 5, Vector3(0.3, 0, 0)],
	["LeftHand", 6, Vector3(0.25, 0, 0)],
	["RightUpperArm", 2, Vector3(-0.15, 0.15, 0)],
	["RightLowerArm", 8, Vector3(-0.3, 0, 0)],
	["RightHand", 9, Vector3(-0.25, 0, 0)],
]


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func run() -> void:
	await _test_flat_ground()
	await _test_deep_crouch()
	await _test_bundled_avatar()
	await _test_slope_ground()
	await _test_no_ground()
	await _test_airborne()
	await _test_walk_and_teleport()
	await _test_transformed_rig()
	await _test_world_scale()
	await _test_reach_limit()
	await _test_missing_legs()
	await _test_lower_body_tracked()
	await _test_character_body_exclusion()
	print("AVATAR_GROUND_FEET_TEST failures=", failures)
	quit(1 if failures else 0)


# Fixtures


func build_model(bones: Array = FIXTURE_BONES) -> Node3D:
	var model := Node3D.new()
	model.name = "Model"
	var skeleton := Skeleton3D.new()
	skeleton.name = "GeneralSkeleton"
	model.add_child(skeleton)
	for entry in bones:
		skeleton.add_bone(entry[0])
		skeleton.set_bone_parent(skeleton.find_bone(entry[0]), entry[1])
		skeleton.set_bone_rest(skeleton.find_bone(entry[0]), Transform3D(Basis.IDENTITY, entry[2]))
	skeleton.reset_bone_poses()
	var attachment := BoneAttachment3D.new()
	attachment.name = "Head"
	attachment.bone_name = "Head"
	skeleton.add_child(attachment)
	var look := Node3D.new()
	look.name = "LookOffset"
	attachment.add_child(look)
	look.position = Vector3(0, 0.08, 0.1)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.layers = 1
	body.set_meta("vrm_first_person_flag", "auto")
	skeleton.add_child(body)
	var headless := MeshInstance3D.new()
	headless.name = "Body (Headless)"
	headless.layers = 2
	headless.set_meta("vrm_first_person_flag", "head_removed")
	skeleton.add_child(headless)
	return model


func make_driver() -> Node3D:
	var driver := Node3D.new()
	driver.set_script(load("res://avatar/avatar_rig_driver.gd"))
	return driver


func build_rig(parent: Node, model: Node3D, local: bool = true, vr: bool = true) -> Dictionary:
	var container := Node3D.new()
	container.name = "Avatar"
	parent.add_child(container)
	container.add_child(model)
	var head := Node3D.new()
	head.name = "Head"
	container.add_child(head)
	head.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.7, 0))
	var left := Node3D.new()
	left.name = "LeftHand"
	container.add_child(left)
	left.transform = Transform3D(Basis.IDENTITY, Vector3(0.4, 1.2, 0.1))
	var right := Node3D.new()
	right.name = "RightHand"
	container.add_child(right)
	right.transform = Transform3D(Basis.IDENTITY, Vector3(-0.4, 1.2, 0.1))
	var driver := make_driver()
	driver.name = "RigDriver"
	container.add_child(driver)
	driver.configure(model, head, left, right, local, vr)
	return {"container": container, "driver": driver, "model": model, "head": head, "left": left, "right": right}


func add_floor(parent: Node, angle_x: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Floor"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 0.2, 20)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0, -0.1, 0)
	body.rotation.x = angle_x
	parent.add_child(body)
	return body


func settle(frames: int) -> void:
	for _frame in frames:
		await physics_frame
		await process_frame


## Capture the final, post-modifier foot pose. The engine restores the
## pre-modifier bone poses after skinning, so the world pose must be read inside
## the modifier callback.
func watch_feet(driver) -> Dictionary:
	var records := {}
	if driver.ground_feet == null or driver.ground_feet._foot_modifier == null:
		return records
	for side in driver.ground_feet._foot:
		records[side] = {"ankle": Vector3.ZERO, "up": Vector3.UP, "basis": Basis.IDENTITY, "hip": Vector3.ZERO, "knee": Vector3.ZERO, "toes": Vector3.ZERO}
	driver.ground_feet._foot_modifier.modification_processed.connect(func() -> void:
		var skeleton: Skeleton3D = driver.skeleton
		var world_basis := skeleton.global_transform.basis.orthonormalized()
		for side in driver.ground_feet._foot:
			var bone: int = driver.ground_feet._foot[side]
			var pose := skeleton.get_bone_global_pose(bone)
			var up_local: Vector3 = driver.ground_feet._foot_up_local[side]
			var basis := world_basis * pose.basis.orthonormalized()
			records[side]["ankle"] = skeleton.global_transform * pose.origin
			for entry in [["hip", driver.ground_feet._upper[side]], ["knee", driver.ground_feet._lower[side]], ["toes", skeleton.find_bone("LeftToes" if side == "left" else "RightToes")]]:
				if entry[1] >= 0:
					records[side][entry[0]] = skeleton.global_transform * skeleton.get_bone_global_pose(entry[1]).origin
			records[side]["basis"] = basis
			records[side]["up"] = (basis * up_local).normalized()
	)
	return records


func plane_of(floor: StaticBody3D) -> Plane:
	var normal := (floor.global_transform.basis * Vector3.UP).normalized()
	var top_center := floor.global_transform * Vector3(0, 0.1, 0)
	return Plane(normal, normal.dot(top_center))


func world_scale(driver) -> float:
	var scale: Vector3 = driver.skeleton.global_basis.get_scale()
	return (absf(scale.x) + absf(scale.y) + absf(scale.z)) / 3.0


# Tests


func _test_flat_ground() -> void:
	var scene_root := Node3D.new()
	root.add_child(scene_root)
	var floor := add_floor(scene_root)
	var rig := build_rig(scene_root, build_model())
	var driver = rig.driver
	await settle(8)
	check(driver.ground_feet != null, "Ground helper was not built")
	if driver.ground_feet == null:
		scene_root.free()
		return
	var feet = driver.ground_feet
	check(feet.leg_ik.size() == 2, "Both legs must get native IK")
	check(not feet.ground_hit.is_empty(), "Physics tick must find the floor")
	for side in ["left", "right"]:
		check(feet.ground_hit.get(side, {}).get("collider", null) == floor,
			"Ground probe must hit the floor on the " + side)
	var records := watch_feet(driver)
	await settle(12)
	var sole: float = float(feet.sole_offset.get("left", 0.0))
	check(sole > 0.02, "Sole offset must keep the ankle off the floor, got " + str(sole))
	for side in ["left", "right"]:
		var ankle: Vector3 = records[side]["ankle"]
		var up: Vector3 = records[side]["up"]
		check(absf(ankle.y - sole) < 0.015,
			"Ankle must sit one sole offset above the floor (" + side + "), got " + str(ankle.y))
		check(absf((ankle - up * sole).y) < 0.015,
			"Foot sole must touch the floor (" + side + "), sole y " + str((ankle - up * sole).y))
		check(up.dot(Vector3.UP) > 0.98,
			"Flat ground must orient the foot up (" + side + "), got " + str(up))
		check(feet.grounded.get(side, false), "Foot must be grounded on flat floor (" + side + ")")
		check(not feet.reach_limited.get(side, true) or float(feet.target_gap.get(side, 1.0)) < 0.005,
			"Flat floor must be reachable (" + side + "), gap " + str(feet.target_gap.get(side, -1.0)))
	# Standing feet stay planted while the restrained idle animates the legs.
	var start_left: Vector3 = records["left"]["ankle"]
	var start_right: Vector3 = records["right"]["ankle"]
	var drift_left := 0.0
	var drift_right := 0.0
	for _frame in 60:
		await settle(1)
		drift_left = maxf(drift_left, records["left"]["ankle"].distance_to(start_left))
		drift_right = maxf(drift_right, records["right"]["ankle"].distance_to(start_right))
	check(drift_left < 0.01, "Standing left foot must stay planted, drifted " + str(drift_left))
	check(drift_right < 0.01, "Standing right foot must stay planted, drifted " + str(drift_right))
	# Camera/eye and tracked hand authority are untouched by the leg solve.
	var look := driver.avatar_model.find_child("LookOffset", true, false) as Node3D
	check(look != null and look.global_position.distance_to(rig.head.global_position) < 0.002,
		"Ground IK must not move the eye anchor")
	check(driver.hand_target.left.global_position.distance_to(rig.left.global_position) < 0.001,
		"Ground IK must not move tracked hand targets")
	scene_root.free()


func _test_slope_ground() -> void:
	var scene_root := Node3D.new()
	root.add_child(scene_root)
	var floor := add_floor(scene_root, deg_to_rad(20.0))
	var rig := build_rig(scene_root, build_model())
	# A small crouch makes this downhill stance reachable with fixed leg lengths.
	# Unreachable standing configurations are covered separately below.
	rig.head.position.y = 1.62
	var driver = rig.driver
	await settle(10)
	var feet = driver.ground_feet
	if feet == null:
		check(false, "Ground helper was not built for the slope")
		scene_root.free()
		return
	var records := watch_feet(driver)
	await settle(12)
	var plane := plane_of(floor)
	var scale := world_scale(driver)
	var sole: float = float(feet.sole_offset.get("left", 0.0)) * scale
	for side in ["left", "right"]:
		var ankle: Vector3 = records[side]["ankle"]
		var up: Vector3 = records[side]["up"]
		check(absf(plane.distance_to(ankle) - sole) < 0.02,
			"Ankle must follow the slope normal (" + side + "), plane distance " + str(plane.distance_to(ankle)))
		check(up.dot(plane.normal) > 0.95,
			"Foot must align with the slope normal (" + side + "), dot " + str(up.dot(plane.normal)))
		check(feet.grounded.get(side, false), "Slope foot must be grounded (" + side + ")")
	var look := driver.avatar_model.find_child("LookOffset", true, false) as Node3D
	check(look != null and look.global_position.distance_to(rig.head.global_position) < 0.002,
		"Slope IK must not move the eye anchor")
	scene_root.free()


func _test_no_ground() -> void:
	var scene_root := Node3D.new()
	root.add_child(scene_root)
	var rig := build_rig(scene_root, build_model())
	var driver = rig.driver
	await settle(10)
	var feet = driver.ground_feet
	check(feet != null, "Ground helper must exist even without a floor")
	if feet != null:
		for side in ["left", "right"]:
			check(not feet.grounded.get(side, true), "No-ground foot must not claim contact (" + side + ")")
			check(not feet.leg_ik[side].active, "No-ground leg IK must stay inactive (" + side + ")")
	var look := driver.avatar_model.find_child("LookOffset", true, false) as Node3D
	check(look != null and look.global_position.distance_to(rig.head.global_position) < 0.002,
		"No-ground fallback must preserve the eye anchor")
	scene_root.free()


func _test_transformed_rig() -> void:
	var scene_root := Node3D.new()
	root.add_child(scene_root)
	var floor := add_floor(scene_root)
	var rig := build_rig(scene_root, build_model())
	var container: Node3D = rig.container
	container.position = Vector3(3, 0, -2)
	container.rotation.y = PI / 2.0
	var driver = rig.driver
	await settle(12)
	var feet = driver.ground_feet
	if feet == null:
		check(false, "Ground helper was not built for the transformed rig")
		scene_root.free()
		return
	var records := watch_feet(driver)
	await settle(10)
	var sole: float = float(feet.sole_offset.get("left", 0.0))
	for side in ["left", "right"]:
		var ankle: Vector3 = records[side]["ankle"]
		var up: Vector3 = records[side]["up"]
		check(absf(ankle.y - sole) < 0.02,
			"Transformed rig foot must stay on the floor (" + side + "), y " + str(ankle.y))
		check(up.dot(Vector3.UP) > 0.98,
			"Transformed rig foot must stay upright (" + side + ")")
		check(feet.ground_hit.get(side, {}).get("collider", null) == floor,
			"Transformed probe must still find the floor (" + side + ")")
	var look := driver.avatar_model.find_child("LookOffset", true, false) as Node3D
	check(look != null and look.global_position.distance_to(rig.head.global_position) < 0.002,
		"Transformed rig must keep the eye anchor")
	check(rig.head.global_position.distance_to(Vector3(3, 1.7, -2)) < 0.002,
		"Transformed head anchor moved unexpectedly, got " + str(rig.head.global_position))
	scene_root.free()


func _test_world_scale() -> void:
	var scene_root := Node3D.new()
	root.add_child(scene_root)
	add_floor(scene_root)
	var rig := build_rig(scene_root, build_model())
	var container: Node3D = rig.container
	container.scale = Vector3(1.5, 1.5, 1.5)
	var driver = rig.driver
	await settle(12)
	var feet = driver.ground_feet
	if feet == null:
		check(false, "Ground helper was not built for the scaled rig")
		scene_root.free()
		return
	var records := watch_feet(driver)
	await settle(10)
	var scale := world_scale(driver)
	check(absf(scale - 1.5) < 0.01, "World scale must reach the helper, got " + str(scale))
	var sole: float = float(feet.sole_offset.get("left", 0.0)) * scale
	for side in ["left", "right"]:
		var ankle: Vector3 = records[side]["ankle"]
		check(absf(ankle.y - sole) < 0.03,
			"Scaled rig foot must use the scaled sole offset (" + side + "), y " + str(ankle.y))
		check(feet.grounded.get(side, false), "Scaled rig foot must be grounded (" + side + ")")
	var look := driver.avatar_model.find_child("LookOffset", true, false) as Node3D
	check(look != null and look.global_position.distance_to(rig.head.global_position) < 0.003,
		"Scaled rig must keep the eye anchor")
	scene_root.free()


func _test_reach_limit() -> void:
	var scene_root := Node3D.new()
	root.add_child(scene_root)
	add_floor(scene_root)
	var rig := build_rig(scene_root, build_model())
	var driver = rig.driver
	var head: Node3D = rig.head
	head.position = Vector3(0, 2.7, 0)
	await settle(12)
	var feet = driver.ground_feet
	if feet == null:
		check(false, "Ground helper was not built for the reach test")
		scene_root.free()
		return
	var records := watch_feet(driver)
	await settle(10)
	var scale := world_scale(driver)
	var skeleton: Skeleton3D = driver.skeleton
	var thigh: float = float(feet._thigh["left"]) * scale
	var shin: float = float(feet._shin["left"]) * scale
	var foot_length: float = float(feet._foot_length["left"]) * scale
	var hip_world: Vector3 = records["left"]["hip"]
	var ankle: Vector3 = records["left"]["ankle"]
	var max_reach: float = (thigh + shin) * float(feet.REACH_MARGIN)
	check(hip_world.distance_to(ankle) <= max_reach + 0.002,
		"Unreachable floor must clamp to the leg reach, got " + str(hip_world.distance_to(ankle)))
	check(feet.reach_limited.get("left", false), "Reach limitation must be reported")
	check(float(feet.target_gap.get("left", 0.0)) > 0.5,
		"Reach limitation must expose the remaining gap, got " + str(feet.target_gap.get("left", -1.0)))
	# Bone lengths are preserved by the native solver.
	var knee_world: Vector3 = records["left"]["knee"]
	var toes_world: Vector3 = records["left"]["toes"]
	check(absf(hip_world.distance_to(knee_world) - thigh) < 0.003,
		"Thigh must not stretch, got " + str(hip_world.distance_to(knee_world)))
	check(absf(knee_world.distance_to(ankle) - shin) < 0.003,
		"Shin must not stretch, got " + str(knee_world.distance_to(ankle)))
	check(absf(ankle.distance_to(toes_world) - foot_length) < 0.003,
		"Foot must not stretch, got " + str(ankle.distance_to(toes_world)))
	# The knee bends forward, not backwards.
	var axis := (ankle - hip_world).normalized()
	var knee_offset := knee_world - hip_world
	var perpendicular := knee_offset - axis * knee_offset.dot(axis)
	var forward_world: Vector3 = skeleton.global_transform.basis * feet._foot_forward["left"]
	check(perpendicular.dot(forward_world) > 0.005,
		"Knee must bend forward instead of hyperextending, got " + str(perpendicular.dot(forward_world)))
	var look := driver.avatar_model.find_child("LookOffset", true, false) as Node3D
	check(look != null and look.global_position.distance_to(head.global_position) < 0.002,
		"Reach-limited IK must preserve the camera/eye anchor")
	scene_root.free()


func _test_missing_legs() -> void:
	var scene_root := Node3D.new()
	root.add_child(scene_root)
	add_floor(scene_root)
	var rig := build_rig(scene_root, build_model(UPPER_BONES))
	var driver = rig.driver
	await settle(10)
	var feet = driver.ground_feet
	check(feet != null, "Ground helper must tolerate a legless rig")
	if feet != null:
		check(feet.leg_ik.is_empty(), "Missing leg bones must not create leg IK")
		check(feet.foot_target.is_empty(), "Missing leg bones must not create foot targets")
	var look := driver.avatar_model.find_child("LookOffset", true, false) as Node3D
	check(look != null and look.global_position.distance_to(rig.head.global_position) < 0.002,
		"Missing legs must not affect the head anchor")
	scene_root.free()


func _test_lower_body_tracked() -> void:
	var scene_root := Node3D.new()
	root.add_child(scene_root)
	add_floor(scene_root)
	var rig := build_rig(scene_root, build_model())
	var driver = rig.driver
	driver.lower_body_tracked = true
	await settle(12)
	var feet = driver.ground_feet
	if feet == null:
		check(false, "Ground helper was not built for the tracked lower body test")
		scene_root.free()
		return
	for side in ["left", "right"]:
		check(not feet.leg_ik[side].active,
			"A tracked lower body must disable ground leg IK (" + side + ")")
		check(not feet.grounded.get(side, true), "Tracked lower body must not claim ground contact (" + side + ")")
	var skeleton: Skeleton3D = driver.skeleton
	var leg := skeleton.find_bone("LeftUpperLeg")
	check(skeleton.get_bone_pose_rotation(leg).is_equal_approx(driver._animation_bones["LeftUpperLeg"]),
		"A tracked lower body must keep the animation/rest leg pose")
	scene_root.free()


func _test_character_body_exclusion() -> void:
	var scene_root := Node3D.new()
	root.add_child(scene_root)
	var floor := add_floor(scene_root)
	var player := CharacterBody3D.new()
	player.name = "Player"
	player.collision_layer = 1
	player.collision_mask = 0
	var body_shape := CollisionShape3D.new()
	var body_box := BoxShape3D.new()
	body_box.size = Vector3(1, 0.3, 1)
	body_shape.shape = body_box
	body_shape.position = Vector3(0, 0.2, 0)
	player.add_child(body_shape)
	scene_root.add_child(player)
	var rig := build_rig(player, build_model())
	var driver = rig.driver
	await settle(12)
	var feet = driver.ground_feet
	if feet == null:
		check(false, "Ground helper was not built for the exclusion test")
		scene_root.free()
		return
	for side in ["left", "right"]:
		var hit: Dictionary = feet.ground_hit.get(side, {})
		check(hit.get("collider", null) == floor,
			"Own CharacterBody3D must be excluded from the ground probe (" + side + ")")
	player.velocity.y = 1.0
	await settle(2)
	check(not feet.leg_ik.left.active, "Upward jump velocity must release feet immediately")
	player.velocity = Vector3.ZERO
	var records := watch_feet(driver)
	await settle(8)
	var sole: float = float(feet.sole_offset.get("left", 0.0))
	check(absf(records["left"]["ankle"].y - sole) < 0.02,
		"Excluding the player body must leave the foot on the real floor, got " + str(records["left"]["ankle"].y))
	scene_root.free()


func _test_airborne() -> void:
	var scene_root := Node3D.new()
	root.add_child(scene_root)
	add_floor(scene_root)
	var rig := build_rig(scene_root, build_model())
	await settle(8)
	rig.container.position.y = 0.8
	await settle(8)
	for side in ["left", "right"]:
		check(not rig.driver.ground_feet.leg_ik[side].active, "Airborne body must not pin feet to the floor")
	rig.container.position.y = 0
	await settle(8)
	for side in ["left", "right"]:
		check(rig.driver.ground_feet.grounded[side], "Landing must restore ground placement")
	rig.driver.set_ground_ik(false)
	await settle(2)
	check(not rig.driver.ground_feet.leg_ik.left.active, "Disabled ground IK must not retain contact")
	rig.driver.set_ground_ik(true)
	await settle(8)
	check(rig.driver.ground_feet.grounded.left, "Re-enabled ground IK must recover")
	scene_root.free()


func _test_bundled_avatar() -> void:
	var request: AvatarLoadRequest = root.get_node("AvatarService").acquire("godette")
	if not request.finished:
		await request.completed
	check(request.scene != null, "Bundled avatar must load for real-rig ground coverage")
	if request.scene == null:
		request.release()
		return
	var scene_root := Node3D.new()
	root.add_child(scene_root)
	add_floor(scene_root)
	var rig := build_rig(scene_root, request.scene.instantiate())
	request.release()
	await settle(12)
	var feet = rig.driver.ground_feet
	var records := watch_feet(rig.driver)
	await settle(4)
	for side in ["left", "right"]:
		check(feet.grounded.get(side, false), "Bundled avatar foot must find the ground: " + side)
		var sole: float = feet.sole_offset[side] * world_scale(rig.driver)
		check(absf(records[side].ankle.y - sole) < 0.025, "Bundled avatar sole must touch the floor: " + side + " ankle " + str(records[side].ankle.y) + " sole " + str(sole))
	scene_root.free()


func _test_walk_and_teleport() -> void:
	var scene_root := Node3D.new()
	root.add_child(scene_root)
	add_floor(scene_root)
	var rig := build_rig(scene_root, build_model(), false, false)
	await settle(8)
	var stance_frames := 0
	var swing_frames := 0
	for frame in 60:
		rig.container.position.z += 0.04
		await settle(1)
		for side in ["left", "right"]:
			if rig.driver.ground_feet.leg_ik[side].active:
				stance_frames += 1
			else:
				swing_frames += 1
	check(stance_frames > 0 and swing_frames > 0, "Walking must alternate planted stance and free animation swing")
	rig.container.position.x += 4.0
	await settle(8)
	var feet = rig.driver.ground_feet
	for side in ["left", "right"]:
		check(feet.foot_target[side].global_position.distance_to(rig.container.global_position) < 1.0, "Teleport must discard old foot locks")
	scene_root.free()


func _test_deep_crouch() -> void:
	var scene_root := Node3D.new()
	root.add_child(scene_root)
	add_floor(scene_root)
	var rig := build_rig(scene_root, build_model())
	await settle(10)
	var records := watch_feet(rig.driver)
	await settle(2)
	var planted: Vector3 = records.left.ankle
	for height in [1.5, 1.3, 1.1, 0.95, 1.1, 1.4, 1.7]:
		rig.head.position.y = height
		await settle(6)
		var feet = rig.driver.ground_feet
		for side in ["left", "right"]:
			check(feet.grounded.get(side, false) and feet.leg_ik[side].active, "Crouching must not release ground IK at eye height " + str(height))
			var ankle: Vector3 = records[side].ankle
			check(absf(ankle.y - float(feet.sole_offset[side])) < 0.015, "Crouched soles must stay on the floor")
		check(Vector2(records.left.ankle.x - planted.x, records.left.ankle.z - planted.z).length() < 0.015, "Crouching must preserve the standing foot lock")
		var look := rig.driver.avatar_model.find_child("LookOffset", true, false) as Node3D
		check(look.global_position.distance_to(rig.head.global_position) < 0.002, "Crouch IK must preserve tracked eyes")
	scene_root.free()
