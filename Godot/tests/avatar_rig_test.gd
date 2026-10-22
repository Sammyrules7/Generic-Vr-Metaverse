extends SceneTree
## Headless coverage for the VRM avatar rig driver.
##
## The synthetic fixture mirrors the importer's output: a %GeneralSkeleton with
## normalized humanoid bones, a third person mesh on layer 1 and a first person
## headless duplicate on layer 2. The bundled VRM is exercised as well so the
## real importer output is covered too.

var failures := 0
## Bone poses captured inside the native modifier pass; the engine restores the
## pre-modifier poses once the skin has been updated.
var _poses := {}

const FIXTURE_BONES := [
	["Hips", -1, Vector3(0, 0.95, 0)],
	["Spine", 0, Vector3(0, 0.1, 0)],
	["Chest", 1, Vector3(0, 0.2, 0)],
	["Neck", 2, Vector3(0, 0.2, 0)],
	["Head", 3, Vector3(0, 0.1, 0)],
	["LeftUpperArm", 2, Vector3(0.15, 0.15, 0)],
	["LeftLowerArm", 5, Vector3(0.3, 0, 0)],
	["LeftHand", 6, Vector3(0.25, 0, 0)],
	["RightUpperArm", 2, Vector3(-0.15, 0.15, 0)],
	["RightLowerArm", 8, Vector3(-0.3, 0, 0)],
	["RightHand", 9, Vector3(-0.25, 0, 0)],
	["LeftUpperLeg", 0, Vector3(0.1, -0.05, 0)],
	["LeftLowerLeg", 11, Vector3(0, -0.4, 0)],
	["LeftFoot", 12, Vector3(0, -0.45, 0)],
	["LeftToes", 13, Vector3(0, 0, 0.15)],
	["RightUpperLeg", 0, Vector3(-0.1, -0.05, 0)],
	["RightLowerLeg", 15, Vector3(0, -0.4, 0)],
	["RightFoot", 16, Vector3(0, -0.45, 0)],
	["RightToes", 17, Vector3(0, 0, 0.15)],
]


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func run() -> void:
	await _test_synthetic_fixture()
	await _test_bundled_vrm()
	print("AVATAR_RIG_TEST failures=", failures)
	quit(1 if failures else 0)


# Fixture


func build_fixture_model() -> Node3D:
	var model := Node3D.new()
	model.name = "Model"
	var skeleton := Skeleton3D.new()
	skeleton.name = "GeneralSkeleton"
	model.add_child(skeleton)
	for entry in FIXTURE_BONES:
		skeleton.add_bone(entry[0])
		skeleton.set_bone_parent(skeleton.find_bone(entry[0]), entry[1])
		skeleton.set_bone_rest(skeleton.find_bone(entry[0]), Transform3D(Basis.IDENTITY, entry[2]))
	skeleton.reset_bone_poses()
	# The importer stores the eye position in a LookOffset node below the head
	# bone attachment.
	var attachment := BoneAttachment3D.new()
	attachment.name = "Head"
	attachment.bone_name = "Head"
	skeleton.add_child(attachment)
	var look := Node3D.new()
	look.name = "LookOffset"
	attachment.add_child(look)
	look.position = Vector3(0, 0.08, 0.1)
	# The importer writes the third person mesh on layer 1 and the headless
	# duplicate on the first person layer.
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
	# The container builds the driver the same way, so the script has to work
	# without the global class cache.
	var driver := Node3D.new()
	driver.set_script(load("res://avatar/avatar_rig_driver.gd"))
	return driver


func build_rig(model: Node3D, local: bool, vr: bool) -> Dictionary:
	var container := Node3D.new()
	container.name = "Avatar"
	root.add_child(container)
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


func watch_ik(driver, skeleton: Skeleton3D) -> void:
	for side in driver.arm_ik:
		var ik: SkeletonModifier3D = driver.arm_ik[side]
		var key := str(side)
		var hand := skeleton.find_bone("LeftHand" if side == "left" else "RightHand")
		var elbow := skeleton.find_bone("LeftLowerArm" if side == "left" else "RightLowerArm")
		ik.modification_processed.connect(func() -> void:
			# The bone poses are skeleton local, the world transform turns them
			# into the space the anchors live in.
			var world := skeleton.global_transform
			_poses[key] = {
				"hand": world * skeleton.get_bone_global_pose(hand),
				"elbow": world * skeleton.get_bone_global_pose(elbow),
			}
		)


func mesh_by_name(model: Node3D, mesh_name: String) -> MeshInstance3D:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.name == mesh_name:
			return mesh
	return null


# Synthetic fixture


func _test_synthetic_fixture() -> void:
	_poses.clear()
	var rig := build_rig(build_fixture_model(), true, false)
	var driver = rig["driver"]
	var model: Node3D = rig["model"]
	var head: Node3D = rig["head"]
	var left: Node3D = rig["left"]
	check(driver.skeleton != null, "Driver did not bind the humanoid skeleton")
	check(driver.process_priority > 5, "Driver must run after the container pose update")
	var body := mesh_by_name(model, "Body")
	var headless := mesh_by_name(model, "Body (Headless)")
	check(body != null and headless != null, "Fixture meshes are missing")
	if body == null or headless == null:
		return
	# The local player sees its own headless body and never its own head.
	check(headless.layers == 0, "Desktop must not draw the first-person body")
	check(body.layers == AvatarView.FULL_BODY, "Local full avatar must remain available to mirrors")
	var camera := Camera3D.new()
	AvatarView.configure_player_camera(camera, false)
	check((camera.cull_mask & body.layers) == 0, "Desktop camera must hide the local avatar")
	AvatarView.configure_mirror_camera(camera)
	check((camera.cull_mask & body.layers) != 0, "Mirror camera must show the full local avatar")
	driver.set_control_mode(true)
	AvatarView.configure_player_camera(camera, true)
	check((camera.cull_mask & body.layers) == 0, "VR camera must not see the full head")
	check((camera.cull_mask & headless.layers) != 0, "VR camera must see the headless body")
	AvatarView.configure_mirror_camera(camera)
	check((camera.cull_mask & headless.layers) == 0, "Mirror must not draw the duplicate first-person body")
	camera.free()
	driver.set_control_mode(false)
	watch_ik(driver, driver.skeleton)

	await process_frame
	await process_frame
	var look := driver.avatar_model.find_child("LookOffset", true, false) as Node3D
	check(look != null, "Fixture is missing the eye anchor")
	var head_bone: int = driver.skeleton.find_bone("Head")
	if look != null:
		check(look.global_position.distance_to(Vector3(0, 1.7, 0)) < 0.001,
			"Eyes must sit on the head anchor, got " + str(look.global_position))
	# A neutral anchor must leave the imported head pose alone: the model may
	# be authored facing any way, the head must not be counter rotated.
	var rest_rotation: Quaternion = driver.skeleton.get_bone_rest(head_bone).basis.get_rotation_quaternion()
	var neutral_delta: float = driver.skeleton.get_bone_pose_rotation(head_bone).angle_to(rest_rotation)
	check(neutral_delta < 0.01,
		"Neutral anchor must not rotate the head, delta " + str(rad_to_deg(neutral_delta)) + " degrees")
	var neutral_head: Quaternion = driver.skeleton.get_bone_global_pose(head_bone).basis.get_rotation_quaternion()

	# Moving the head anchor moves the body with it.
	head.transform = Transform3D(Basis.IDENTITY, Vector3(0.3, 1.5, -0.2))
	await process_frame
	await process_frame
	if look != null:
		check(look.global_position.distance_to(Vector3(0.3, 1.5, -0.2)) < 0.001,
			"Eyes must follow the moved anchor, got " + str(look.global_position))

	# Turning the anchor turns the body: the fixture faces +Z in model space.
	head.transform = Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(0.3, 1.5, -0.2))
	await process_frame
	await process_frame
	var facing: Vector3 = model.transform.basis * Vector3(0, 0, 1)
	facing.y = 0.0
	check(facing.normalized().distance_to(Vector3(-1, 0, 0)) < 0.01,
		"Body yaw must follow the anchor look direction, got " + str(facing))
	if look != null:
		check(look.global_position.distance_to(Vector3(0.3, 1.5, -0.2)) < 0.001,
			"Eyes must stay on the anchor while turning")
		var head_pose: Transform3D = driver.skeleton.global_transform * driver.skeleton.get_bone_global_pose(head_bone)
		var expected := look.global_position - model.global_transform.basis * Vector3(0, 0.08, 0.1)
		check(head_pose.origin.distance_to(expected) < 0.005,
			"Head bone must follow the eyes, got " + str(head_pose.origin) + " expected " + str(expected))

	# Desktop hands must not stay in the imported T-pose.
	var heading_before := model.basis
	head.basis = Basis(Vector3.UP, PI / 2.0) * Basis(Vector3.RIGHT, PI / 2.0)
	await process_frame
	await process_frame
	check(model.basis.is_equal_approx(heading_before), "Looking straight down must retain torso heading")
	head.basis = Basis(Vector3.UP, PI / 2.0)
	await process_frame
	await process_frame
	var left_hand_pose: Transform3D = _poses.get("left", {}).get("hand", Transform3D.IDENTITY)
	var shoulder: Vector3 = driver.skeleton.global_transform * driver.skeleton.get_bone_global_pose(driver.skeleton.find_bone("LeftUpperArm")).origin
	check(left_hand_pose.origin.y < shoulder.y - 0.3,
		"Desktop arm must hang down instead of the T-pose, hand " + str(left_hand_pose.origin) + " shoulder " + str(shoulder))

	# Tracked hands bind to the container anchors.
	driver.set_control_mode(true)
	# Looking down has to pitch the head by the same amount.
	head.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(30.0)), Vector3(0.3, 1.5, -0.2))
	await process_frame
	await process_frame
	var pitched: Quaternion = driver.skeleton.get_bone_global_pose(head_bone).basis.get_rotation_quaternion()
	var pitch_delta: float = rad_to_deg(pitched.angle_to(neutral_head))
	check(absf(pitch_delta - 30.0) < 1.0,
		"Head must pitch with the anchor, got " + str(pitch_delta) + " degrees")
	head.transform = Transform3D(Basis.IDENTITY, Vector3(0.3, 1.5, -0.2))
	await process_frame
	await process_frame
	left.transform = Transform3D(Basis.IDENTITY, Vector3(-0.15, 1.25, 0.15))
	await process_frame
	await process_frame
	await process_frame
	left_hand_pose = _poses.get("left", {}).get("hand", Transform3D.IDENTITY)
	check(left_hand_pose.origin.distance_to(Vector3(-0.15, 1.25, 0.15)) < 0.02,
		"Tracked hand must reach its anchor, got " + str(left_hand_pose.origin) + " expected " + str(Vector3(-0.15, 1.25, 0.15)))

	# The IK modifiers have to run before any spring bone installed later.
	var late_spring := SkeletonModifier3D.new()
	driver.skeleton.add_child(late_spring)
	var ik_index := -1
	var spring_index := -1
	for index in driver.skeleton.get_child_count():
		var child: Node = driver.skeleton.get_child(index)
		if child is SkeletonModifier3D:
			if child is TwoBoneIK3D:
				ik_index = index if ik_index < 0 else mini(ik_index, index)
			else:
				spring_index = index if spring_index < 0 else mini(spring_index, index)
	check(ik_index >= 0, "Native IK modifiers are missing")
	check(spring_index < 0 or ik_index < spring_index,
		"Native IK must run before the spring bones")
	driver.skeleton.remove_child(late_spring)
	late_spring.free()

	# A remote player keeps its head and loses the headless duplicate.
	var remote := build_rig(build_fixture_model(), false, false)
	var remote_driver = remote["driver"]
	check(mesh_by_name(remote["model"], "Body").layers == 1, "Remote third person mesh must render on layer 1")
	check(mesh_by_name(remote["model"], "Body (Headless)").layers == 0, "Remote first person mesh must not render")
	remote_driver.restore_original_layers()
	check(mesh_by_name(remote["model"], "Body (Headless)").layers == 2,
		"Original layers must be restorable for the preview")

	rig["container"].free()
	remote["container"].free()


# Bundled VRM


func _test_bundled_vrm() -> void:
	_poses.clear()
	var service := root.get_node_or_null("AvatarService")
	if service == null:
		print("AVATAR_RIG_TEST bundled VRM skipped: no avatar service")
		return
	var request = service.acquire("godette")
	var deadline := Time.get_ticks_msec() + 20000
	while not request.finished and Time.get_ticks_msec() < deadline:
		await process_frame
	if not request.finished or request.scene == null:
		request.release()
		check(false, "Bundled VRM did not load: " + str(request.error))
		return
	var scene: PackedScene = request.scene
	request.release()
	var model := scene.instantiate() as Node3D
	var rig := build_rig(model, true, true)
	var driver = rig["driver"]
	var container: Node3D = rig["container"]
	check(driver.skeleton != null, "Bundled VRM has no humanoid skeleton")
	if driver.skeleton == null:
		container.free()
		return
	var head: Node3D = rig["head"]
	head.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.7, 0))
	watch_ik(driver, driver.skeleton)
	await process_frame
	await process_frame
	var head_bone: int = driver.skeleton.find_bone("Head")
	check(head_bone >= 0, "Bundled VRM has no Head bone")
	var look := model.find_child("LookOffset", true, false) as Node3D
	if look != null:
		check(look.global_position.distance_to(Vector3(0, 1.7, 0)) < 0.01,
			"Bundled VRM eyes must sit on the anchor, got " + str(look.global_position))
	else:
		check(false, "Bundled VRM has no eye anchor")
	var headless: MeshInstance3D = null
	var third_person: MeshInstance3D = null
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if str(mesh.get_meta("vrm_first_person_flag", "")) == "head_removed":
			headless = mesh
		else:
			third_person = mesh
	check(headless != null, "Bundled VRM has no first person mesh")
	check(third_person != null, "Bundled VRM has no third person mesh")
	if headless != null:
		check(headless.layers == AvatarView.FIRST_PERSON, "VR body must use the first-person layer")
	if third_person != null:
		check(third_person.layers == AvatarView.FULL_BODY, "Mirror must retain the complete avatar")
	container.free()
