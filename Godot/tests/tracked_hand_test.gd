extends SceneTree
## Fixtures use raw OpenXR joint axes (+Y out of the back, -Z toward the tip).
## They do not derive tracking data from the driver's conversion or mesh rest.

const OPENXR_TO_HUMANOID := Basis(Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0))
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


func verify_geometry(driver: XRNode3D, origin: XROrigin3D, tracker: XRHandTracker, label: String) -> void:
	var visual: NeutralHandVisual = driver.visual
	for joint in range(1, XRHandTracker.HAND_JOINT_MAX):
		# Dummy RenderingServer does not retain MultiMesh instance buffers.
		var rendered := visual.points[joint] if DisplayServer.get_name() == "headless" else visual.joints.get_instance_transform(joint - 1).origin
		var actual := visual.global_transform * rendered
		var expected := PlatformXRInput.joint_world(origin, tracker, joint).origin
		check(actual.distance_to(expected) < 0.0001, label + " visual joint disagrees with touch point: " + str(joint))
		check(visual.joints.get_instance_transform(joint - 1).basis.determinant() > 0, label + " reflected joint shell")
	for index in visual.links.instance_count:
		check(visual.links.get_instance_transform(index).basis.determinant() > 0, label + " inside-out finger segment")
	check(visual.palm.get_instance_transform(0).basis.determinant() > 0, label + " inside-out palm")
	for joint in NeutralHandVisual.TIPS:
		if DisplayServer.get_name() != "headless":
			check(visual.joints.get_instance_custom_data(joint - 1).r == 1.0, "Fingertips must get the brighter outline")
	for batch: MultiMeshInstance3D in visual.get_children():
		check(batch.layers == AvatarView.FIRST_PERSON and batch.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Hand shell must stay out of mirrors and shadows")

func run() -> void:
	var original_scale := XRServer.world_scale
	for side in ["left", "right"]:
		var origin := XROrigin3D.new()
		root.add_child(origin)
		var driver := XRNode3D.new()
		driver.set_script(load("res://player/tracked_hand.gd"))
		driver.hand = side
		origin.add_child(driver)
		var tracker := XRHandTracker.new()
		tracker.name = "/user/hand_tracker/" + side
		tracker.hand = XRPositionalTracker.TRACKER_HAND_LEFT if side == "left" else XRPositionalTracker.TRACKER_HAND_RIGHT
		tracker.has_tracking_data = true
		tracker.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
		XRServer.add_tracker(tracker)
		for curl in [0.0, 0.5, 1.0]:
			apply_fixture(tracker, fixture(side, curl, Basis.from_euler(Vector3(0.3, -0.7, 0.5))))
			await process_frame
			await process_frame
			check(driver.visible and driver.tracking_valid, "Valid optical joints must render")
			verify_geometry(driver, origin, tracker, side + " curled " + str(curl))
		origin.set_meta("avatar_hands_active", true)
		driver._process(0.016)
		check(not driver.visible, "Avatar hands should be used away from UI")
		origin.set_meta("ui_hand_overlay_" + side, 1.0)
		driver._process(0.04)
		check(driver.visible and driver._overlay_alpha > 0 and driver._overlay_alpha < 1, "UI shell should fade in")
		check("depth_test_disabled" in driver.visual.material.shader.code, "UI outline must remain visible over offset avatar hands")
		origin.set_meta("ui_hand_overlay_" + side, 0.0)
		driver._process(0.2)
		check(not driver.visible, "UI shell should fade away")
		origin.set_meta("avatar_hands_active", false)
		origin.transform = Transform3D(Basis(Vector3.UP, 1.1), Vector3(12, 3, -7))
		XRServer.world_scale = 1.7
		apply_fixture(tracker, fixture(side, 0.5, Basis(Vector3.UP, 0.4)), false)
		await process_frame
		await process_frame
		verify_geometry(driver, origin, tracker, side + " moved/scaled, no new pose signal")
		check(not "depth_test_disabled" in driver.visual.material.shader.code, "Fallback shell should respect world occlusion")
		# Root pose orientation does not define the shell: only measured positions
		# do, including when the provider supplies position-only joints.
		for joint in XRHandTracker.HAND_JOINT_MAX:
			tracker.set_hand_joint_flags(joint, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID)
		driver._process(0.016)
		check(driver.visible, "Position-only tracking should still render the neutral shell")
		verify_geometry(driver, origin, tracker, side + " positions only")
		tracker.set_hand_joint_flags(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, 0)
		driver._process(0.016)
		check(not driver.visible, "Invalid contact point must hide the shell")
		tracker.set_hand_joint_flags(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, VALID)
		tracker.has_tracking_data = false
		driver._process(0.016)
		check(not driver.visible, "Tracking loss must hide the shell immediately")
		tracker.has_tracking_data = true
		driver._process(0.016)
		check(driver.visible, "Tracking recovery must not require a new pose event")
		tracker.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER
		driver._process(0.016)
		check(not driver.visible, "Optical shell must not replace live controller grips")
		XRServer.remove_tracker(tracker)
		driver._process(0.016)
		check(not driver.visible, "Removed tracker must hide the shell")
		# Bind a replacement tracker without recreating the visual.
		tracker = XRHandTracker.new()
		tracker.name = "/user/hand_tracker/" + side
		tracker.has_tracking_data = true
		apply_fixture(tracker, fixture(side, 0.2, Basis.IDENTITY))
		XRServer.add_tracker(tracker)
		await process_frame
		await process_frame
		check(driver.visible, "Replacement tracker did not restore shell")
		verify_geometry(driver, origin, tracker, side + " replacement tracker")
		XRServer.remove_tracker(tracker)
		origin.free()
	XRServer.world_scale = original_scale
	print("TRACKED_HAND_TEST failures=", failures)
	quit(1 if failures else 0)
