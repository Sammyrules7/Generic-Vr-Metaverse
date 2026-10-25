class_name PlatformXRInput
extends RefCounted
## Shared input names and tracking-space conversion for native and browser XR.

static func stick(controller: XRController3D) -> Vector2:
	if controller == null:
		return Vector2.ZERO
	var result := Vector2.ZERO
	for action: String in ["primary", "thumbstick", "touchpad"]:
		var value := controller.get_vector2(action)
		if value.length_squared() > result.length_squared():
			result = value
	return result


static var _neutral_controller_material: ShaderMaterial

static func prepare_hand_model(model: Node) -> void:
	if _neutral_controller_material == null:
		_neutral_controller_material = ShaderMaterial.new()
		_neutral_controller_material.shader = preload("res://player/neutral_hand.gdshader")
	# These are moving meshes, including when a restored import cache still
	# contains a scene generated with the importer's default Static GI mode.
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
		mesh.material_override = _neutral_controller_material


# Godot hand trackers already use the humanoid joint basis; controller grip
# poses use OpenXR's grip basis and need this conversion for avatar wrists.
const GRIP_TO_HUMANOID := Basis(Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0))

static var _tracker_paths := {"left": &"/user/hand_tracker/left", "right": &"/user/hand_tracker/right"}


static func hand_tracker(hand: String, require_tracking := true) -> XRHandTracker:
	# Trackers can appear, disappear, or be replaced after the rig is created,
	# so the handle is always resolved live. The path StringNames are built
	# once; per-call string concatenation was the actual alloc overhead here.
	# (A cached handle went stale across add/remove and crashed at exit via
	# singleton signal teardown, so no cache and no signal hooks.)
	var path: StringName = _tracker_paths.get(hand, StringName("/user/hand_tracker/" + hand))
	var tracker := XRServer.get_tracker(path) as XRHandTracker
	return tracker if tracker != null and (not require_tracking or tracker.has_tracking_data) else null


static func joint_valid(tracker: XRHandTracker, joint: int) -> bool:
	return tracker != null and (tracker.get_hand_joint_flags(joint) & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID) != 0


static func optical_hand(tracker: XRHandTracker) -> bool:
	if tracker == null or tracker.hand_tracking_source == XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER:
		return false
	# WebXR leaves the source UNKNOWN and retains the hand tracker after
	# switching to controllers. Its old identity must not suppress live grips.
	# Explicit optical sources still suppress fallback during brief native gaps.
	return tracker.has_tracking_data or tracker.hand_tracking_source != XRHandTracker.HAND_TRACKING_SOURCE_UNKNOWN


static func joint_world(origin: XROrigin3D, tracker: XRHandTracker, joint: int) -> Transform3D:
	var pose := tracker.get_hand_joint_transform(joint)
	pose.origin *= XRServer.world_scale
	return origin.global_transform * XRServer.get_reference_frame() * pose
