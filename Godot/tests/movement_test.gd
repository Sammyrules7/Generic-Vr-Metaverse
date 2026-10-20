extends SceneTree

var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100, 1, 100)
	collider.shape = shape
	floor_body.add_child(collider)
	floor_body.position.y = -0.5
	root.add_child(floor_body)

	for mode in ["desktop", "vr"]:
		var player := CharacterBody3D.new()
		var player_collider := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.height = 2.0
		player_collider.position.y = 1.0
		player_collider.shape = capsule
		player.add_child(player_collider)
		root.add_child(player)
		player.position = Vector3(10, 0.05, 10)
		var adapter := Node3D.new()
		if mode == "desktop":
			adapter.set_script(load("res://player/desktop_controls.gd"))
			var camera := Camera3D.new()
			camera.name = "Camera"
			adapter.add_child(camera)
		else:
			adapter.set_script(load("res://player/vr_controls.gd"))
			var origin := XROrigin3D.new()
			origin.name = "Origin"
			adapter.add_child(origin)
			var camera := XRCamera3D.new()
			camera.name = "HMDView"
			origin.add_child(camera)
			for hand in ["LeftHand", "RightHand"]:
				var controller := XRController3D.new()
				controller.name = hand
				origin.add_child(controller)
		player.add_child(adapter)
		var motor := CharacterMotor.new()
		player.add_child(motor)
		motor.input_source = adapter
		motor.set_physics_process(false)
		for i in 30:
			await physics_frame
			motor.step(1.0 / 60.0, Vector3.ZERO, false)
		check(player.is_on_floor(), mode + " lands")
		for i in 30:
			await physics_frame
			motor.step(1.0 / 60.0, Vector3(1, 0, 1), false)
		check(absf(Vector2(player.velocity.x, player.velocity.z).length() - motor.speed) < 0.01, mode + " diagonal speed capped")
		for i in 20:
			await physics_frame
			motor.step(1.0 / 60.0, Vector3.ZERO, false)
		check(Vector2(player.velocity.x, player.velocity.z).length() < 0.01, mode + " stops")
		var baseline := player.position.y
		await physics_frame
		motor.step(1.0 / 60.0, Vector3.ZERO, true)
		check(player.velocity.y > 0, mode + " jumps")
		var apex := baseline
		for i in 90:
			await physics_frame
			motor.step(1.0 / 60.0, Vector3.ZERO, false)
			apex = maxf(apex, player.position.y)
		check(absf(apex - baseline - motor.jump_height) < 0.08, mode + " jump height")
		check(player.is_on_floor(), mode + " lands after jump")
		if mode == "desktop":
			Input.action_press("move_forward")
			adapter.sample(0.1)
			check(adapter.move_direction.z < -0.99, "desktop forward input")
			Input.action_release("move_forward")
			adapter.apply_look(Vector2(0, 100))
			check(is_equal_approx(adapter.head.rotation.x, -1.5), "desktop pitch clamp")
		else:
			check(adapter.filtered_stick(Vector2(0.1, 0)).is_zero_approx(), "XR stick deadzone")
			check(adapter.select_movement(Vector2(0, 1), false, 0) == Vector2.UP, "XR stick forward")
			check(adapter.select_movement(Vector2.ZERO, true, 0.01) == Vector2.UP, "pinch starts")
			check(adapter.select_movement(Vector2.ZERO, true, 0.025) == Vector2.UP, "pinch hysteresis")
			check(adapter.select_movement(Vector2.ZERO, true, 0.03, 0.2) == Vector2.UP, "relaxed pinch stays engaged inside release band")
			check(adapter.select_movement(Vector2.ZERO, true, 0.1, 0.2) == Vector2.UP, "one noisy sample during a frame hitch must not stop movement")
			check(adapter.select_movement(Vector2.ZERO, true, 0.03, 0.016) == Vector2.UP, "valid sample cancels frame-hitch release")
			check(adapter.select_movement(Vector2.ZERO, true, 0.04, 0.016) == Vector2.UP, "one-frame separation jitter must not stop movement")
			check(adapter.select_movement(Vector2.ZERO, true, 0.03, 0.016) == Vector2.UP, "returning to release band cancels release timer")
			check(adapter.select_movement(Vector2.ZERO, true, 0.04, 0.02) == Vector2.UP, "release timer restarted too early")
			check(adapter.select_movement(Vector2.ZERO, true, 0.04, 0.04) == Vector2.UP, "brief separation still preserves sustained movement")
			check(adapter.select_movement(Vector2.ZERO, true, 0.04, 0.025).is_zero_approx(), "modest intentional separation must stop movement after confirmation")
			check(adapter.select_movement(Vector2.ZERO, true, 0.03, 0.2).is_zero_approx(), "release band alone must not start locomotion")
			check(adapter.select_movement(Vector2.ZERO, true, 0.019, 0.02) == Vector2.UP, "original pinch sensitivity must still start movement")
			check(adapter.select_movement(Vector2.ZERO, false, 0, 0.016) == Vector2.UP, "one-frame tracking gap must not stop pinch")
			check(adapter.select_movement(Vector2.ZERO, true, 0.025, 0.016) == Vector2.UP, "tracking recovery preserves pinch and cancels gap timer")
			check(adapter.select_movement(Vector2.ZERO, false, 0, 0.02) == Vector2.UP, "brief tracking gap stays within grace period")
			check(adapter.select_movement(Vector2.ZERO, false, 0, 0.04) == Vector2.UP, "short tracking dropout preserves sustained movement")
			check(adapter.select_movement(Vector2.ZERO, false, 0, 0.025).is_zero_approx(), "sustained tracking loss stops pinch after confirmation")
			check(adapter.select_movement(Vector2.ZERO, false, 0, 1.0).is_zero_approx(), "missing tracking cannot start movement")
			check(adapter.select_movement(Vector2(1, 0), true, 0.01) == Vector2.RIGHT, "controller priority")
			for side in ["left", "right"]:
				var tracker := XRHandTracker.new()
				tracker.name = "/user/hand_tracker/" + side
				tracker.has_tracking_data = true
				tracker.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
				for joint in [XRHandTracker.HAND_JOINT_THUMB_TIP, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP]:
					tracker.set_hand_joint_flags(joint, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID)
					tracker.set_hand_joint_transform(joint, Transform3D.IDENTITY)
				tracker.set_hand_joint_transform(XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP, Transform3D(Basis.IDENTITY, Vector3(0.1, 0, 0)))
				XRServer.add_tracker(tracker)
				var pinch: Vector2 = adapter._hand_pinch()
				check(pinch.x == 1.0 and is_equal_approx(pinch.y, 0.1), side + " index pinch must not drive locomotion")
				tracker.set_hand_joint_transform(XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP, Transform3D(Basis.IDENTITY, Vector3(0.01, 0, 0)))
				pinch = adapter._hand_pinch()
				check(adapter.select_movement(Vector2.ZERO, pinch.x > 0.5, pinch.y) == Vector2.UP, side + " thumb/middle pinch moves forward")
				var idle := XRHandTracker.new()
				idle.name = "/user/hand_tracker/" + ("right" if side == "left" else "left")
				idle.has_tracking_data = true
				idle.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
				for joint in [XRHandTracker.HAND_JOINT_THUMB_TIP, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP]:
					idle.set_hand_joint_flags(joint, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID)
				idle.set_hand_joint_transform(XRHandTracker.HAND_JOINT_THUMB_TIP, Transform3D.IDENTITY)
				idle.set_hand_joint_transform(XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP, Transform3D(Basis.IDENTITY, Vector3(0.025, 0, 0)))
				XRServer.add_tracker(idle)
				tracker.set_hand_joint_transform(XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP, Transform3D(Basis.IDENTITY, Vector3(0.04, 0, 0)))
				pinch = adapter._hand_pinch()
				check(is_equal_approx(pinch.y, 0.04), side + " idle second hand must not prolong release")
				check(adapter.select_movement(Vector2.ZERO, pinch.x > 0.5, pinch.y, 0.02) == Vector2.UP, side + " active release waits for confirmation")
				check(adapter.select_movement(Vector2.ZERO, pinch.x > 0.5, pinch.y, 0.065).is_zero_approx(), side + " active hand release stops despite idle second hand")
				tracker.set_hand_joint_transform(XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP, Transform3D(Basis.IDENTITY, Vector3(0.01, 0, 0)))
				pinch = adapter._hand_pinch()
				adapter.select_movement(Vector2.ZERO, pinch.x > 0.5, pinch.y)
				tracker.set_hand_joint_flags(XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP, 0)
				pinch = adapter._hand_pinch()
				check(adapter.select_movement(Vector2.ZERO, pinch.x > 0.5, pinch.y, 0.016) == Vector2.UP, side + " transient invalid joint must not jitter movement")
				check(adapter.select_movement(Vector2.ZERO, pinch.x > 0.5, pinch.y, 0.065).is_zero_approx(), side + " sustained invalid joint cancels movement")
				XRServer.remove_tracker(tracker)
				XRServer.remove_tracker(idle)
			adapter.get_node("Origin").position = Vector3(0.4, 0, -0.2)
			adapter.head.position = Vector3(0.6, 1.7, 0.3)
			var head_position: Vector3 = adapter.head.global_position
			adapter.rotate_around_head(0.7)
			check(adapter.head.global_position.distance_to(head_position) < 0.0001, "XR turn preserves head position")
			adapter.sync_room_scale()
			check(adapter.head.global_position.distance_to(head_position) < 0.0001, "room scale preserves head pose")
			check(Vector2(player.global_position.x - head_position.x, player.global_position.z - head_position.z).length() < 0.001, "room scale body follows head")
			adapter._button_pressed("ax_button")
			check(adapter.consume_jump() and not adapter.consume_jump(), "XR jump consumed once")
		player.free()

	check(MovementInput.planar_direction(Vector2.UP, Basis(Vector3.RIGHT, PI / 2)).is_equal_approx(Vector3.FORWARD), "vertical look keeps forward movement")
	print("Movement tests complete: %d failures" % failures)
	quit(1 if failures else 0)
