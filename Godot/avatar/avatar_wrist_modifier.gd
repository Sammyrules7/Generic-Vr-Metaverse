extends SkeletonModifier3D
## TwoBoneIK3D solves the limb, but does not copy the target's end orientation.
## Run after arm IK so wrist position and rotation both match tracked anchors.
var targets := {}
var bones := {}

func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var inverse := skeleton.global_transform.affine_inverse()
	for side in targets:
		var target := targets[side] as Node3D
		var bone := int(bones.get(side, -1))
		if is_instance_valid(target) and bone >= 0:
			skeleton.set_bone_global_pose(bone, inverse * target.global_transform)
