class_name AvatarRigDriver
extends Node3D
## Poses an imported VRM humanoid from the container's body-relative anchors.
##
## The model is translated and yawed so the head bone lands on the head anchor
## and the body faces the anchor's look direction. The arms are solved by
## Godot's native TwoBoneIK3D modifiers, which are parented to the skeleton so
## they run before the VRM spring bones.
##
## Local full-body geometry stays on AvatarView.FULL_BODY for mirrors. The VR
## body uses AvatarView.FIRST_PERSON; desktop cameras draw neither. Remote
## avatars remain on the ordinary world layer. Import masks are kept separately.
##
## The camera is lined up with the eyes, not with the head bone origin: VRM
## stores the eye position in a LookOffset node under the head attachment.
##
## Desktop idle, walking and jogging use CC0-derived humanoid tracks. They are retargeted
## as motion around each track's own mean, so an avatar keeps its own rest
## stance, bone directions and proportions. Untracked VR applies only the leg
## part of the same motion; head, neck, arms and hands never receive
## prerecorded motion, and tracked head and hand targets always remain
## authoritative.
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
const VR_BODY_BACK_OFFSET := 0.10
## Restrained lower-body motion in VR keeps the feet close to their floor pose.
const VR_IDLE_SCALE := 0.55
const ARM_BONES := {
	"left": ["LeftUpperArm", "LeftLowerArm", "LeftHand"],
	"right": ["RightUpperArm", "RightLowerArm", "RightHand"],
}
const IDLE_CLIP_PATH := "res://avatar/animations/quaternius_universal_idle_loop.json"
const WALK_CLIP_PATH := "res://avatar/animations/quaternius_universal_walk_loop.json"
const JOG_CLIP_PATH := "res://avatar/animations/quaternius_universal_jog_fwd_loop.json"
const IDLE_CLIP_SCRIPT := "res://avatar/animations/avatar_idle_clip.gd"
## Rest pose rotations the driver owns. Head, neck, arms and fingers are not
## included: tracked targets, IK and the wrist modifier own those.
const CONTROLLED_BONES := [
	"Hips", "Spine", "Chest", "UpperChest",
	"LeftShoulder", "RightShoulder",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
	"RightUpperLeg", "RightLowerLeg", "RightFoot",
]
## VR only animates the legs. Their ancestors stay at rest, so the eye/head
## anchor remains exact for the tracked head. Shoulders stay at rest too, so
## tracked arm roots do not drift.
const VR_IDLE_BONES := [
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
	"RightUpperLeg", "RightLowerLeg", "RightFoot",
]
## Top-down order matters: each aim uses the parent poses already applied.
const CLIP_TRACK_ORDER := [
	"Hips", "Spine", "Chest", "UpperChest",
	"LeftShoulder", "RightShoulder",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
	"RightUpperLeg", "RightLowerLeg", "RightFoot",
]
## Preferred child whose direction defines each source track. The first bone
## that exists in the imported skeleton wins, so incomplete VRMs skip cleanly.
const CLIP_CHILDREN := {
	"Hips": ["Spine", "Chest", "Neck"],
	"Spine": ["Chest", "UpperChest", "Neck"],
	"Chest": ["UpperChest", "Neck"],
	"UpperChest": ["Neck"],
	"LeftShoulder": ["LeftUpperArm"],
	"RightShoulder": ["RightUpperArm"],
	"LeftUpperLeg": ["LeftLowerLeg", "LeftFoot"],
	"LeftLowerLeg": ["LeftFoot", "LeftToes"],
	"LeftFoot": ["LeftToes"],
	"RightUpperLeg": ["RightLowerLeg", "RightFoot"],
	"RightLowerLeg": ["RightFoot", "RightToes"],
	"RightFoot": ["RightToes"],
}

var avatar_model: Node3D
var skeleton: Skeleton3D
var head_anchor: Node3D
var left_anchor: Node3D
var right_anchor: Node3D
var is_local := false
var vr_mode := false
## Future full-body providers set this before wearing the avatar. This driver
## deliberately does not read XRBodyTracker; an unwired tracker must not turn
## into a hidden dependency.
var lower_body_tracked := false
## Ground-aware feet: a physics-tick ray probe and native leg IK. The eye/head
## anchor stays authoritative; only the leg chain and foot orientation move.
var ground_ik_enabled := true
## World collision layers treated as ground. The project's world is layer 1.
var ground_mask := 1
## Separated helper that owns the probes, leg IK and foot orientation.
var ground_feet: Node3D
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
var _head_pose_position := Vector3.ZERO
var _eye_offset := Vector3.ZERO
var _head_rest_basis_model := Basis.IDENTITY
var _forward_model := Vector3.BACK
var _model_to_space := Basis.IDENTITY
var _source_basis := Basis.IDENTITY
var _desktop_target := {}
var _original_layers := {}
var _original_model: Node3D
var _configured := false
var _wrist_modifier: SkeletonModifier3D
var _finger_modifiers := {}
var _last_yaw := 0.0
var _animation_bones := {}
var _motion_position := Vector3.ZERO
var _motion_initialized := false
var _motion_velocity := Vector3.ZERO
var _stride_phase := 0.0
var _idle_time := 0.0
var _idle_clip_time := 0.0
var _idle_phase := 0.0
var _clip_targets: Array[Dictionary] = []
var _arm_lengths := {}
var _walk_clip: RefCounted
var _jog_clip: RefCounted
static var _locomotion_clips := {}
var _idle_clip: RefCounted
static var _shared_idle_clip: RefCounted
static var _idle_clip_warned := false


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
	_capture_animation_pose()
	_build_arm_ik()
	_build_hand_modifiers()
	_build_ground_feet()
	_apply_mesh_layers()
	_configured = true
	set_process(true)


## True when both arm chains resolved to native IK modifiers.
func has_arm_ik() -> bool:
	return arm_ik.has("left") and arm_ik.has("right")


## Switch between tracked hand targets and the natural desktop rest pose.
func set_control_mode(use_vr: bool) -> void:
	_reset_animation_pose()
	_motion_initialized = false
	_motion_velocity = Vector3.ZERO
	_stride_phase = 0.0
	_idle_time = 0.0
	_idle_clip_time = 0.0
	vr_mode = use_vr
	if is_instance_valid(ground_feet):
		ground_feet.reset()
	_apply_mesh_layers()
	_apply_desktop_targets()


## Optional integration hooks for a future body tracker or for world layers
## that put ground somewhere other than layer 1.
func set_ground_mask(mask: int) -> void:
	ground_mask = mask
	if is_instance_valid(ground_feet):
		ground_feet.ground_mask = mask


func set_ground_ik(enabled_flag: bool) -> void:
	ground_ik_enabled = enabled_flag
	if is_instance_valid(ground_feet):
		ground_feet.enabled = enabled_flag
		if not enabled_flag:
			ground_feet.reset()


## Put the imported layer split back, for previews that show the full model.
func restore_original_layers() -> void:
	for mesh in _original_layers:
		if is_instance_valid(mesh):
			mesh.layers = _original_layers[mesh]


func _process(delta: float) -> void:
	if not _configured:
		return
	if vr_mode:
		# A future body solver can claim the lower body. Until then this is the
		# untracked path: animate only legs and feet, never hips, head or arms.
		if not lower_body_tracked:
			_animate_vr_idle(delta)
	else:
		_animate_desktop(delta)
	_update_body_pose()
	_update_hand_targets()
	_update_ground_feet(delta)


func _find_skeleton(root: Node3D) -> Skeleton3D:
	var found := root.get_node_or_null("%" + SKELETON_NAME) as Skeleton3D
	if found == null:
		found = root.find_child(SKELETON_NAME, true, false) as Skeleton3D
	if found == null:
		var candidates := root.find_children("*", "Skeleton3D", true, false)
		found = candidates[0] as Skeleton3D if not candidates.is_empty() else null
	return found


func _clear_ik() -> void:
	if is_instance_valid(ground_feet):
		ground_feet.clear()
		if ground_feet.get_parent() != null:
			ground_feet.get_parent().remove_child(ground_feet)
		ground_feet.free()
	ground_feet = null
	if is_instance_valid(_wrist_modifier):
		_wrist_modifier.free()
	_wrist_modifier = null
	for modifier in _finger_modifiers.values():
		if is_instance_valid(modifier):
			modifier.free()
	_finger_modifiers.clear()
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
	for mesh in _mesh_instances():
		var original: int = _original_layers.get(mesh, 0)
		if is_local:
			mesh.layers = AvatarView.FULL_BODY if (original & THIRD_PERSON_LAYER) != 0 else 0
			if vr_mode and (original & FIRST_PERSON_LAYER) != 0:
				mesh.layers |= AvatarView.FIRST_PERSON
		else:
			mesh.layers = VISIBLE_LAYER if (original & THIRD_PERSON_LAYER) != 0 else HIDDEN_LAYER


# Rest geometry


func _read_rest_geometry() -> void:
	_head_bone = skeleton.find_bone(HEAD_BONE)
	if _head_bone >= 0:
		_head_pose_position = skeleton.get_bone_pose_position(_head_bone)
	_neck_bone = skeleton.find_bone(NECK_BONE)
	if _neck_bone < 0 and _head_bone >= 0:
		_neck_bone = skeleton.get_bone_parent(_head_bone)
	var skeleton_local := avatar_model.global_transform.affine_inverse() * skeleton.global_transform
	var eye_offset := _eye_offset_model()
	_eye_offset = eye_offset
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
	_source_basis = _character_basis()


func _eye_offset_model() -> Vector3:
	return AvatarEyes.offset(avatar_model, skeleton)


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


## Character-space axes (x = left, y = up, z = forward) expressed in skeleton
## space. The CC0 tracks are authored in the same convention.
func _character_basis() -> Basis:
	var up := _body_up_skeleton()
	var left := _body_left_skeleton()
	left = (left - up * left.dot(up)).normalized()
	if left.length_squared() < 1e-8:
		left = Vector3.LEFT
	var forward := left.cross(up).normalized()
	return Basis(left, up, forward)


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


func _build_hand_modifiers() -> void:
	_wrist_modifier = SkeletonModifier3D.new()
	_wrist_modifier.set_script(preload("res://avatar/avatar_wrist_modifier.gd"))
	_wrist_modifier.name = "AvatarWristPose"
	skeleton.add_child(_wrist_modifier)
	for side in hand_target:
		_wrist_modifier.targets[side] = hand_target[side]
		_wrist_modifier.bones[side] = skeleton.find_bone("LeftHand" if side == "left" else "RightHand")
	if not is_local:
		return
	for side in ["left", "right"]:
		var prefix := "Left" if side == "left" else "Right"
		if skeleton.find_bone(prefix + "IndexProximal") < 0:
			continue
		var modifier := XRHandModifier3D.new()
		modifier.name = "AvatarFingers" + prefix
		modifier.hand_tracker = StringName("/user/hand_tracker/" + side)
		modifier.bone_update = XRHandModifier3D.BONE_UPDATE_ROTATION_ONLY
		modifier.active = false
		skeleton.add_child(modifier)
		_finger_modifiers[side] = modifier


func _update_hand_targets() -> void:
	if _wrist_modifier != null:
		_wrist_modifier.active = vr_mode
	for side in _finger_modifiers:
		var tracker := PlatformXRInput.hand_tracker(side)
		_finger_modifiers[side].active = vr_mode and tracker != null and tracker.has_tracking_data
	if not vr_mode:
		return
	for side in hand_target:
		var anchor := _anchor_for(side)
		if anchor == null:
			continue
		var node: Node3D = hand_target[side]
		node.global_transform = anchor.global_transform


## Ground placement is a separate helper so the head/arm solve above stays the
## only authority for the camera, torso and tracked hands.
func _build_ground_feet() -> void:
	if skeleton == null or avatar_model == null:
		return
	var helper = load("res://avatar/avatar_ground_feet.gd").new()
	helper.name = "AvatarGroundFeet"
	add_child(helper)
	helper.ground_mask = ground_mask
	helper.enabled = ground_ik_enabled
	helper.lower_body_tracked = lower_body_tracked
	helper.configure(avatar_model, skeleton, _source_basis)
	ground_feet = helper


func _update_ground_feet(delta: float) -> void:
	if not is_instance_valid(ground_feet):
		return
	ground_feet.enabled = ground_ik_enabled
	ground_feet.lower_body_tracked = lower_body_tracked
	ground_feet.ground_mask = ground_mask
	ground_feet.solve(delta)


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


# Animation


## Desktop locomotion is derived from replicated body movement, so observers and
## mirrors animate without new RPCs. Tracked VR poses never receive this motion.
func _capture_animation_pose() -> void:
	_animation_bones.clear()
	_motion_initialized = false
	_motion_velocity = Vector3.ZERO
	_stride_phase = 0.0
	_idle_time = 0.0
	_idle_clip_time = 0.0
	for bone_name in CONTROLLED_BONES:
		var index := skeleton.find_bone(bone_name)
		if index >= 0:
			_animation_bones[bone_name] = skeleton.get_bone_pose_rotation(index)
	_arm_lengths.clear()
	for side in ARM_BONES:
		var names: Array = ARM_BONES[side]
		var upper := skeleton.find_bone(names[0])
		var hand := skeleton.find_bone(names[2])
		if upper >= 0 and hand >= 0:
			_arm_lengths[side] = skeleton.get_bone_global_rest(upper).origin.distance_to(skeleton.get_bone_global_rest(hand).origin)
	_idle_phase = fmod(float(get_instance_id()), 997.0) * 0.0063
	_load_idle_clip()
	_load_locomotion_clips()
	_build_clip_targets()


func _load_idle_clip() -> void:
	if _shared_idle_clip == null and not _idle_clip_warned:
		var script := load(IDLE_CLIP_SCRIPT)
		if script != null:
			var clip: RefCounted = script.new()
			if clip.load_file(IDLE_CLIP_PATH):
				_shared_idle_clip = clip
			else:
				_idle_clip_warned = true
				push_warning("AvatarRigDriver: idle clip unavailable (" + str(clip.error) + "); using procedural idle")
		else:
			_idle_clip_warned = true
			push_warning("AvatarRigDriver: idle clip helper unavailable; using procedural idle")
	_idle_clip = _shared_idle_clip


func _load_locomotion_clips() -> void:
	for path in [WALK_CLIP_PATH, JOG_CLIP_PATH]:
		if not _locomotion_clips.has(path):
			var clip: RefCounted = load(IDLE_CLIP_SCRIPT).new()
			_locomotion_clips[path] = clip if clip.load_file(path) else null
			if _locomotion_clips[path] == null:
				push_warning("AvatarRigDriver: locomotion clip unavailable: " + path)
	_walk_clip = _locomotion_clips[WALK_CLIP_PATH]
	_jog_clip = _locomotion_clips[JOG_CLIP_PATH]


func _build_clip_targets() -> void:
	_clip_targets.clear()
	for track_name in CLIP_TRACK_ORDER:
		var bone := skeleton.find_bone(track_name)
		if bone < 0:
			continue
		var child := -1
		for candidate in CLIP_CHILDREN.get(track_name, []):
			child = skeleton.find_bone(candidate)
			if child >= 0:
				break
		if child < 0:
			continue
		_clip_targets.append({
			"track": StringName(track_name),
			"bone_name": track_name,
			"bone": bone,
			"child": child,
		})


func _reset_animation_pose() -> void:
	if not is_instance_valid(skeleton):
		return
	for bone_name in _animation_bones:
		var index := skeleton.find_bone(bone_name)
		if index >= 0:
			skeleton.set_bone_pose_rotation(index, _animation_bones[bone_name])


## Rotate a captured rest pose around a skeleton-space axis. This preserves the
## avatar's authored bone roll instead of adopting the source rig's local axes.
func _rest_rotation_with_axis(bone_name: String, axis: Vector3, angle: float) -> Quaternion:
	if not _animation_bones.has(bone_name):
		return Quaternion.IDENTITY
	var rest: Quaternion = _animation_bones[bone_name]
	if absf(angle) < 1e-6:
		return rest
	var index := skeleton.find_bone(bone_name)
	if index < 0:
		return rest
	var local_axis := skeleton.get_bone_global_rest(index).basis.inverse() * axis
	if local_axis.length_squared() < 1e-10:
		return rest
	return (rest * Quaternion(local_axis.normalized(), angle)).normalized()


func _rotate_pose(bone_name: String, pose: Quaternion, axis: Vector3, angle: float) -> Quaternion:
	if absf(angle) < 1e-6:
		return pose
	var index := skeleton.find_bone(bone_name)
	if index < 0:
		return pose
	var local_axis := skeleton.get_bone_global_rest(index).basis.inverse() * axis
	if local_axis.length_squared() < 1e-10:
		return pose
	return (pose * Quaternion(local_axis.normalized(), angle)).normalized()


## Skeleton-space transform of a bone using the poses currently set. The engine's
## cached globals are one frame behind during _process, and the IK modifiers have
## not run yet, so the animation code reads its own forward kinematics.
func _pose_global(index: int) -> Transform3D:
	if index < 0:
		return Transform3D.IDENTITY
	var local := Transform3D(Basis(skeleton.get_bone_pose_rotation(index)), skeleton.get_bone_pose_position(index))
	var parent := skeleton.get_bone_parent(index)
	if parent < 0:
		return local
	return _pose_global(parent) * local


func _rest_direction(bone: int, child: int) -> Vector3:
	var direction := skeleton.get_bone_global_rest(child).origin - skeleton.get_bone_global_rest(bone).origin
	if direction.length_squared() < 1e-10:
		return Vector3.UP
	return direction.normalized()


## Aim a bone at a skeleton-space direction while preserving its roll.
func _aim_bone(bone: int, child: int, desired: Vector3) -> void:
	if desired.length_squared() < 1e-10:
		return
	var bone_pose := _pose_global(bone)
	var child_pose := _pose_global(child)
	var current := child_pose.origin - bone_pose.origin
	if current.length_squared() < 1e-10:
		return
	var swing := _rotation_from_to(current.normalized(), desired.normalized())
	var global_rotation := (swing * bone_pose.basis.get_rotation_quaternion()).normalized()
	var parent := skeleton.get_bone_parent(bone)
	var parent_rotation := Quaternion.IDENTITY
	if parent >= 0:
		parent_rotation = _pose_global(parent).basis.get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(bone, (parent_rotation.inverse() * global_rotation).normalized())


func _animate_desktop(delta: float) -> void:
	if vr_mode or delta <= 0.0 or _space == null:
		return
	var position_now := _space.global_position
	var movement := position_now - _motion_position if _motion_initialized else Vector3.ZERO
	_motion_position = position_now
	_motion_initialized = true
	# A teleport or paused frame must not turn into a high-speed walk cycle.
	if movement.length() > 0.75 or delta > 0.2:
		_motion_velocity = Vector3.ZERO
		_stride_phase = 0.0
		movement = Vector3.ZERO
	var velocity := movement / delta
	velocity.y = 0.0
	_motion_velocity = _motion_velocity.lerp(velocity, 1.0 - exp(-10.0 * delta))
	var speed := minf(_motion_velocity.length(), 7.0)
	var weight := smoothstep(0.05, 0.8, speed)
	var jog_weight := smoothstep(1.8, 3.5, speed) if _jog_clip != null else 0.0
	_idle_time += delta
	_idle_clip_time += delta
	var direction := skeleton.global_basis.orthonormalized().inverse() * _motion_velocity.normalized() if speed > 0.01 else _source_basis.z
	var forward_weight := direction.dot(_source_basis.z)
	var side_weight := direction.dot(_source_basis.x)
	# Advance by distance, with one shared contact phase for walk and jog.
	# Scale stride length to the target avatar, not the source mannequin.
	var leg_scale := maxf(0.4, _rest_skeleton("LeftUpperLeg").distance_to(_rest_skeleton("LeftFoot")) / 0.85)
	var cycle_distance := lerpf(1.35, 2.35, jog_weight) * leg_scale
	var playback_direction := -1.0 if forward_weight < -0.1 else 1.0
	_stride_phase = fposmod(_stride_phase + playback_direction * minf(speed / cycle_distance, 3.0) * delta * TAU, TAU)
	var walk_rotations := _animation_bones.duplicate()
	if weight > 0.0:
		walk_rotations = _locomotion_pose(_walk_clip, forward_weight, side_weight)
	if jog_weight > 0.0:
		var jog_rotations := _locomotion_pose(_jog_clip, forward_weight, side_weight)
		for bone_name in walk_rotations:
			walk_rotations[bone_name] = (walk_rotations[bone_name] as Quaternion).slerp(jog_rotations[bone_name], jog_weight)
	_apply_idle_pose(walk_rotations, weight, 1.0, CONTROLLED_BONES)
	skeleton.force_update_all_bone_transforms()
	for side in ["left", "right"]:
		if not _desktop_target.has(side) or not hand_target.has(side):
			continue
		var idle_target := _idle_hand_target(side)
		var walk_target := _locomotion_hand_target(side, _walk_clip, forward_weight, side_weight)
		if jog_weight > 0.0:
			walk_target = walk_target.lerp(_locomotion_hand_target(side, _jog_clip, forward_weight, side_weight), jog_weight)
		var target := idle_target.origin.lerp(walk_target, weight)
		var upper := skeleton.find_bone("LeftUpperArm" if side == "left" else "RightUpperArm")
		if upper >= 0:
			var shoulder := _pose_global(upper).origin
			var reach := float(_arm_lengths.get(side, 0.0)) * DESKTOP_REACH
			target = shoulder + (target - shoulder).limit_length(reach)
		hand_target[side].transform = Transform3D(Basis.IDENTITY, target)


func _locomotion_pose(clip: RefCounted, forward_weight: float, side_weight: float) -> Dictionary:
	var rotations := {}
	for bone_name in _animation_bones:
		rotations[bone_name] = _animation_bones[bone_name]
	_reset_animation_pose()
	if clip != null:
		_apply_clip_motion(rotations, CONTROLLED_BONES, clip, _stride_phase / TAU * float(clip.duration), forward_weight, side_weight)
	return rotations


func _locomotion_hand_target(side: String, clip: RefCounted, forward_weight: float, side_weight: float) -> Vector3:
	var upper := skeleton.find_bone("LeftUpperArm" if side == "left" else "RightUpperArm")
	if clip == null or upper < 0 or not clip.has_wrist(side):
		return (_desktop_target[side] as Transform3D).origin
	var offset: Vector3 = clip.sample_wrist(side, _stride_phase / TAU * float(clip.duration))
	offset = Vector3(offset.x + offset.z * side_weight, offset.y, offset.z * absf(forward_weight))
	return _pose_global(upper).origin + _source_basis * offset * float(_arm_lengths.get(side, 0.0))


## Restrained standing motion for an untracked VR body without a known pose.
## Head, neck, arms and hands are never touched here.
func _animate_vr_idle(delta: float) -> void:
	if delta <= 0.0 or skeleton == null:
		return
	_idle_time += delta
	_idle_clip_time += delta
	var rest_rotations := {}
	for bone_name in VR_IDLE_BONES:
		if _animation_bones.has(bone_name):
			rest_rotations[bone_name] = _animation_bones[bone_name]
	_apply_idle_pose(rest_rotations, 0.0, VR_IDLE_SCALE, VR_IDLE_BONES)
	skeleton.force_update_all_bone_transforms()


func _apply_idle_pose(walk_rotations: Dictionary, walk_weight: float, idle_scale: float, active_bones: Array) -> void:
	if skeleton == null:
		return
	# Start from rest so clip aim sees a clean parent chain.
	for bone_name in active_bones:
		if not _animation_bones.has(bone_name):
			continue
		var index := skeleton.find_bone(bone_name)
		if index >= 0:
			skeleton.set_bone_pose_rotation(index, _animation_bones[bone_name])
	var idle_rotations := {}
	for bone_name in active_bones:
		if _animation_bones.has(bone_name):
			idle_rotations[bone_name] = _animation_bones[bone_name]
	if _idle_clip != null:
		_apply_clip_motion(idle_rotations, active_bones)
	else:
		_apply_procedural_idle(idle_rotations, active_bones)
	_apply_idle_overlay(idle_rotations, active_bones, idle_scale)
	for bone_name in active_bones:
		if not _animation_bones.has(bone_name):
			continue
		var index := skeleton.find_bone(bone_name)
		if index < 0:
			continue
		var rest: Quaternion = _animation_bones[bone_name]
		var idle: Quaternion = idle_rotations.get(bone_name, rest)
		if idle_scale < 1.0:
			idle = rest.slerp(idle, idle_scale)
		var walk: Quaternion = walk_rotations.get(bone_name, rest)
		skeleton.set_bone_pose_rotation(index, idle.slerp(walk, walk_weight))


## Map source direction changes onto this VRM while preserving bone roll.
## Idle references its mean; locomotion references the source rest directions.
func _apply_clip_motion(idle_rotations: Dictionary, active_bones: Array, clip: RefCounted = null, sample_time := -1.0, forward_weight := 1.0, side_weight := 0.0) -> void:
	if clip == null:
		clip = _idle_clip
		sample_time = _idle_clip_time
	var basis := _source_basis
	var inverse := basis.inverse()
	for entry in _clip_targets:
		var bone_name: String = entry["bone_name"]
		if not active_bones.has(bone_name):
			continue
		var track: StringName = entry["track"]
		if not clip.has_track(track):
			continue
		var mean: Vector3 = clip.reference_direction(track)
		var direction: Vector3 = clip.sample_direction(track, sample_time)
		if clip != _idle_clip and bone_name.ends_with("UpperLeg"):
			# Redirect the thigh swing for strafing while preserving the authored
			# knee bend. Backpedaling plays the loop backwards, without turning
			# the knee joint or the character away from the camera heading.
			var swing_z := direction.z - mean.z
			direction = Vector3(direction.x + swing_z * side_weight, direction.y, mean.z + swing_z * absf(forward_weight)).normalized()
		var motion := _rotation_from_to(mean, direction)
		var global_motion := (basis * Basis(motion) * inverse).get_rotation_quaternion()
		var rest_direction := _rest_direction(entry["bone"], entry["child"])
		var desired := global_motion * rest_direction
		_aim_bone(entry["bone"], entry["child"], desired)
		idle_rotations[bone_name] = skeleton.get_bone_pose_rotation(entry["bone"])


## Layered fallback for a missing/corrupt clip and for incomplete rigs. It uses
## incommensurate periods so standing avatars do not breathe in lockstep.
func _apply_procedural_idle(idle_rotations: Dictionary, active_bones: Array) -> void:
	var up := _source_basis.y
	var left := _source_basis.x
	var forward := _source_basis.z
	var shift := sin(_idle_time * 0.41 + _idle_phase)
	var breath := sin(_idle_time * 1.55 + _idle_phase * 0.37)
	var slow := sin(_idle_time * 0.19 + _idle_phase * 1.3)
	if idle_rotations.has("Hips"):
		idle_rotations["Hips"] = _rotate_pose("Hips", idle_rotations["Hips"], forward, shift * 0.010)
	if idle_rotations.has("Spine"):
		var spine: Quaternion = _rotate_pose("Spine", idle_rotations["Spine"], left, shift * 0.015)
		idle_rotations["Spine"] = _rotate_pose("Spine", spine, up, slow * 0.006)
	if idle_rotations.has("Chest"):
		var chest: Quaternion = _rotate_pose("Chest", idle_rotations["Chest"], left, -shift * 0.010)
		idle_rotations["Chest"] = _rotate_pose("Chest", chest, up, breath * 0.004)
	if idle_rotations.has("UpperChest"):
		idle_rotations["UpperChest"] = _rotate_pose("UpperChest", idle_rotations["UpperChest"], left, shift * 0.007)
	for side in ["Left", "Right"]:
		var side_sign := 1.0 if side == "Left" else -1.0
		var upper_name: String = side + "UpperLeg"
		var lower_name: String = side + "LowerLeg"
		var foot_name: String = side + "Foot"
		if idle_rotations.has(upper_name):
			idle_rotations[upper_name] = _rotate_pose(upper_name, idle_rotations[upper_name], left, shift * 0.006 * side_sign)
		if idle_rotations.has(lower_name):
			idle_rotations[lower_name] = _rotate_pose(lower_name, idle_rotations[lower_name], left, 0.010 + maxf(0.0, shift) * 0.008)
		if idle_rotations.has(foot_name):
			idle_rotations[foot_name] = _rotate_pose(foot_name, idle_rotations[foot_name], left, -0.006)


## A slow second layer keeps the 2.5 s clip from reading as a mechanical loop.
func _apply_idle_overlay(idle_rotations: Dictionary, active_bones: Array, idle_scale: float) -> void:
	var up := _source_basis.y
	var left := _source_basis.x
	var sway := sin(_idle_time * 0.29 + _idle_phase) * 0.008 * idle_scale
	var breathe := sin(_idle_time * 1.55 + _idle_phase * 0.7) * 0.005 * idle_scale
	if active_bones.has("Spine") and idle_rotations.has("Spine"):
		var spine: Quaternion = _rotate_pose("Spine", idle_rotations["Spine"], left, sway)
		idle_rotations["Spine"] = _rotate_pose("Spine", spine, up, breathe * 0.5)
	if active_bones.has("Chest") and idle_rotations.has("Chest"):
		idle_rotations["Chest"] = _rotate_pose("Chest", idle_rotations["Chest"], left, -sway * 0.6)


func _idle_hand_target(side: String) -> Transform3D:
	var prefix := "Left" if side == "left" else "Right"
	var upper := skeleton.find_bone(prefix + "UpperArm")
	var hand := skeleton.find_bone(prefix + "Hand")
	var swing := sin(_idle_time * 0.29 + _idle_phase + (0.0 if side == "left" else 1.9))
	var breath := sin(_idle_time * 1.55 + _idle_phase * 0.7)
	if _idle_clip != null and upper >= 0 and hand >= 0 and _idle_clip.has_wrist(side):
		var origin := _pose_global(upper).origin
		var offset: Vector3 = _idle_clip.sample_wrist(side, _idle_clip_time) * float(_arm_lengths.get(side, 0.0))
		var target := Transform3D(Basis.IDENTITY, origin + _source_basis * offset)
		target.origin += _source_basis.z * (swing * 0.012) + _source_basis.y * (breath * 0.006)
		# Like the desktop rest target, stay short of full stretch so the elbow
		# keeps a bend and the IK does not snap to a straight arm.
		var reach := float(_arm_lengths.get(side, 0.0)) * DESKTOP_REACH
		var from_shoulder := target.origin - origin
		if reach > 0.0 and from_shoulder.length() > reach:
			target.origin = origin + from_shoulder.normalized() * reach
		return target
	var fallback: Transform3D = _desktop_target.get(side, Transform3D.IDENTITY)
	fallback.origin += _source_basis.z * (swing * 0.015) + _source_basis.y * (breath * 0.008)
	return fallback


# Body placement


func _update_body_pose() -> void:
	if avatar_model == null or skeleton == null or head_anchor == null or _space == null:
		return
	var anchor := _space.global_transform.affine_inverse() * head_anchor.global_transform
	if _head_bone >= 0:
		skeleton.set_bone_pose_position(_head_bone, _head_pose_position)
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
	# Keep the eyes pinned to the camera even as the torso breathes or turns.
	if _head_bone >= 0:
		var eyes := skeleton.transform * (skeleton.get_bone_global_pose(_head_bone) * _eye_offset)
		avatar_model.position = anchor.origin - basis * eyes
		if vr_mode:
			# Keep the chest behind the eyes instead of putting the viewpoint
			# inside the torso when looking down. Counter-shift only the head,
			# preserving the tracked eye position and the world-space hand goals.
			var back := Basis(Vector3.UP, _last_yaw).z * VR_BODY_BACK_OFFSET
			avatar_model.position += back
			var head_pose := skeleton.get_bone_global_pose(_head_bone)
			head_pose.origin -= (avatar_model.basis * skeleton.basis).inverse() * back
			skeleton.set_bone_global_pose(_head_bone, head_pose)


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
