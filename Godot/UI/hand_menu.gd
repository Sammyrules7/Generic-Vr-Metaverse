@tool
extends XRToolsViewport2DIn3D
## A nearby, upward-tilted tablet with a heading deadzone. Contact uses the
## same UI event path as controller rays, including dragging and release.

@export_range(0.25, 2.0) var follow_distance := 0.38
@export_range(0.0, 40.0) var upward_tilt_degrees := 20.0
@export_range(0.1, 20.0) var follow_speed := 4.0
@export_range(1.0, 90.0) var turn_threshold_degrees := 15.0
@export_range(0.0, 0.8) var lobby_height_drop := 0.12
@export_range(0.0, 0.8) var room_height_drop := 0.32
@export_range(0.0, 0.8) var compact_height_drop := 0.26

class HandContact:
	var pointer: Node3D
	var touching := false
	var hovering := false
	var armed := true
	var last_touch := Vector3.ZERO
	var previous_depth := INF
	var contact_frame := Transform3D.IDENTITY
	var approach := TouchApproach.new()

var origin: XROrigin3D
var camera: XRCamera3D
var hand_contacts: Dictionary[String, HandContact] = {}
var touching: bool:
	get:
		for contact in hand_contacts.values():
			if contact.touching:
				return true
		return false

var placed := false
var heading := 0.0
var target_heading := 0.0
var anchor := Vector3.ZERO
var target_anchor := Vector3.ZERO
var compact := false
var in_room := false
var input_pointer: Node3D
var click_audio: AudioStreamPlayer
signal click_feedback

var _surface_body: StaticBody3D


func _ready() -> void:
	super._ready()
	for side in ["left", "right"]:
		var contact := HandContact.new()
		contact.pointer = Node3D.new()
		contact.pointer.name = side.capitalize() + "FingertipTouch"
		add_child(contact.pointer)
		hand_contacts[side] = contact
	click_audio = AudioStreamPlayer.new()
	click_audio.stream = preload("res://UI/click.wav")
	click_audio.volume_db = -9.0
	add_child(click_audio)
	_surface_body = $StaticBody3D
	process_priority = 20
	visibility_changed.connect(_reset_placement)
	set_process(true)


func bind_rig(new_origin: XROrigin3D, new_camera: XRCamera3D) -> void:
	release_touch()
	origin = new_origin
	camera = new_camera
	placed = false
	_follow_head(0.0)


func _process(delta: float) -> void:
	super._process(delta)
	_clear_hand_overlays()
	# The viewport base disables processing for several update modes; the
	# subclass must reassert it every frame to keep head following alive.
	set_process(true)
	if not visible or not enabled or not is_instance_valid(origin) or not is_instance_valid(camera):
		release_touch()
		placed = false
		return
	_check_withdrawal()
	_follow_head(delta)
	_update_touch()


func _update_render() -> void:
	super._update_render()
	# The viewport base disables processing for UPDATE_ALWAYS/ONCE and when
	# hidden. This subclass also needs processing for head following and touch.
	set_process(true)


func _reset_placement() -> void:
	release_touch()
	placed = false
	if visible and enabled:
		set_process(true)
		_follow_head(0.0)


func _follow_head(delta: float) -> void:
	if not is_instance_valid(origin) or not is_instance_valid(camera) or touching:
		return
	var playspace := origin.global_transform * XRServer.get_reference_frame()
	var head_pose := playspace.affine_inverse() * camera.global_transform
	var forward := -head_pose.basis.z
	forward.y = 0.0
	# Looking straight up/down has no heading; retain the last horizontal one.
	var head_heading := atan2(-forward.x, -forward.z) if forward.length_squared() > 0.0001 else target_heading
	var height_drop := compact_height_drop if compact else (room_height_drop if in_room else lobby_height_drop)
	var head_anchor := head_pose.origin - Vector3.UP * height_drop
	if not placed:
		anchor = head_anchor
		target_anchor = head_anchor
		heading = head_heading
		target_heading = head_heading
	else:
		# A small translation deadzone avoids attaching the tablet to head jitter,
		# while keeping it within reach during room-scale motion.
		if Vector2(head_anchor.x - target_anchor.x, head_anchor.z - target_anchor.z).length() > 0.1 or absf(head_anchor.y - target_anchor.y) > 0.15:
			target_anchor = head_anchor
		if absf(angle_difference(target_heading, head_heading)) > deg_to_rad(turn_threshold_degrees):
			target_heading = head_heading
	var blend := 1.0 - exp(-follow_speed * delta)
	heading = lerp_angle(heading, target_heading, blend)
	anchor = anchor.lerp(target_anchor, blend)
	var world_forward := playspace.basis * (Basis(Vector3.UP, heading) * Vector3.FORWARD)
	world_forward.y = 0.0
	world_forward = world_forward.normalized()
	var center := playspace * anchor
	var target := center + world_forward * follow_distance
	var tablet_basis := Basis.looking_at(world_forward, Vector3.UP) * Basis(Vector3.RIGHT, -deg_to_rad(upward_tilt_degrees))
	global_transform = Transform3D(tablet_basis, target)
	placed = true


func set_room_mode(value: bool, small: bool) -> void:
	small = small and value
	if in_room != value or compact != small:
		in_room = value
		compact = small
		_reset_placement()


func play_click_feedback() -> void:
	# This panel is only used by XR. Desktop UI never invokes this path.
	click_audio.play()
	click_feedback.emit()
	if is_instance_valid(input_pointer):
		var controller := input_pointer.get_parent() as XRController3D
		if controller != null and controller.get_is_active():
			controller.trigger_haptic_pulse("haptic", 0.0, 0.25, 0.035, 0.0)


func is_hand_pointer(pointer: Node3D) -> bool:
	for contact in hand_contacts.values():
		if contact.pointer == pointer:
			return true
	return false


func _check_withdrawal() -> void:
	if not is_instance_valid(origin):
		return
	for side in hand_contacts:
		var contact := hand_contacts[side]
		if contact.armed:
			continue
		var tracker := PlatformXRInput.hand_tracker(side)
		if PlatformXRInput.optical_hand(tracker) and PlatformXRInput.joint_valid(tracker, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP):
			var tip := tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP).origin * XRServer.world_scale
			# A small withdrawal keeps rapid taps practical. Tracking-space
			# contact survives UI changes and artificial locomotion.
			if (contact.contact_frame.affine_inverse() * tip).z > 0.012:
				contact.armed = true


func _update_touch() -> void:
	for side in hand_contacts:
		_update_hand_touch(side, hand_contacts[side])


func _update_hand_touch(side: String, contact: HandContact) -> void:
	var tracker := PlatformXRInput.hand_tracker(side)
	if not PlatformXRInput.optical_hand(tracker) or not PlatformXRInput.joint_valid(tracker, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP):
		_release_hand(contact)
		return
	var tip := PlatformXRInput.joint_world(origin, tracker, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP).origin
	contact.pointer.global_position = tip
	var point := to_local(tip)
	contact.pointer.set_meta("ui_poke_depth", point.z)
	var at := to_global(Vector3(point.x, point.y, 0))
	var in_bounds := contains_ui_point(at)
	if in_bounds and point.z >= -0.08 and point.z < 0.18:
		origin.set_meta("ui_hand_overlay_" + side, 1.0 - smoothstep(0.025, 0.16, maxf(0.0, point.z)))
	var target := _surface_body
	if not contact.touching:
		if in_bounds:
			contact.approach.sample(point)
		else:
			contact.approach.reset()
		var hover_distance := 0.20 if contact.hovering else 0.15
		var near_surface := in_bounds and point.z >= -0.08 and point.z <= hover_distance
		if near_surface:
			if not contact.hovering:
				XRToolsPointerEvent.entered(contact.pointer, target, at)
				contact.hovering = true
			XRToolsPointerEvent.moved(contact.pointer, target, at, contact.last_touch if contact.last_touch != Vector3.ZERO else at)
			contact.last_touch = at
		elif contact.hovering:
			XRToolsPointerEvent.exited(contact.pointer, target, contact.last_touch)
			contact.hovering = false
	if contact.touching:
		if not in_bounds or point.z > 0.012 or point.z < -0.08:
			_release_hand(contact, not in_bounds or point.z < -0.08)
		else:
			XRToolsPointerEvent.moved(contact.pointer, target, at, contact.last_touch)
			contact.last_touch = at
	elif contact.armed and in_bounds and is_finite(contact.previous_depth) and contact.previous_depth > 0.006 and point.z <= 0.006 and point.z >= -0.04:
		contact.pointer.set_meta("ui_poke_intent", contact.approach.intent())
		contact.approach.reset()
		contact.touching = true
		contact.armed = false
		contact.contact_frame = (origin.global_transform * XRServer.get_reference_frame()).affine_inverse() * global_transform
		contact.last_touch = at
		if not contact.hovering:
			XRToolsPointerEvent.entered(contact.pointer, target, at)
			contact.hovering = true
		XRToolsPointerEvent.moved(contact.pointer, target, at, at)
		XRToolsPointerEvent.pressed(contact.pointer, target, at)
	contact.previous_depth = point.z


func contains_ui_point(world_point: Vector3) -> bool:
	var ui := $Viewport.get_child(0)
	return ui.xr_point_is_visible($StaticBody3D.global_to_viewport(world_point))


func release_touch(cancelled := true) -> void:
	_clear_hand_overlays()
	for contact in hand_contacts.values():
		_release_hand(contact, cancelled)


func _release_hand(contact: HandContact, cancelled := true) -> void:
	if contact.touching and is_instance_valid(contact.pointer):
		contact.touching = false
		if cancelled:
			var outside := to_global(Vector3(screen_size.x, screen_size.y, 0))
			XRToolsPointerEvent.moved(contact.pointer, _surface_body, outside, contact.last_touch)
			contact.last_touch = outside
		XRToolsPointerEvent.released(contact.pointer, _surface_body, contact.last_touch)
		XRToolsPointerEvent.exited(contact.pointer, _surface_body, contact.last_touch)
		contact.hovering = false
	elif contact.hovering and is_instance_valid(contact.pointer):
		XRToolsPointerEvent.exited(contact.pointer, _surface_body, contact.last_touch)
		contact.hovering = false
	contact.previous_depth = INF
	contact.approach.reset()


func _clear_hand_overlays() -> void:
	if is_instance_valid(origin):
		origin.set_meta("ui_hand_overlay_left", 0.0)
		origin.set_meta("ui_hand_overlay_right", 0.0)


func _exit_tree() -> void:
	_clear_hand_overlays()
