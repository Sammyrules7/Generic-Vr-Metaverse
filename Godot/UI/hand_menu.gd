extends XRToolsViewport2DIn3D
## A readable, smoothed tablet above the left hand. Finger contact uses the
## same UI event path as controller rays, including dragging and release.

var origin: XROrigin3D
var camera: XRCamera3D
var anchor: XRController3D
var touch_pointer: Node3D
var touching := false
var last_touch := Vector3.ZERO
var previous_depth := INF
var placed := false


func _ready() -> void:
	super._ready()
	touch_pointer = Node3D.new()
	touch_pointer.name = "FingertipTouch"
	add_child(touch_pointer)
	process_priority = 20


func bind_rig(new_origin: XROrigin3D, new_camera: XRCamera3D, new_anchor: XRController3D) -> void:
	release_touch()
	origin = new_origin
	camera = new_camera
	anchor = new_anchor
	placed = false


func _process(delta: float) -> void:
	super._process(delta)
	if not visible or not enabled or not is_instance_valid(origin) or not is_instance_valid(camera):
		release_touch()
		placed = false
		return
	var tracker := PlatformXRInput.hand_tracker("left")
	var target := camera.global_position - camera.global_basis.z * 0.55
	if PlatformXRInput.joint_valid(tracker, XRHandTracker.HAND_JOINT_PALM):
		target = PlatformXRInput.joint_world(origin, tracker, XRHandTracker.HAND_JOINT_PALM).origin + Vector3.UP * 0.16
	elif is_instance_valid(anchor) and anchor.get_is_active():
		target = anchor.global_position + Vector3.UP * 0.16
	# Keep the whole tablet in a comfortable field of view when the anchor
	# approaches the face or drifts toward the edge of tracking.
	var local := camera.to_local(target)
	local.z = minf(local.z, -0.5)
	var horizontal_room := maxf(0.0, -local.z * 0.65 - screen_size.x * 0.5)
	var vertical_room := maxf(0.0, -local.z * 0.5 - screen_size.y * 0.5)
	local.x = clampf(local.x, -horizontal_room, horizontal_room)
	local.y = clampf(local.y, -vertical_room, vertical_room)
	target = camera.to_global(local)
	var desired := Transform3D(Basis.IDENTITY, target).looking_at(target + (target - camera.global_position).normalized(), Vector3.UP)
	# Freeze while touching so smoothing cannot slide controls under a finger.
	if not touching:
		global_transform = global_transform.interpolate_with(desired, 1.0 - exp(-14.0 * delta)) if placed else desired
		placed = true
	_update_touch()


func _update_touch() -> void:
	var tracker := PlatformXRInput.hand_tracker("right")
	if not PlatformXRInput.optical_hand(tracker) or not PlatformXRInput.joint_valid(tracker, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP):
		release_touch()
		return
	var tip := PlatformXRInput.joint_world(origin, tracker, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP).origin
	touch_pointer.global_position = tip
	var point := to_local(tip)
	var at := to_global(Vector3(point.x, point.y, 0))
	var in_bounds := contains_ui_point(at)
	var target := $StaticBody3D
	if touching:
		if not in_bounds or point.z > 0.035 or point.z < -0.08:
			release_touch(not in_bounds or point.z < -0.08)
		else:
			XRToolsPointerEvent.moved(touch_pointer, target, at, last_touch)
			last_touch = at
	elif in_bounds and previous_depth > 0.012 and point.z <= 0.012 and point.z >= -0.04:
		touching = true
		last_touch = at
		XRToolsPointerEvent.entered(touch_pointer, target, at)
		XRToolsPointerEvent.moved(touch_pointer, target, at, at)
		XRToolsPointerEvent.pressed(touch_pointer, target, at)
	previous_depth = point.z


func contains_ui_point(world_point: Vector3) -> bool:
	var ui := $Viewport.get_child(0)
	return ui.xr_point_is_visible($StaticBody3D.global_to_viewport(world_point))


func release_touch(cancelled := true) -> void:
	if touching and is_instance_valid(touch_pointer):
		touching = false
		if cancelled:
			var outside := to_global(Vector3(screen_size.x, screen_size.y, 0))
			XRToolsPointerEvent.moved(touch_pointer, $StaticBody3D, outside, last_touch)
			last_touch = outside
		XRToolsPointerEvent.released(touch_pointer, $StaticBody3D, last_touch)
		XRToolsPointerEvent.exited(touch_pointer, $StaticBody3D, last_touch)
	previous_depth = INF
