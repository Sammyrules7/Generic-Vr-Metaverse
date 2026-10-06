extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var failures := 0
	for side in ["left", "right"]:
		var origin := XROrigin3D.new()
		root.add_child(origin)
		var driver := Node3D.new()
		driver.set_script(load("res://player/tracked_hand.gd"))
		driver.hand = side
		origin.add_child(driver)
		driver.set_process(false)
		var skeleton: Skeleton3D = driver.skeleton
		var tracker := XRHandTracker.new()
		tracker.name = "/user/hand_tracker/" + side
		tracker.hand = XRPositionalTracker.TRACKER_HAND_LEFT if side == "left" else XRPositionalTracker.TRACKER_HAND_RIGHT
		tracker.has_tracking_data = true
		tracker.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
		var desired: Dictionary[int, Transform3D] = {}
		var axes: Basis = driver.LEGACY_AXES
		for bone: int in driver.bone_joints:
			var joint: int = driver.bone_joints[bone]
			var pose := skeleton.global_transform * skeleton.get_bone_global_rest(bone)
			desired[bone] = pose
			pose.basis *= axes.inverse()
			tracker.set_hand_joint_transform(joint, pose)
			tracker.set_hand_joint_flags(joint, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID)
		XRServer.add_tracker(tracker)
		driver._process(0.016)
		var mismatches := 0
		var max_angle := 0.0
		for bone: int in desired:
			var actual := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
			var expected: Transform3D = desired[bone]
			var angle := rad_to_deg(actual.basis.orthonormalized().get_rotation_quaternion().angle_to(expected.basis.orthonormalized().get_rotation_quaternion()))
			if angle > 1.0:
				mismatches += 1
			max_angle = maxf(max_angle, angle)
		failures += mismatches
		print("HAND_POSE ", side, " neutral mismatches=", mismatches, "/", desired.size(), " max_degrees=", max_angle)
		tracker.set_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID)
		driver._process(0.016)
		if driver.visible:
			failures += 1
			push_error("Hand must hide when palm orientation is invalid")
		XRServer.remove_tracker(tracker)
		origin.free()
	quit(1 if failures else 0)
