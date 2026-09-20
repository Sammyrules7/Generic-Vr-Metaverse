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


static func hand_tracker(hand: String) -> XRHandTracker:
	# Trackers can appear, disappear, or be replaced after the rig is created.
	var tracker := XRServer.get_tracker("/user/hand_tracker/" + hand) as XRHandTracker
	return tracker if tracker != null and tracker.has_tracking_data else null


static func joint_valid(tracker: XRHandTracker, joint: int) -> bool:
	return tracker != null and (tracker.get_hand_joint_flags(joint) & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID) != 0


static func optical_hand(tracker: XRHandTracker) -> bool:
	return tracker != null and tracker.hand_tracking_source != XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER


static func joint_world(origin: XROrigin3D, tracker: XRHandTracker, joint: int) -> Transform3D:
	var pose := tracker.get_hand_joint_transform(joint)
	pose.origin *= XRServer.world_scale
	return origin.global_transform * XRServer.get_reference_frame() * pose
