extends Node3D
## Drive the bundled legacy XR hand skeleton directly from tracked joints.
## No controller grip offsets or canned finger animations are used in this rig.

@export_enum("left", "right") var hand := "left"
const JOINT_NAMES := ["Palm", "Wrist", "Thumb_Metacarpal", "Thumb_Proximal", "Thumb_Distal", "Thumb_Tip", "Index_Metacarpal", "Index_Proximal", "Index_Intermediate", "Index_Distal", "Index_Tip", "Middle_Metacarpal", "Middle_Proximal", "Middle_Intermediate", "Middle_Distal", "Middle_Tip", "Ring_Metacarpal", "Ring_Proximal", "Ring_Intermediate", "Ring_Distal", "Ring_Tip", "Little_Metacarpal", "Little_Proximal", "Little_Intermediate", "Little_Distal", "Little_Tip"]
# XRHandTracker uses Godot humanoid axes; the bundled meshes use OpenXR axes.
const LEGACY_AXES := Basis(Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0))
var skeleton: Skeleton3D
var bone_joints: Dictionary[int, int] = {}


func _ready() -> void:
	var path := "res://addons/godot-xr-tools/hands/model/Hand_Nails_low_%s.gltf" % ("L" if hand == "left" else "R")
	var model := (load(path) as PackedScene).instantiate()
	add_child(model)
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	var suffix := "_L" if hand == "left" else "_R"
	for joint in JOINT_NAMES.size():
		var bone := skeleton.find_bone(JOINT_NAMES[joint] + suffix)
		if bone >= 0:
			bone_joints[bone] = joint
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = load("res://addons/godot-xr-tools/hands/materials/caucasian_hand.tres")
	process_priority = 5
	hide()


func _process(_delta: float) -> void:
	var tracker := PlatformXRInput.hand_tracker(hand)
	visible = PlatformXRInput.optical_hand(tracker) and PlatformXRInput.joint_valid(tracker, XRHandTracker.HAND_JOINT_PALM)
	if not visible:
		return
	var origin := get_parent() as XROrigin3D
	global_transform = PlatformXRInput.joint_world(origin, tracker, XRHandTracker.HAND_JOINT_PALM)
	global_basis *= LEGACY_AXES
	var poses: Dictionary[int, Transform3D] = {}
	for bone: int in bone_joints:
		var joint: int = bone_joints[bone]
		if not PlatformXRInput.joint_valid(tracker, joint):
			continue
		var world_pose := PlatformXRInput.joint_world(origin, tracker, joint)
		world_pose.basis *= LEGACY_AXES
		poses[bone] = skeleton.global_transform.affine_inverse() * world_pose
	for bone: int in poses:
		var parent := skeleton.get_bone_parent(bone)
		var pose: Transform3D = poses[bone]
		if parent >= 0:
			var parent_pose: Transform3D = poses.get(parent, skeleton.get_bone_global_pose(parent))
			pose = parent_pose.affine_inverse() * pose
		# Preserve the mesh's authored bone lengths. Applying tracked positions to
		# every bone stretches the skinned mesh into the user's raw joint spacing.
		# Bone poses are deltas from rest, not absolute local rotations.
		var rest := skeleton.get_bone_rest(bone)
		var rotation_delta := (rest.basis.inverse() * pose.basis).orthonormalized()
		skeleton.set_bone_pose_rotation(bone, rotation_delta.get_rotation_quaternion())
