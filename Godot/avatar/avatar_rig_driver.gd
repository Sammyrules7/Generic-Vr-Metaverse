class_name AvatarRigDriver
extends Node3D
## Poses an imported VRM humanoid from the container's body-relative anchors.
##
## The model is translated and yawed so the head bone lands on the head anchor
## and the body faces the anchor's look direction. The arms are solved by
## Godot's native TwoBoneIK3D modifiers, which are parented to the skeleton so
## they run before the VRM spring bones.
##
## Visibility follows the importer's head hiding split: the imported layer mask
## decides what a viewer may see, the first person (headless) meshes and the
## third person meshes are swapped between layer 1 and no layer at all, so the
## local player sees its own body without a head while remote players keep
## theirs. Cameras are never reconfigured.
##
## The camera is lined up with the eyes, not with the head bone origin: VRM
## stores the eye position in a LookOffset node under the head attachment.
##
## Known alpha limitation: the avatar is never rescaled, because scaling a
## Skeleton3D breaks the native spring bone simulator. A model that is shorter
## than the tracked head height therefore floats above the floor instead of
## standing on it; the eyes still track exactly.

const PROCESS_PRIORITY := 10
## The skeleton must consume the targets of the frame the driver just wrote.
const SKELETON_PRIORITY := 20
const SKELETON_NAME := "GeneralSkeleton"
const HEAD_BONE := "Head"
const NECK_BONE := "Neck"
## Render layer 1 is the layer the world cameras draw.
const VISIBLE_LAYER := 1
## No layer at all: hidden from every camera, whatever its cull mask is.
const HIDDEN_LAYER := 0
## Import contract: the first person layer the importer writes the headless
## meshes to, and the third person layer it writes the full meshes to.
const FIRST_PERSON_LAYER := 2
const THIRD_PERSON_LAYER := 1
const ORIGINAL_LAYERS_META := "avatar_rig_original_layers"
## Desktop hands hang slightly short of full stretch so the elbow keeps a bend.
const DESKTOP_REACH := 0.95
const ARM_BONES := {
	"left": ["LeftUpperArm", "LeftLowerArm", "LeftHand"],
	"right": ["RightUpperArm", "RightLowerArm", "RightHand"],
}

var avatar_model: Node3D
var skeleton: Skeleton3D
var head_anchor: Node3D
var left_anchor: Node3D
var right_anchor: Node3D
var is_local := false
var vr_mode := false
## Native IK modifiers keyed by "left" and "right".
var arm_ik := {}
## Proxy nodes the IK modifiers aim at, keyed by "left" and "right".
var hand_target := {}
## Pole nodes that steer the elbows, keyed by "left" and "right".
var arm_pole := {}

var _space: Node3D
var _head_bone := -1
var _neck_bone := -1
var _head_rest_model := Vector3.ZERO
var _head_rest_basis_model := Basis.IDENTITY
var _forward_model := Vector3.BACK
var _model_to_space := Basis.IDENTITY
var _desktop_target := {}
var _original_layers := {}
var _original_model: Node3D
var _configured := false
var _last_yaw := 0.0


func _ready() -> void:
	process_priority = PROCESS_PRIORITY
	set_process(false)


## Bind an imported avatar model to the container's body relative anchors.
func configure(model: Node3D, head: Node3D, left: Node3D, right: Node3D, local: bool, use_vr: bool) -> void:
	avatar_model = model
	head_anchor = head
	left_anchor = left
	right_anchor = right
	is_local = local
	vr_mode = use_vr
	process_priority = PROCESS_PRIORITY
	_configured = false
	_clear_ik()
	if avatar_model == null or not avatar_model.is_inside_tree():
		return
	_space = avatar_model.get_parent() as Node3D
	if _space == null:
		return
	skeleton = _find_skeleton(avatar_model)
	if skeleton == null:
		push_warning("AvatarRigDriver: avatar model has no humanoid skeleton")
		return
	# The native IK modifiers read the interpolated transforms of the skeleton
	# and of their targets. Interpolated poses lag the tracked body by a frame,
	# so every node of the rig stays on the current transform.
	avatar_model.physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_OFF
	skeleton.physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_OFF
	skeleton.process_priority = SKELETON_PRIORITY
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE
	if _original_model != avatar_model:
		_original_layers.clear()
		_capture_mesh_layers()
		_original_model = avatar_model
	_read_rest_geometry()
	_build_arm_ik()
	_apply_mesh_layers()
	_configured = true
	set_process(true)


## Switch between tracked hand targets and the natural desktop rest pose.
func set_control_mode(use_vr: bool) -> void:
	vr_mode = use_vr
	_apply_desktop_targets()


## Put the imported layer split back, for previews that show the full model.
func restore_original_layers() -> void:
	for mesh in _original_layers:
		if is_instance_valid(mesh):
			mesh.layers = _original_layers[mesh]


func _process(_delta: float) -> void:
	if not _configured:
		return
	_update_body_pose()
	_update_hand_targets()


func _find_skeleton(root: Node3D) -> Skeleton3D:
	var found := root.get_node_or_null("%" + SKELETON_NAME) as Skeleton3D
	if found == null:
		found = root.find_child(SKELETON_NAME, true, false) as Skeleton3D
	if found == null:
		var candidates := root.find_children("*", "Skeleton3D", true, false)
		found = candidates[0] as Skeleton3D if not candidates.is_empty() else null
	return found


func _clear_ik() -> void:
	for side in arm_ik:
		var modifier: Node = arm_ik[side]
		if is_instance_valid(modifier):
			modifier.get_parent().remove_child(modifier)
			modifier.free()
	for side in hand_target:
		var target: Node = hand_target[side]
		if is_instance_valid(target):
			target.get_parent().remove_child(target)
			target.free()
	for side in arm_pole:
		var pole: Node = arm_pole[side]
		if is_instance_valid(pole):
			pole.get_parent().remove_child(pole)
			pole.free()
	arm_ik.clear()
	hand_target.clear()
	arm_pole.clear()
	_desktop_target.clear()
	skeleton = null
	_space = null
	_head_bone = -1
	_neck_bone = -1


# Visibility


func _mesh_instances() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if avatar_model == null:
		return result
	for node in avatar_model.find_children("*", "MeshInstance3D", true, false):
		result.append(node as MeshInstance3D)
	return result


func _capture_mesh_layers() -> void:
	_original_layers.clear()
	for mesh in _mesh_instances():
		_original_layers[mesh] = mesh.layers
		mesh.set_meta(ORIGINAL_LAYERS_META, mesh.layers)


func _apply_mesh_layers() -> void:
	# The imported layer mask is the contract: the first person layer carries
	# the headless meshes, the third person layer the full ones. A mesh that
	# was imported into both layers stays visible for every viewer.
	for mesh in _mesh_instances():
		var original: int = _original_layers.get(mesh, 0)
		var visible := false
		if is_local:
			visible = (original & FIRST_PERSON_LAYER) != 0
		else:
			visible = (original & THIRD_PERSON_LAYER) != 0
		mesh.layers = VISIBLE_LAYER if visible else HIDDEN_LAYER


# Rest geometry


func _read_rest_geometry() -> void:
	_head_bone = skeleton.find_bone(HEAD_BONE)
	_neck_bone = skeleton.find_bone(NECK_BONE)
	if _neck_bone < 0 and _head_bone >= 0:
		_neck_bone = skeleton.get_bone_parent(_head_bone)
	var skeleton_local := avatar_model.global_transform.affine_inverse() * skeleton.global_transform
	var eye_offset := _eye_offset_model()
	if _head_bone >= 0:
		# The camera has to line up with the eyes, not with the bone origin.
		var head_rest := skeleton_local * skeleton.get_bone_global_rest(_head_bone)
		_head_rest_model = (head_rest * Transform3D(Basis.IDENTITY, eye_offset)).origin
		_head_rest_basis_model = head_rest.basis
	var up := _body_up_skeleton()
	var left := _body_left_skeleton()
	var forward := left.cross(up).normalized()
	# Model space axes, used to align the model with the container's frame.
	var to_model := skeleton_local.basis.inverse()
	var up_model := (to_model * up).normalized()
	var left_model := (to_model * left).normalized()
	_forward_model = left_model.cross(up_model).normalized()
	var z_model := -_forward_model
	var x_model := up_model.cross(z_model).normalized()
	_model_to_space = Basis(x_model, up_model, z_model).inverse()


func _eye_offset_model() -> Vector3:
	# VRM keeps the eye position in a LookOffset node below the head bone
	# attachment. The offset is expressed in the head bone frame.
	for attachment in avatar_model.find_children("*", "BoneAttachment3D", true, false):
		if attachment.bone_name != HEAD_BONE:
			continue
		var look := attachment.find_child("LookOffset", true, false) as Node3D
		if look == null:
			for child in attachment.get_children():
				if child is Node3D:
					look = child
					break
		if look != null:
			return look.transform.origin
	return Vector3.ZERO


func _rest_skeleton(bone_name: String) -> Vector3:
	var index := skeleton.find_bone(bone_name)
	if index < 0:
		return Vector3.ZERO
	return skeleton.get_bone_global_rest(index).origin


func _body_up_skeleton() -> Vector3:
	var hips := _rest_skeleton("Hips")
	var chest := _rest_skeleton("Chest")
	if chest.is_zero_approx():
		chest = _rest_skeleton("UpperChest")
	if chest.is_zero_approx():
		chest = _rest_skeleton("Spine")
	var up := chest - hips
	if up.length_squared() < 1e-8:
		up = _rest_skeleton(HEAD_BONE) - hips
	if up.length_squared() < 1e-8:
		return Vector3.UP
	return up.normalized()


func _body_left_skeleton() -> Vector3:
	var left := _rest_skeleton("LeftHand") - _rest_skeleton("RightHand")
	if left.length_squared() < 1e-8:
		left = _rest_skeleton("LeftUpperArm") - _rest_skeleton("RightUpperArm")
	if left.length_squared() < 1e-8:
		return Vector3.LEFT
	return left.normalized()


# Arms


func _build_arm_ik() -> void:
	for side in ARM_BONES:
		var names: Array = ARM_BONES[side]
		var upper := skeleton.find_bone(names[0])
		var lower := skeleton.find_bone(names[1])
		var hand := skeleton.find_bone(names[2])
		if upper < 0 or lower < 0 or hand < 0:
			continue
		var suffix := str(side).capitalize()
		var target := Node3D.new()
		target.name = "AvatarRigHandTarget" + suffix
		target.physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_OFF
		skeleton.add_child(target)
		var pole := Node3D.new()
		pole.name = "AvatarRigHandPole" + suffix
		pole.physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_OFF
		skeleton.add_child(pole)
		var ik := TwoBoneIK3D.new()
		ik.name = "AvatarRigArmIK" + suffix
		skeleton.add_child(ik)
		ik.set_setting_count(1)
		ik.set_root_bone_name(0, names[0])
		ik.set_middle_bone_name(0, names[1])
		ik.set_end_bone_name(0, names[2])
		ik.set_target_node(0, NodePath("../" + target.name))
		ik.set_pole_node(0, NodePath("../" + pole.name))
		ik.set_pole_direction(0, SkeletonModifier3D.SECONDARY_DIRECTION_NONE)
		hand_target[side] = target
		arm_pole[side] = pole
		arm_ik[side] = ik
		# Native modifiers run in child order, so the IK has to precede the
		# VRM spring bones that are installed after this driver.
		skeleton.move_child(ik, 0)
	_compute_arm_poses()


func _compute_arm_poses() -> void:
	var up := _body_up_skeleton()
	var left := _body_left_skeleton()
	var forward := left.cross(up).normalized()
	for side in ARM_BONES:
		if not arm_ik.has(side):
			continue
		var names: Array = ARM_BONES[side]
		var upper := _rest_skeleton(names[0])
		var lower := _rest_skeleton(names[1])
		var hand := _rest_skeleton(names[2])
		var outward := left if side == "left" else -left
		# The elbow follows the pole, so point it down and slightly behind.
		var pole_dir := (-forward * 0.9 + outward * 0.3).normalized()
		var pole: Node3D = arm_pole[side]
		pole.transform = Transform3D(Basis.IDENTITY, upper + pole_dir * maxf((lower - upper).length(), 0.05))
		# Desktop hands hang from the rest pose instead of the import T-pose.
		var arm_dir := lower - upper
		if arm_dir.length_squared() < 1e-8:
			arm_dir = Vector3.RIGHT
		var rotation := _rotation_from_to(arm_dir.normalized(), -up)
		var target: Node3D = hand_target[side]
		_desktop_target[side] = Transform3D(Basis.IDENTITY, upper + rotation * (hand - upper) * DESKTOP_REACH)
	_apply_desktop_targets()


func _apply_desktop_targets() -> void:
	if vr_mode:
		return
	for side in _desktop_target:
		var node: Node3D = hand_target.get(side)
		if node != null:
			node.transform = _desktop_target[side]


func _update_hand_targets() -> void:
	if not vr_mode:
		return
	for side in hand_target:
		var anchor := _anchor_for(side)
		if anchor == null:
			continue
		var node: Node3D = hand_target[side]
		node.global_transform = anchor.global_transform


func _anchor_for(side: String) -> Node3D:
	return left_anchor if side == "left" else right_anchor


static func _rotation_from_to(from: Vector3, to: Vector3) -> Quaternion:
	var a := from.normalized()
	var b := to.normalized()
	var axis := a.cross(b)
	if axis.length_squared() < 1e-10:
		if a.dot(b) > 0.0:
			return Quaternion.IDENTITY
		# Opposite directions: any perpendicular axis gives the same half turn.
		var fallback := Vector3.UP if absf(a.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		return Quaternion(fallback.normalized(), PI)
	return Quaternion(axis.normalized(), a.angle_to(b))


# Body placement


func _update_body_pose() -> void:
	if avatar_model == null or skeleton == null or head_anchor == null or _space == null:
		return
	var anchor := _space.global_transform.affine_inverse() * head_anchor.global_transform
	# The body follows the anchor's horizontal look direction.
	var desired := -anchor.basis.z
	desired.y = 0.0
	# A vertical gaze has no horizontal heading. Retain the previous heading
	# while looking down at one's body instead of snapping to a fixed direction.
	if desired.length_squared() >= 1e-8:
		_last_yaw = atan2(-desired.x, -desired.z)
	var basis := Basis(Vector3.UP, _last_yaw) * _model_to_space
	var origin := anchor.origin - basis * _head_rest_model
	avatar_model.transform = Transform3D(basis, origin)
	_apply_head_rotation(anchor)


func _apply_head_rotation(anchor: Transform3D) -> void:
	if _head_bone < 0:
		return
	var parent := _neck_bone if _neck_bone >= 0 else skeleton.get_bone_parent(_head_bone)
	if parent < 0:
		return
	# The anchor is the camera. The head keeps the orientation the model was
	# authored with and only follows the anchor on top of it, so a neutral
	# anchor leaves the imported head pose untouched.
	var desired := anchor.basis.get_rotation_quaternion() \
		* _model_to_space.get_rotation_quaternion() \
		* _head_rest_basis_model.get_rotation_quaternion()
	var skeleton_rotation := (avatar_model.transform.basis * skeleton.transform.basis).get_rotation_quaternion()
	var parent_rotation := skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(_head_bone, parent_rotation.inverse() * skeleton_rotation.inverse() * desired)
