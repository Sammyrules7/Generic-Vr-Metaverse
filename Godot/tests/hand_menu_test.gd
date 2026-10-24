extends SceneTree

class TouchUI extends Control:
	func xr_point_is_visible(point: Vector2) -> bool:
		return Rect2(Vector2.ZERO, Vector2(1120, 800)).has_point(point)

var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func set_tip(tracker: XRHandTracker, origin: XROrigin3D, world_point: Vector3) -> void:
	var pose := (origin.global_transform * XRServer.get_reference_frame()).affine_inverse() * Transform3D(Basis.IDENTITY, world_point)
	pose.origin /= XRServer.world_scale
	tracker.set_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, pose)
	tracker.set_hand_joint_flags(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID)


func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	world.transform = Transform3D(Basis(Vector3.UP, -0.4), Vector3(-5, 0, 3))
	var origin := XROrigin3D.new()
	world.add_child(origin)
	origin.transform = Transform3D(Basis(Vector3.UP, 0.7), Vector3(12, 0, -8))
	var head := XRCamera3D.new()
	origin.add_child(head)
	head.position = Vector3(0.3, 1.7, 0.2)
	var panel = load("res://UI/vr_panel.tscn").instantiate()
	panel.screen_size = Vector2(0.56, 0.4)
	panel.get_node("Viewport").add_child(TouchUI.new())
	world.add_child(panel)
	panel.bind_rig(origin, head)
	var playspace := origin.global_transform * XRServer.get_reference_frame()
	var expected := playspace * Vector3(0.3, 1.58, -0.18)
	check(panel.global_position.distance_to(expected) < 0.001, "Binding must put the tablet within reach of the player")
	check(is_equal_approx(panel.global_basis.z.y, sin(deg_to_rad(20))), "Panel must face slightly upward")
	check(absf(panel.global_basis.x.y) < 0.001, "Panel must have no roll")
	check(panel.global_basis.z.dot(playspace.basis.z) > 0.93, "Panel must face back toward the player")
	check(panel.is_processing(), "Viewport refresh disabled menu processing during ready")
	panel.set_room_mode(true, false)
	check(panel.global_position.distance_to(playspace * Vector3(0.3, 1.38, -0.18)) < 0.001, "Full in-game panel was not lowered 20 cm")
	panel.set_room_mode(true, true)
	check(panel.global_position.distance_to(playspace * Vector3(0.3, 1.44, -0.18)) < 0.001, "Compact in-game panel was not lowered 8 cm")
	panel.set_room_mode(false, false)
	check(panel.global_position.distance_to(expected) < 0.001, "Lobby height changed with in-game panel tuning")
	# Check real frames: manually calling _process would miss the original bug.
	await process_frame
	await process_frame
	var previous: Transform3D = panel.global_transform
	head.position += Vector3(0.03, -0.04, 0.04)
	head.rotation = Vector3(deg_to_rad(35), deg_to_rad(10), deg_to_rad(25))
	await process_frame
	await process_frame
	check(panel.is_processing(), "Viewport base disabled menu processing after a frame")
	check(panel.global_transform.is_equal_approx(previous), "Physical head motion or heading inside 15 degrees moved the menu")
	head.rotation.y = deg_to_rad(30)
	await process_frame
	await process_frame
	check(not panel.global_transform.is_equal_approx(previous), "Heading beyond 15 degrees did not move the menu on real frames")
	check(is_equal_approx(panel.global_basis.z.y, sin(deg_to_rad(20))) and absf(panel.global_basis.x.y) < 0.001, "Head tilt changed menu pitch/roll while turning")
	for frame in 90:
		panel._process(1.0 / 60.0)
	var forward := playspace.basis * (Basis(Vector3.UP, deg_to_rad(30)) * Vector3.FORWARD)
	expected = playspace * Vector3(0.3, 1.58, 0.2) + forward * 0.38
	check(panel.global_position.distance_to(expected) < 0.005, "Menu did not converge around its playspace anchor")
	previous = panel.global_transform
	head.rotation.y = deg_to_rad(44)
	panel._process(0.1)
	check(panel.global_position.distance_to(previous.origin) < 0.001, "Menu kept following heading inside the new 15-degree deadzone")
	# Artificial locomotion moves the whole playspace anchor, including the UI.
	var shift := Vector3(2, 0, -1)
	origin.global_position += shift
	panel._process(0.0)
	check(panel.global_position.distance_to(previous.origin + shift) < 0.001, "Menu did not move with playspace locomotion")
	head.position += Vector3(0.8, 0, -0.6)
	for frame in 90:
		panel._process(1.0 / 60.0)
	var local := head.to_local(panel.global_position)
	check(Vector2(local.x, local.z).length() < 0.65, "Room-scale movement put the tablet out of reach")
	panel.hide()
	head.position += Vector3(3, 0.2, -2)
	panel.show()
	check(panel.is_processing(), "Visibility/render refresh disabled menu processing")
	check(absf(angle_difference(panel.heading, deg_to_rad(44))) < 0.001, "Reopening did not reset heading to the headset")
	expected = panel.global_position
	for mode in [XRToolsViewport2DIn3D.UpdateMode.UPDATE_ONCE, XRToolsViewport2DIn3D.UpdateMode.UPDATE_THROTTLED, XRToolsViewport2DIn3D.UpdateMode.UPDATE_ALWAYS]:
		panel.update_mode = mode
		panel._process(0.016)
		check(panel.is_processing(), "Render update mode disabled head following")
	# Left-hand motion must not pull the head-anchored tablet away.
	var left := XRHandTracker.new()
	left.name = "/user/hand_tracker/left"
	left.has_tracking_data = true
	left.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
	left.set_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM, Transform3D(Basis.IDENTITY, Vector3(50, 0, 50)))
	left.set_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID)
	XRServer.add_tracker(left)
	panel._process(0.1)
	check(panel.global_position.distance_to(expected) < 0.001, "Left-hand motion changed menu placement")
	var right := XRHandTracker.new()
	right.name = "/user/hand_tracker/right"
	right.has_tracking_data = true
	right.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
	XRServer.add_tracker(right)
	var events: Array = []
	panel.pointer_event.connect(func(event): events.append(event.event_type))
	set_tip(right, origin, panel.to_global(Vector3(0, 0, -0.01)))
	panel._process(0.0)
	check(not panel.touching and not events.has(XRToolsPointerEvent.Type.PRESSED), "Tracking that starts behind the panel must not count as a poke")
	set_tip(right, origin, panel.to_global(Vector3(0, 0, 0.14)))
	panel._process(0.0)
	check(panel.hand_contacts.right.hovering and not panel.touching, "Approaching the panel must give hover feedback before contact")
	set_tip(right, origin, panel.to_global(Vector3(0, 0, 0.18)))
	panel._process(0.0)
	check(panel.hand_contacts.right.hovering, "Hover hysteresis must prevent flicker near its boundary")
	set_tip(right, origin, panel.to_global(Vector3(0, 0, 0.21)))
	panel._process(0.0)
	check(not panel.hand_contacts.right.hovering, "Withdrawing beyond the exit zone must clear hover")
	set_tip(right, origin, panel.to_global(Vector3(0, 0, 0.03)))
	panel._process(0.0)
	set_tip(right, origin, panel.to_global(Vector3(0, 0, 0.005)))
	panel._process(0.0)
	check(panel.touching and events.has(XRToolsPointerEvent.Type.PRESSED), "Finger crossing the panel did not press the UI")
	check(panel.hand_contacts.right.pointer.get_meta("ui_poke_intent") == "press", "Straight pre-contact motion must latch press intent")
	var frozen: Transform3D = panel.global_transform
	head.rotation.y += deg_to_rad(40)
	set_tip(right, origin, panel.to_global(Vector3(0.02, 0, 0.005)))
	panel._process(0.2)
	check(panel.global_transform.is_equal_approx(frozen), "Head following moved controls during finger contact")
	check(events.back() == XRToolsPointerEvent.Type.MOVED, "Finger drag did not use the UI pointer path")
	right.has_tracking_data = false
	panel._process(0.016)
	check(not panel.touching and events.has(XRToolsPointerEvent.Type.RELEASED), "Tracking loss did not release finger contact")
	panel._process(0.1)
	check(not panel.global_transform.is_equal_approx(frozen), "Head following did not resume after contact ended")
	var presses := events.count(XRToolsPointerEvent.Type.PRESSED)
	panel.hide()
	panel.show()
	right.has_tracking_data = true
	panel._process(0.0)
	check(events.count(XRToolsPointerEvent.Type.PRESSED) == presses, "A resting finger retriggered after UI/tracking change")
	origin.global_position += Vector3(0.5, 0, 0.5)
	panel._process(0.0)
	check(not panel.hand_contacts.right.armed, "Artificial locomotion rearmed a resting finger")
	set_tip(right, origin, panel.to_global(Vector3(0, 0, 0.2)))
	panel._process(0.0)
	check(panel.hand_contacts.right.armed, "Finger withdrawal did not rearm the next contact")
	set_tip(right, origin, panel.to_global(Vector3(0, 0, 0.005)))
	panel._process(0.0)
	check(events.count(XRToolsPointerEvent.Type.PRESSED) == presses + 1, "Fresh contact after withdrawal did not activate once")
	right.has_tracking_data = false
	panel.release_touch()
	var pressed_pointers: Array = []
	panel.pointer_event.connect(func(event):
		if event.event_type == XRToolsPointerEvent.Type.PRESSED:
			pressed_pointers.append(event.pointer)
	)
	set_tip(left, origin, panel.to_global(Vector3(-0.02, 0, 0.014)))
	panel._process(0.0)
	set_tip(left, origin, panel.to_global(Vector3(-0.02, 0, 0.005)))
	panel._process(0.0)
	check(panel.hand_contacts.left.touching and pressed_pointers.has(panel.hand_contacts.left.pointer), "Left fingertip did not press the panel")
	right.has_tracking_data = true
	set_tip(right, origin, panel.to_global(Vector3(0.02, 0, 0.014)))
	panel._process(0.0)
	set_tip(right, origin, panel.to_global(Vector3(0.02, 0, 0.005)))
	panel._process(0.0)
	check(panel.hand_contacts.left.touching and panel.hand_contacts.right.touching, "Both hands must track contact independently")
	left.has_tracking_data = false
	panel._process(0.0)
	check(not panel.hand_contacts.left.touching and panel.hand_contacts.right.touching, "Losing one hand canceled the other hand's contact")
	right.has_tracking_data = false
	panel._process(0.0)
	left.has_tracking_data = true
	panel._process(0.0)
	check(not panel.hand_contacts.left.armed, "Tracking recovery rearmed a resting left finger")
	set_tip(left, origin, panel.to_global(Vector3(-0.02, 0, 0.014)))
	panel._process(0.0)
	check(panel.hand_contacts.left.armed, "Small 14 mm withdrawal did not allow a rapid next tap")
	set_tip(left, origin, panel.to_global(Vector3(-0.02, 0, 0.005)))
	panel._process(0.0)
	check(pressed_pointers.count(panel.hand_contacts.left.pointer) == 2, "Fresh left contact did not press once after small withdrawal")
	left.has_tracking_data = false
	panel.release_touch()
	left.has_tracking_data = true
	set_tip(left, origin, panel.to_global(Vector3(-0.02, 0, 0.025)))
	panel._process(0.0)
	set_tip(left, origin, panel.to_global(Vector3(-0.02, 0.02, 0.015)))
	panel._process(0.0)
	set_tip(left, origin, panel.to_global(Vector3(-0.02, 0.04, 0.005)))
	panel._process(0.0)
	check(panel.hand_contacts.left.pointer.get_meta("ui_poke_intent") == "scroll", "Sideways pre-contact motion must latch scroll intent")
	set_tip(left, origin, panel.to_global(Vector3(-0.02, 0.04, -0.015)))
	panel._process(0.0)
	check(panel.hand_contacts.left.pointer.get_meta("ui_poke_intent") == "scroll", "Penetration must not convert a swipe into a press")
	left.has_tracking_data = false
	panel.release_touch()
	# Leaving a room rebinds the persistent tablet to another rig.
	var lobby := XROrigin3D.new()
	world.add_child(lobby)
	var lobby_head := XRCamera3D.new()
	lobby.add_child(lobby_head)
	lobby_head.position.y = 1.6
	panel.bind_rig(lobby, lobby_head)
	expected = (lobby.global_transform * XRServer.get_reference_frame()) * Vector3(0, 1.48, -0.38)
	check(panel.global_position.distance_to(expected) < 0.001, "Rig switch left the menu at the previous/world position")
	# The tablet survives the old player rig being freed on room exit.
	origin.free()
	lobby.free()
	panel._process(0.016)
	check(not panel.touching and not panel.placed, "Freed rig did not reset menu placement safely")
	XRServer.remove_tracker(left)
	XRServer.remove_tracker(right)
	world.free()
	print("HAND_MENU_TEST failures=", failures)
	quit(1 if failures else 0)
