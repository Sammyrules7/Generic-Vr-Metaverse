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
			check(adapter.select_movement(Vector2.ZERO, false, 0).is_zero_approx(), "tracking loss stops pinch")
			check(adapter.select_movement(Vector2(1, 0), true, 0.01) == Vector2.RIGHT, "controller priority")
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
