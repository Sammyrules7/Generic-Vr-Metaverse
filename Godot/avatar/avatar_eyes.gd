class_name AvatarEyes
extends RefCounted
## Resolve the viewpoint in head-bone space, including VRMs without look offsets.

static func offset(model: Node3D, skeleton: Skeleton3D) -> Vector3:
	var head := skeleton.find_bone("Head")
	if head < 0:
		return Vector3.ZERO
	var head_rest := skeleton.get_bone_global_rest(head)
	var left := skeleton.find_bone("LeftEye")
	var right := skeleton.find_bone("RightEye")
	if left >= 0 and right >= 0:
		var midpoint := (skeleton.get_bone_global_rest(left).origin + skeleton.get_bone_global_rest(right).origin) * 0.5
		return head_rest.affine_inverse() * midpoint
	for attachment in model.find_children("*", "BoneAttachment3D", true, false):
		if attachment.bone_name == "Head":
			var look := attachment.find_child("LookOffset", true, false) as Node3D
			if look != null and not look.position.is_zero_approx():
				return look.position
	# Head joints typically sit near the base of the skull, below the eyes.
	# Use neck length to adapt the fallback to the imported avatar's proportions.
	var neck := skeleton.find_bone("Neck")
	var height := 0.1
	if neck >= 0:
		height = clampf(head_rest.origin.distance_to(skeleton.get_bone_global_rest(neck).origin), 0.06, 0.14)
	return head_rest.basis.inverse() * Vector3.UP * height
