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
	await _test_avatar_fingers()
	_test_eye_alignment()
	_test_idle_clip_data()
	_test_desktop_animation()
	_test_locomotion_clips()
	_test_rest_bases()
	_test_procedural_fallback()
	await _test_vr_lower_body_idle()
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

	if driver._wrist_modifier != null:
		driver._wrist_modifier.modification_processed.connect(func() -> void:
			for side in driver.hand_target:
				var hand := skeleton.find_bone("LeftHand" if side == "left" else "RightHand")
				if _poses.has(side):
					_poses[side].hand = skeleton.global_transform * skeleton.get_bone_global_pose(hand)
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
	# A neutral anchor must leave the head's world orientation alone. The torso
	# now idles, so the head counter-rotates in local space to cancel it; that
	# compensation must not turn the head away from the camera.
	var rest_head_global: Quaternion = driver.skeleton.get_bone_global_rest(head_bone).basis.get_rotation_quaternion()
	var neutral_head: Quaternion = driver.skeleton.get_bone_global_pose(head_bone).basis.get_rotation_quaternion()
	var neutral_delta: float = neutral_head.angle_to(rest_head_global)
	check(neutral_delta < deg_to_rad(1.0),
		"Neutral anchor must not rotate the head, delta " + str(rad_to_deg(neutral_delta)) + " degrees")

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
	left.basis = Basis.from_euler(Vector3(0.4, -0.6, 0.7))
	left.position = Vector3(-0.2, 1.2, -0.5)
	await process_frame
	await process_frame
	var rotated_hand: Transform3D = _poses.get("left", {}).get("hand", Transform3D.IDENTITY)
	check(rotated_hand.origin.distance_to(left.global_position) < 0.002, "Tracked wrist translation must reach the target after arm IK")
	check(rotated_hand.basis.get_rotation_quaternion().angle_to(left.global_basis.get_rotation_quaternion()) < 0.01, "Tracked wrist rotation must be applied after arm IK")
	head.rotation.x = -PI / 2.0
	await process_frame
	await process_frame
	var chest_index: int = driver.skeleton.find_bone("Chest")
	var chest_position: Vector3 = driver.skeleton.global_transform * driver.skeleton.get_bone_global_pose(chest_index).origin
	check((chest_position - head.global_position).dot(Vector3.BACK) > 0.09, "Looking down must leave the chest behind the camera")
	check(look.global_position.distance_to(head.global_position) < 0.002, "VR body offset must keep the eyes aligned to the tracked head")
	var body_position: Vector3 = model.global_position
	await process_frame
	await process_frame
	check(model.global_position.distance_to(body_position) < 0.001, "VR body/head compensation must not accumulate across frames")

	var remote := build_rig(build_fixture_model(), false, false)
	var remote_driver = remote["driver"]
	check(mesh_by_name(remote["model"], "Body").layers == 1, "Remote third person mesh must render on layer 1")
	check(mesh_by_name(remote["model"], "Body (Headless)").layers == 0, "Remote first person mesh must not render")
	remote_driver.set_control_mode(true)
	watch_ik(remote_driver, remote_driver.skeleton)
	remote.left.transform = Transform3D(Basis.from_euler(Vector3(-0.2, 0.5, 0.3)), Vector3(0.1, 1.0, -0.4))
	await process_frame
	await process_frame
	var remote_hand: Transform3D = _poses.get("left", {}).get("hand", Transform3D.IDENTITY)
	check(remote_hand.origin.distance_to(remote.left.global_position) < 0.002 and remote_hand.basis.get_rotation_quaternion().angle_to(remote.left.global_basis.get_rotation_quaternion()) < 0.01, "Remote VR wrists must apply replicated position and rotation")
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
	# Run authored locomotion on the real imported rig, including its native
	# arm modifiers and eye attachment, not just the synthetic bone fixture.
	driver.set_control_mode(false)
	driver.set_process(false)
	var foot: int = driver.skeleton.find_bone("LeftFoot")
	var foot_start: Vector3 = driver.skeleton.get_bone_global_pose(foot).origin
	var foot_motion := 0.0
	for frame in 45:
		container.position.z -= 3.0 / 60.0
		driver._process(1.0 / 60.0)
		await process_frame
		foot_motion = maxf(foot_motion, driver.skeleton.get_bone_global_pose(foot).origin.distance_to(foot_start))
		if look != null:
			check(look.global_position.distance_to(head.global_position) < 0.01, "Bundled avatar's walking must keep its eyes on the anchor")
	check(foot_motion > 0.05, "Authored locomotion must move the real avatar's feet")
	container.free()


func _test_desktop_animation() -> void:
	var rig := build_rig(build_fixture_model(), false, false)
	var driver = rig.driver
	var container: Node3D = rig.container
	var skeleton: Skeleton3D = driver.skeleton
	driver.set_process(false)
	check(driver._idle_clip != null, "Desktop rig must load the CC0 idle tracks")
	driver._process(1.0 / 60.0)
	var spine := skeleton.find_bone("Spine")
	var leg := skeleton.find_bone("LeftUpperLeg")
	var idle_start: Quaternion = skeleton.get_bone_pose_rotation(spine)
	var idle_variation := 0.0
	var max_hand_reach := {"left": 0.0, "right": 0.0}
	var idle_hand_start := {
		"left": driver.hand_target.left.transform.origin,
		"right": driver.hand_target.right.transform.origin,
	}
	var idle_hand_swing := 0.0
	for frame in 90:
		driver._process(1.0 / 60.0)
		idle_variation = maxf(idle_variation, skeleton.get_bone_pose_rotation(spine).angle_to(idle_start))
		for side in ["left", "right"]:
			var upper := skeleton.find_bone("LeftUpperArm" if side == "left" else "RightUpperArm")
			var reach: float = driver.hand_target[side].transform.origin.distance_to(driver._pose_global(upper).origin)
			max_hand_reach[side] = maxf(max_hand_reach[side], reach)
			idle_hand_swing = maxf(idle_hand_swing,
				driver.hand_target[side].transform.origin.distance_to(idle_hand_start[side]))
	for side in ["left", "right"]:
		var arm_length: float = driver._arm_lengths[side]
		check(max_hand_reach[side] <= arm_length * driver.DESKTOP_REACH + 0.001,
			"Idle wrist target must stay short of full stretch (" + side + ")")
	check(idle_hand_swing > 0.002 and idle_hand_swing < 0.12,
		"Idle hands must sway subtly, got " + str(idle_hand_swing))
	check(idle_variation > deg_to_rad(0.1), "Desktop idle must keep varying over the loop")
	var rest_spine: Quaternion = driver._animation_bones["Spine"]
	check(skeleton.get_bone_pose_rotation(spine).angle_to(rest_spine) < deg_to_rad(8.0),
		"Idle torso must stay close to this avatar's rest stance")
	var idle_leg_angle: float = skeleton.get_bone_pose_rotation(leg).angle_to(driver._animation_bones["LeftUpperLeg"])
	check(idle_leg_angle < deg_to_rad(8.0), "Idle legs must stay restrained")
	var maximum_leg_angle := 0.0
	var maximum_hand_swing := 0.0
	for frame in 60:
		container.position.z -= 3.0 / 60.0
		driver._process(1.0 / 60.0)
		maximum_leg_angle = maxf(maximum_leg_angle, skeleton.get_bone_pose_rotation(leg).get_angle())
		maximum_hand_swing = maxf(maximum_hand_swing, driver.hand_target.left.position.distance_to(driver._desktop_target.left.origin))
	check(maximum_leg_angle > 0.2, "Moving desktop avatars must step their legs")
	check(maximum_hand_swing > 0.05, "Desktop walking must swing the hands")
	for frame in 120:
		driver._process(1.0 / 60.0)
	var stopped_leg_angle: float = skeleton.get_bone_pose_rotation(leg).angle_to(driver._animation_bones["LeftUpperLeg"])
	check(stopped_leg_angle < deg_to_rad(8.0),
		"Stopping must blend the legs back to the restrained idle, got " + str(rad_to_deg(stopped_leg_angle)))
	container.position.x += 100.0
	driver._process(1.0 / 60.0)
	check(driver._motion_velocity.is_zero_approx(), "Teleporting must reset locomotion velocity")
	container.free()


func _test_locomotion_clips() -> void:
	var rig := build_rig(build_fixture_model(), false, false)
	var driver = rig.driver
	var skeleton: Skeleton3D = driver.skeleton
	driver.set_process(false)
	check(driver._walk_clip != null and driver._jog_clip != null, "Authored walk and jog tracks must be shipped")
	for clip: RefCounted in [driver._walk_clip, driver._jog_clip]:
		if clip == null:
			continue
		check(clip.source.get("license") == "CC0-1.0", "Locomotion provenance must retain its license")
		for track: StringName in clip.tracks:
			check(clip.sample_direction(track, 0.0).distance_to(clip.sample_direction(track, clip.duration - 0.00001)) < 0.002, "Locomotion loop must close without a pose jump: " + str(track))
		for side in ["left", "right"]:
			for step in 30:
				check(clip.sample_wrist(side, float(step) / 30.0 * clip.duration).length() <= 1.01, "Bent source elbows must not exaggerate normalized wrist reach")
	# Exercise walking, jogging, diagonal movement and backpedaling without
	# moving the head anchor or exceeding the target avatar's arm reach.
	for velocity in [Vector3(0, 0, -0.4), Vector3(0, 0, -1.5), Vector3(0, 0, -5.0), Vector3(2, 0, 0), Vector3(0, 0, 2), Vector3(2, 0, -2)]:
		for frame in 45:
			rig.container.position += velocity / 60.0
			driver._process(1.0 / 60.0)
			for side in ["left", "right"]:
				var upper := skeleton.find_bone("LeftUpperArm" if side == "left" else "RightUpperArm")
				var target: Vector3 = driver.hand_target[side].position
				check(target.is_finite(), "Directional locomotion must keep finite wrist targets")
				check(target.distance_to(driver._pose_global(upper).origin) <= float(driver._arm_lengths[side]) * driver.DESKTOP_REACH + 0.001, "Walk/jog blending must keep wrists within the avatar's reach")
			for bone in skeleton.get_bone_count():
				check(skeleton.get_bone_pose_rotation(bone).is_finite(), "Locomotion retargeting must keep finite bone poses")
		var head_bone := skeleton.find_bone("Head")
		var eye: Vector3 = skeleton.global_transform * (skeleton.get_bone_global_pose(head_bone) * driver._eye_offset)
		check(eye.distance_to(driver.head_anchor.global_position) < 0.001, "Authored locomotion must preserve the authoritative eye anchor")
	# No accumulated root motion after stopping; changing control modes also
	# resets cadence instead of leaking a desktop gait into tracked VR.
	driver.set_control_mode(true)
	check(is_zero_approx(driver._stride_phase) and driver._motion_velocity.is_zero_approx(), "Entering VR must clear desktop cadence")
	rig.container.free()


func _test_idle_clip_data() -> void:
	var script := load("res://avatar/animations/avatar_idle_clip.gd")
	check(script != null, "Idle clip helper must be present")
	if script == null:
		return
	var clip = script.new()
	check(clip.load_file(), "Idle clip data must load: " + str(clip.error))
	check(clip.duration > 1.0 and clip.sample_count > 30, "Idle clip must span a usable loop")
	for bone_name in ["Hips", "Spine", "Chest", "UpperChest", "LeftUpperLeg", "RightUpperLeg", "LeftFoot"]:
		check(clip.has_track(StringName(bone_name)), "Idle clip is missing " + bone_name)
	check(clip.has_wrist("left") and clip.has_wrist("right"), "Idle clip is missing wrist offsets")
	var frames: Array = clip.tracks[StringName("Hips")]["frames"]
	var moved := 0.0
	for index in range(1, frames.size()):
		moved = maxf(moved, absf(frames[index].angle_to(frames[0])))
	check(moved > deg_to_rad(0.2), "Idle clip must contain real motion")
	check(absf(clip.sample_wrist("left", 0.0).length() - 1.0) < 0.15, "Wrist offsets must be arm-length normalized")
	check(String(clip.source.get("license", "")) == "CC0-1.0", "Idle clip provenance must record its CC0 license")


func _test_rest_bases() -> void:
	var model := build_fixture_model()
	var skeleton := model.get_node("GeneralSkeleton") as Skeleton3D
	for bone_name in ["Spine", "Chest", "LeftUpperLeg", "RightUpperLeg"]:
		var bone := skeleton.find_bone(bone_name)
		var rest := skeleton.get_bone_rest(bone)
		rest.basis = rest.basis * Basis(Vector3.FORWARD, 0.35)
		skeleton.set_bone_rest(bone, rest)
	skeleton.reset_bone_poses()
	var rig := build_rig(model, true, false)
	var driver = rig.driver
	driver.set_process(false)
	for frame in 60:
		driver._process(1.0 / 60.0)
	for bone_name in ["Spine", "Chest", "LeftUpperLeg", "RightUpperLeg"]:
		var bone := skeleton.find_bone(bone_name)
		var rest_pose: Quaternion = skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
		var delta: float = skeleton.get_bone_pose_rotation(bone).angle_to(rest_pose)
		check(delta < deg_to_rad(8.0),
			"Clip must add motion around a rotated rest base, not replace it (" + bone_name + " " + str(rad_to_deg(delta)) + " degrees)")
	rig.container.free()


func _test_procedural_fallback() -> void:
	var rig := build_rig(build_fixture_model(), false, false)
	var driver = rig.driver
	var skeleton: Skeleton3D = driver.skeleton
	driver.set_process(false)
	driver._idle_clip = null
	driver._process(1.0 / 60.0)
	var spine := skeleton.find_bone("Spine")
	var leg := skeleton.find_bone("LeftUpperLeg")
	var start: Quaternion = skeleton.get_bone_pose_rotation(spine)
	var variation := 0.0
	# Five seconds of the slow sway, so the check cannot land near a turnaround
	# of the desynchronized idle phase.
	for frame in 300:
		driver._process(1.0 / 60.0)
		variation = maxf(variation, skeleton.get_bone_pose_rotation(spine).angle_to(start))
	check(variation > deg_to_rad(0.1), "Procedural fallback must still animate standing")
	var leg_delta: float = skeleton.get_bone_pose_rotation(leg).angle_to(driver._animation_bones["LeftUpperLeg"])
	check(leg_delta < deg_to_rad(8.0), "Procedural fallback legs must stay restrained")
	rig.container.free()


func _test_vr_lower_body_idle() -> void:
	var rig := build_rig(build_fixture_model(), true, true)
	var driver = rig.driver
	var skeleton: Skeleton3D = driver.skeleton
	var head: Node3D = rig.head
	var look := rig.model.find_child("LookOffset", true, false) as Node3D
	driver.set_process(false)
	var foot := skeleton.find_bone("LeftFoot")
	var leg := skeleton.find_bone("LeftUpperLeg")
	var foot_start := Vector3.ZERO
	var max_eye_error := 0.0
	var max_foot_drift := 0.0
	var max_leg_angle := 0.0
	for frame in 120:
		driver._process(1.0 / 60.0)
		await process_frame
		if look != null:
			max_eye_error = maxf(max_eye_error, look.global_position.distance_to(head.global_position))
		var foot_position: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(foot).origin
		if frame == 0:
			foot_start = foot_position
		else:
			max_foot_drift = maxf(max_foot_drift, foot_position.distance_to(foot_start))
		max_leg_angle = maxf(max_leg_angle,
			skeleton.get_bone_pose_rotation(leg).angle_to(driver._animation_bones["LeftUpperLeg"]))
	check(max_eye_error < 0.002, "VR lower-body idle must not move the tracked eye anchor, got " + str(max_eye_error))
	check(max_leg_angle > deg_to_rad(0.1), "Untracked VR legs must receive restrained idle motion")
	check(max_leg_angle < deg_to_rad(8.0), "VR leg idle must stay restrained, got " + str(rad_to_deg(max_leg_angle)))
	check(max_foot_drift < 0.08, "VR idle feet must stay reasonably planted, drifted " + str(max_foot_drift))
	var spine := skeleton.find_bone("Spine")
	check(skeleton.get_bone_pose_rotation(spine).is_equal_approx(driver._animation_bones["Spine"]),
		"VR fallback must not animate the spine")
	check(driver.hand_target.left.global_position.distance_to(rig.left.global_position) < 0.001,
		"VR fallback must keep tracked hand targets authoritative")
	driver.lower_body_tracked = true
	driver.set_control_mode(true)
	driver._process(1.0 / 60.0)
	await process_frame
	check(skeleton.get_bone_pose_rotation(skeleton.find_bone("LeftUpperLeg")).is_equal_approx(driver._animation_bones["LeftUpperLeg"]),
		"A wired lower body must be left untouched by the fallback")
	rig.container.free()


func _test_eye_alignment() -> void:
	var model := build_fixture_model()
	var skeleton := model.get_node("GeneralSkeleton") as Skeleton3D
	var head := skeleton.find_bone("Head")
	model.find_child("LookOffset", true, false).position = Vector3.ZERO
	check(AvatarEyes.offset(model, skeleton).y > 0.05, "Missing viewpoint offsets must place the camera above the head joint")
	for side in ["Left", "Right"]:
		skeleton.add_bone(side + "Eye")
		var eye := skeleton.find_bone(side + "Eye")
		skeleton.set_bone_parent(eye, head)
		skeleton.set_bone_rest(eye, Transform3D(Basis.IDENTITY, Vector3(0.03 if side == "Left" else -0.03, 0.12, 0.1)))
		skeleton.reset_bone_pose(eye)
	AvatarScale.normalize(model)
	var normalized_eyes := skeleton.get_bone_global_rest(head) * AvatarEyes.offset(model, skeleton)
	check(absf(normalized_eyes.y - 1.7) < 0.001, "Avatar scaling must use the same eye midpoint as the rig")
	var rig := build_rig(model, true, false)
	var driver = rig.driver
	driver.set_process(false)
	driver._process(1.0 / 60.0)
	var eye_midpoint := (skeleton.get_bone_global_pose(skeleton.find_bone("LeftEye")).origin + skeleton.get_bone_global_pose(skeleton.find_bone("RightEye")).origin) * 0.5
	check((skeleton.global_transform * eye_midpoint).distance_to(rig.head.global_position) < 0.001, "The actual eye midpoint must align with the camera")
	rig.head.rotation.x = 0.4
	driver._process(1.0 / 60.0)
	eye_midpoint = (skeleton.get_bone_global_pose(skeleton.find_bone("LeftEye")).origin + skeleton.get_bone_global_pose(skeleton.find_bone("RightEye")).origin) * 0.5
	check((skeleton.global_transform * eye_midpoint).distance_to(rig.head.global_position) < 0.001, "Looking down must preserve eye alignment")
	rig.container.free()


func _test_avatar_fingers() -> void:
	var model := build_fixture_model()
	var skeleton := model.get_node("GeneralSkeleton") as Skeleton3D
	var hand := skeleton.find_bone("LeftHand")
	skeleton.add_bone("LeftPalm")
	skeleton.set_bone_parent(skeleton.find_bone("LeftPalm"), hand)
	for finger in ["Thumb", "Index", "Middle", "Ring", "Little"]:
		var parent := hand
		var parts := ["Metacarpal", "Proximal", "Distal", "Tip"] if finger == "Thumb" else ["Metacarpal", "Proximal", "Intermediate", "Distal", "Tip"]
		for part in parts:
			var name: String = "Left" + finger + part
			skeleton.add_bone(name)
			var bone := skeleton.find_bone(name)
			skeleton.set_bone_parent(bone, parent)
			skeleton.set_bone_rest(bone, Transform3D(Basis.IDENTITY, Vector3(0, 0.03, 0)))
			parent = bone
	skeleton.reset_bone_poses()
	var tracker := XRHandTracker.new()
	tracker.name = "/user/hand_tracker/left"
	tracker.hand = XRPositionalTracker.TRACKER_HAND_LEFT
	tracker.has_tracking_data = true
	tracker.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
	for joint in XRHandTracker.HAND_JOINT_MAX:
		tracker.set_hand_joint_transform(joint, Transform3D.IDENTITY)
		tracker.set_hand_joint_flags(joint, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID)
	tracker.set_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL + 1, Transform3D(Basis(Vector3.RIGHT, 0.4), Vector3.ZERO))
	XRServer.add_tracker(tracker)
	var rig := build_rig(model, true, true)
	var driver = rig.driver
	var modifier: XRHandModifier3D = driver._finger_modifiers.left
	var observed := [Quaternion.IDENTITY]
	var index := skeleton.find_bone("LeftIndexProximal")
	modifier.modification_processed.connect(func(): observed[0] = skeleton.get_bone_pose_rotation(index))
	await process_frame
	await process_frame
	check(modifier.active, "Avatar finger tracking must activate for local tracked hands")
	check(observed[0].angle_to(Quaternion(Vector3.RIGHT, 0.4)) < 0.01, "Finger rotations must reach the avatar skeleton")
	check(skeleton.get_bone_pose_position(index).is_equal_approx(Vector3(0, 0.03, 0)), "Finger tracking must preserve avatar bone lengths")
	driver.set_control_mode(false)
	await process_frame
	check(not modifier.active, "Desktop mode must disable optical finger modifiers")
	XRServer.remove_tracker(tracker)
	rig.container.free()
