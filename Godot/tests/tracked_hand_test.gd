extends SceneTree
## Fixtures use raw OpenXR joint axes (+Y out of the back, -Z toward the tip).
## They do not derive tracking data from the driver's conversion or mesh rest.

const OPENXR_TO_HUMANOID := Basis(Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0))
const JOINT_BONES := ["Palm", "Hand", "ThumbMetacarpal", "ThumbProximal", "ThumbDistal", "ThumbTip", "IndexMetacarpal", "IndexProximal", "IndexIntermediate", "IndexDistal", "IndexTip", "MiddleMetacarpal", "MiddleProximal", "MiddleIntermediate", "MiddleDistal", "MiddleTip", "RingMetacarpal", "RingProximal", "RingIntermediate", "RingDistal", "RingTip", "LittleMetacarpal", "LittleProximal", "LittleIntermediate", "LittleDistal", "LittleTip"]
const VALID := XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func fixture(side: String, curl: float, hand_basis: Basis) -> Array[Transform3D]:
	var joints: Array[Transform3D] = []
	joints.resize(XRHandTracker.HAND_JOINT_MAX)
	var mirror := 1.0 if side == "left" else -1.0
	joints[XRHandTracker.HAND_JOINT_WRIST] = Transform3D.IDENTITY
	joints[XRHandTracker.HAND_JOINT_PALM] = Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.045))
	for finger in 4:
		var first := XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL + finger * 5
		var position := Vector3((1.5 - finger) * 0.022 * mirror, 0, -0.015)
		for segment in 5:
			var basis := Basis(Vector3.UP, (finger - 1.5) * 0.06 * mirror) * Basis(Vector3.RIGHT, -curl * maxf(0, segment - 1))
			joints[first + segment] = Transform3D(basis, position)
			var length := 0.06 if segment == 0 else (0.025 if segment > 1 else 0.04)
			position += -basis.z * length
	var thumb_position := Vector3(0.015 * mirror, 0, -0.02)
	for segment in 4:
		var basis := Basis(Vector3.UP, -0.75 * mirror) * Basis(Vector3.RIGHT, -curl * segment)
		joints[XRHandTracker.HAND_JOINT_THUMB_METACARPAL + segment] = Transform3D(basis, thumb_position)
		thumb_position += -basis.z * 0.03
	var hand_pose := Transform3D(hand_basis, Vector3(-0.25 * mirror, 1.2, -0.5))
	for joint in joints.size():
		joints[joint] = hand_pose * joints[joint]
	return joints


func apply_fixture(tracker: XRHandTracker, joints: Array[Transform3D], update_pose := true) -> void:
	for joint in joints.size():
		var pose := joints[joint]
		pose.basis *= OPENXR_TO_HUMANOID
		tracker.set_hand_joint_transform(joint, pose)
		tracker.set_hand_joint_flags(joint, VALID)
	if update_pose:
		tracker.set_pose("default", tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)


func verify_pose(driver: XRNode3D, origin: XROrigin3D, joints: Array[Transform3D], snapshot: Dictionary, label: String) -> void:
	var skeleton: Skeleton3D = driver.skeleton
	var prefix := "Left" if driver.hand == "left" else "Right"
	var max_distance := 0.0
	var max_angle := 0.0
	check(snapshot.size() == 25, label + " native modifier did not update all skinned bones")
	for joint in range(1, JOINT_BONES.size()):
		var bone := skeleton.find_bone(prefix + JOINT_BONES[joint])
		check(bone >= 0, "Missing humanoid bone: " + prefix + JOINT_BONES[joint])
		if not snapshot.has(bone):
			continue
		var expected := joints[joint]
		expected.origin *= XRServer.world_scale
		expected = origin.global_transform * XRServer.get_reference_frame() * expected
		expected.basis *= OPENXR_TO_HUMANOID
		var actual: Transform3D = snapshot[bone]
		max_distance = maxf(max_distance, actual.origin.distance_to(expected.origin))
		var angle := actual.basis.orthonormalized().get_rotation_quaternion().angle_to(expected.basis.orthonormalized().get_rotation_quaternion())
		max_angle = maxf(max_angle, rad_to_deg(angle))
		check(actual.origin.distance_to(expected.origin) < 0.001, label + " joint position mismatch: " + skeleton.get_bone_name(bone))
		check(rad_to_deg(angle) < 0.1, label + " joint orientation mismatch: " + skeleton.get_bone_name(bone))
		check(actual.basis.determinant() > 0.0, label + " mirrored/inside-out bone transform")
	print("HAND_POSE ", label, " max_mm=", max_distance * 1000, " max_degrees=", max_angle)


func rest_fixture(driver: XRNode3D) -> Array[Transform3D]:
	var joints: Array[Transform3D] = []
	joints.resize(XRHandTracker.HAND_JOINT_MAX)
	joints[0] = Transform3D(OPENXR_TO_HUMANOID.inverse(), Vector3.ZERO)
	var prefix := "Left" if driver.hand == "left" else "Right"
	for joint in range(1, JOINT_BONES.size()):
		var bone: int = driver.skeleton.find_bone(prefix + JOINT_BONES[joint])
		joints[joint] = driver.skeleton.get_bone_global_rest(bone)
		joints[joint].basis *= OPENXR_TO_HUMANOID.inverse()
	return joints


func verify_skin_rest(driver: XRNode3D, snapshot: Dictionary) -> void:
	# Joint transforms alone do not prove that the skin binds/axes agree. Drive
	# the authored neutral pose through the native modifier, then check every
	# weighted vertex and normal against the undeformed mesh.
	var mesh := driver.skeleton.get_child(0) as MeshInstance3D
	var arrays := mesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var skin: Skin = mesh.skin
	var transforms: Array[Transform3D] = []
	for bind in skin.get_bind_count():
		var bone: int = driver.skeleton.find_bone(skin.get_bind_name(bind))
		transforms.append(snapshot[bone] * skin.get_bind_pose(bind))
	var max_error := 0.0
	var min_normal_dot := 1.0
	for vertex in vertices.size():
		var position := Vector3.ZERO
		var normal := Vector3.ZERO
		for influence in 4:
			var index := vertex * 4 + influence
			var transform := transforms[bones[index]]
			position += (transform * vertices[vertex]) * weights[index]
			normal += (transform.basis * normals[vertex]) * weights[index]
		max_error = maxf(max_error, position.distance_to(vertices[vertex]))
		min_normal_dot = minf(min_normal_dot, normal.normalized().dot(normals[vertex].normalized()))
	check(max_error < 0.0001, driver.hand + " neutral tracking deformed/mirrored the skin")
	check(min_normal_dot > 0.999, driver.hand + " neutral tracking inverted skin normals")
	print("HAND_SKIN ", driver.hand, " vertices=", vertices.size(), " max_mm=", max_error * 1000, " min_normal_dot=", min_normal_dot)


func run() -> void:
	var original_scale := XRServer.world_scale
	for side in ["left", "right"]:
		XRServer.world_scale = 1.0
		var origin := XROrigin3D.new()
		root.add_child(origin)
		var driver := XRNode3D.new()
		driver.set_script(load("res://player/tracked_hand.gd"))
		driver.hand = side
		origin.add_child(driver)
		for mesh: MeshInstance3D in driver.find_children("*", "MeshInstance3D", true, false):
			check(mesh.gi_mode == GeometryInstance3D.GI_MODE_DYNAMIC, "Moving optical hand must receive lightmap probes")
			mesh.gi_mode = GeometryInstance3D.GI_MODE_STATIC
			PlatformXRInput.prepare_hand_model(driver)
			check(mesh.gi_mode == GeometryInstance3D.GI_MODE_DYNAMIC, "Old cached hand imports must not restore Static GI")
		var tracker := XRHandTracker.new()
		tracker.name = "/user/hand_tracker/" + side
		tracker.hand = XRPositionalTracker.TRACKER_HAND_LEFT if side == "left" else XRPositionalTracker.TRACKER_HAND_RIGHT
		tracker.has_tracking_data = true
		tracker.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
		XRServer.add_tracker(tracker)
		var snapshot: Dictionary = {}
		driver.modifier.modification_processed.connect(func():
			for bone in driver.skeleton.get_bone_count():
				snapshot[bone] = driver.skeleton.global_transform * driver.skeleton.get_bone_global_pose(bone)
		)
		var joints := fixture(side, 0.0, Basis.IDENTITY)
		apply_fixture(tracker, joints)
		await process_frame
		await process_frame
		check(driver.visible, "Optical hand must be visible with valid tracking")
		origin.set_meta("avatar_hands_active", true)
		driver._process(0.016)
		check(not driver.visible and not driver.modifier.active, "Separate hand models must hide while avatar hands are active")
		origin.set_meta("ui_hand_overlay_" + side, 1.0)
		driver._process(0.04)
		check(driver.visible and driver.modifier.active and driver._overlay_alpha > 0 and driver._overlay_alpha < 1, "UI hands must fade in with native joint tracking")
		for mesh: MeshInstance3D in driver.find_children("*", "MeshInstance3D", true, false):
			check(mesh.material_override in driver._materials, "Cached-import preparation must preserve the optical outline material")
			var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var tips: PackedVector3Array = mesh.material_override.get_shader_parameter("fingertips")
			for tip in tips:
				var nearest := INF
				for vertex in vertices:
					nearest = minf(nearest, vertex.distance_to(tip))
				check(nearest < 0.025, "Fingertip highlight must overlap raw bind-pose geometry")
		for material in driver._materials:
			check("depth_test_disabled" in material.shader.code, "UI outline must remain visible over avatar hands")
			check(material.get_shader_parameter("opacity") < 1.0, "Hand shader must fade smoothly")
			check(material.get_shader_parameter("fingertips").size() == 5 and material.get_shader_parameter("fingertip_highlight") == 1.0, "Raw hand shader must highlight all five fingertips")

		origin.set_meta("ui_hand_overlay_" + side, 0.0)
		driver._process(0.2)
		check(not driver.visible and not driver.modifier.active, "Leaving UI must fade separate hands away")
		origin.set_meta("avatar_hands_active", false)
		driver._process(0.016)
		await process_frame
		await process_frame

		verify_pose(driver, origin, joints, snapshot, side + " open")
		joints = fixture(side, 0.45, Basis.from_euler(Vector3(0.3, -0.7, 0.5)))
		apply_fixture(tracker, joints)
		await process_frame
		await process_frame
		verify_pose(driver, origin, joints, snapshot, side + " curled/tilted")
		# World entry constructs a rig after the tracker and its poses already
		# exist. Do not publish another pose or remove/re-add the tracker.
		var late_origin := XROrigin3D.new()
		root.add_child(late_origin)
		late_origin.transform = Transform3D(Basis(Vector3.UP, 0.8), Vector3(5, 1, -4))
		var late_driver := XRNode3D.new()
		late_driver.set_script(load("res://player/tracked_hand.gd"))
		late_driver.hand = side
		late_origin.add_child(late_driver)
		var late_snapshot: Dictionary = {}
		late_driver.modifier.modification_processed.connect(func():
			for bone in late_driver.skeleton.get_bone_count():
				late_snapshot[bone] = late_driver.skeleton.global_transform * late_driver.skeleton.get_bone_global_pose(bone)
		)
		await process_frame
		await process_frame
		check(late_driver.visible and late_driver.modifier.active, "World-entry hand did not bind an already-live tracker")
		verify_pose(late_driver, late_origin, joints, late_snapshot, side + " already-tracked world entry")
		late_driver.reparent(origin, false)
		await process_frame
		await process_frame
		verify_pose(late_driver, origin, joints, late_snapshot, side + " reused hand in new origin")
		late_driver.free()
		late_origin.free()
		tracker.has_tracking_data = false
		driver._process(0.016)
		check(not driver.visible and not driver.modifier.active, "Tracking gap left a frozen optical mesh visible")
		check(PlatformXRInput.hand_tracker(side) == null and PlatformXRInput.hand_tracker(side, false) == tracker, "Lost optical tracker must remain identifiable for controller suppression")
		tracker.has_tracking_data = true
		joints = fixture(side, 0.2, Basis(Vector3.UP, 0.4))
		# Recover joints without publishing another default pose: the old anchor
		# must not freeze while fingers start updating again.
		apply_fixture(tracker, joints, false)
		await process_frame
		await process_frame
		check(driver.visible and driver.modifier.active, "Optical hand did not resume after tracking gap")
		verify_pose(driver, origin, joints, snapshot, side + " recovered joints")
		XRServer.remove_tracker(tracker)
		driver._process(0.016)
		check(not driver.visible, "Removed tracker left a frozen hand visible")
		tracker = XRHandTracker.new()
		tracker.name = "/user/hand_tracker/" + side
		tracker.hand = XRPositionalTracker.TRACKER_HAND_LEFT if side == "left" else XRPositionalTracker.TRACKER_HAND_RIGHT
		tracker.has_tracking_data = true
		tracker.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
		apply_fixture(tracker, joints)
		XRServer.add_tracker(tracker)
		await process_frame
		await process_frame
		check(driver.visible, "Replacement tracker did not restore the existing hand")
		verify_pose(driver, origin, joints, snapshot, side + " replacement tracker")
		origin.transform = Transform3D(Basis(Vector3.UP, 1.1), Vector3(12, 3, -7))
		XRServer.world_scale = 1.7
		tracker.set_pose("default", tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		await process_frame
		await process_frame
		verify_pose(driver, origin, joints, snapshot, side + " moved/scaled")
		origin.transform = Transform3D.IDENTITY
		XRServer.world_scale = 1.0
		apply_fixture(tracker, rest_fixture(driver))
		await process_frame
		await process_frame
		verify_skin_rest(driver, snapshot)
		tracker.set_hand_joint_flags(XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_INTERMEDIATE, 0)
		driver._process(0.016)
		check(not driver.visible and not driver.modifier.active, "Partial tracking must hide the mesh and suspend native updates")
		tracker.set_hand_joint_flags(XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_INTERMEDIATE, VALID)
		for joint in [XRHandTracker.HAND_JOINT_PALM, XRHandTracker.HAND_JOINT_WRIST]:
			tracker.set_hand_joint_flags(joint, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID)
			driver._process(0.016)
			check(not driver.visible, "Hand must hide when anchor orientation is invalid")
			tracker.set_hand_joint_flags(joint, VALID)
		tracker.has_tracking_data = false
		driver._process(0.016)
		check(not driver.visible, "Hand must hide on tracking loss")
		tracker.has_tracking_data = true
		tracker.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER
		driver._process(0.016)
		check(not driver.visible, "Controller tracking must use the controller mesh")
		XRServer.remove_tracker(tracker)
		origin.free()
	XRServer.world_scale = original_scale
	print("TRACKED_HAND_TEST failures=", failures)
	quit(1 if failures else 0)
