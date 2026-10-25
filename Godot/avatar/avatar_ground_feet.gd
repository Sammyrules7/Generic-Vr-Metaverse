class_name AvatarGroundFeet
extends Node3D
## Ground-aware foot placement for AvatarRigDriver.
##
## The helper owns two responsibilities that are deliberately separate from the
## driver's head/arm pose:
##   1. Probe the physics world for the ground under each ankle. Queries only run
##      from _physics_process, because Godot's direct space state is valid only
##      during a physics tick.
##   2. Drive native TwoBoneIK3D leg modifiers with an ankle target and orient the
##      foot after the leg solve so its sole follows the ground normal.
##
## The ankle is not placed on the floor. The sole offset is read from the rest
## pose (mesh bounds when available, otherwise the foot/toe proportions), so the
## foot bone stays above the surface by the height of the shoe/foot.
##
## No avatar translation happens here. The driver keeps the eye anchor and body
## placement authoritative; this helper only rotates the leg chain and the foot.
## When no ground is found, when a leg bone is missing, or when a future lower
## body tracker owns the legs, every modifier is left inactive and the animation
## pose passes through unchanged.

const SIDES := ["left", "right"]
const LEG_BONES := {
	"left": ["LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes"],
	"right": ["RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes"],
}
## World layer 1 is the ordinary collision/ground layer in this project.
const DEFAULT_GROUND_MASK := 1
## Animation lift above the rest ankle permitted when entering stance.
const PLANT_HEIGHT := 0.02
## Animation lift above the rest ankle that releases an existing stance.
const RELEASE_HEIGHT := 0.07
## Keep a little bend in the knee even at the end of the leg's reach.
const REACH_MARGIN := 0.995
const MOVE_LOCK_SPEED := 0.35
const MAX_PLANT_DRIFT := 0.25
const MIN_SOLE := 0.015
const MAX_SOLE := 0.12
const MESH_SOLE_MIN := 0.005
const MESH_SOLE_MAX := 0.25

## Copies the ankle target's orientation to the foot after the native leg IK.
## TwoBoneIK3D only solves the end position; this keeps the sole on the slope.
class FootOrientationModifier:
	extends SkeletonModifier3D
	var targets := {}
	var bones := {}
	var grounded := {}

	func _process_modification() -> void:
		var skeleton := get_skeleton()
		if skeleton == null:
			return
		var inverse := skeleton.global_transform.affine_inverse()
		for side in targets:
			if not grounded.get(side, false):
				continue
			var target := targets[side] as Node3D
			var bone := int(bones.get(side, -1))
			if is_instance_valid(target) and bone >= 0:
				var pose := skeleton.get_bone_global_pose(bone)
				pose.basis = (inverse * target.global_transform).basis
				skeleton.set_bone_global_pose(bone, pose)


var skeleton: Skeleton3D
var avatar_model: Node3D
## Physics layers treated as ground. The project's world geometry is layer 1.
var ground_mask := DEFAULT_GROUND_MASK
var enabled := true
## A future full-body provider can claim the legs. Ground IK then stays out.
var lower_body_tracked := false
## Distance from the ankle to the sole, in skeleton units, per side.
var sole_offset := {}
## Native IK nodes and their proxy targets, keyed by "left" and "right".
var leg_ik := {}
var foot_target := {}
var foot_pole := {}
## Latest physics-tick ray result per side; empty when there is no ground.
var ground_hit := {}
## Whether each foot currently has a valid ground target.
var grounded := {}
## Set when the ground target is outside the leg's reach. The camera and body
## stay untouched; the foot simply cannot close the remaining gap.
var reach_limited := {}
## Distance between the clamped ankle target and the ground target, in world
## units. Zero when the sole can reach the surface.
var target_gap := {}

var _foot_modifier: FootOrientationModifier
var _upper := {}
var _lower := {}
var _foot := {}
var _thigh := {}
var _shin := {}
var _foot_up_local := {}
var _foot_forward := {}
var _ankle_world := {}
var _plant_ankle := {}
var _exclude: Array[RID] = []
var _owner_body: CharacterBody3D
var _configured := false
var _last_body_position := Vector3.ZERO
var _have_body_position := false
var _body_speed := 0.0
var _plant_locked := false
var _axes := Basis.IDENTITY
var _probe_up := 0.5
var _probe_down := 1.2


func _ready() -> void:
	set_physics_process(true)


func configure(model: Node3D, humanoid: Skeleton3D, axes: Basis) -> void:
	clear()
	avatar_model = model
	skeleton = humanoid
	if avatar_model == null or skeleton == null:
		return
	if not avatar_model.is_inside_tree() or not skeleton.is_inside_tree():
		return
	_axes = axes
	_read_rest_geometry()
	_build_leg_ik()
	_collect_exclude_rids()
	_configured = true
	set_physics_process(true)


## Drop every proxy node and cached state. Safe to call more than once.
func clear() -> void:
	_deactivate_all()
	if is_instance_valid(_foot_modifier):
		_free_rig_node(_foot_modifier)
	_foot_modifier = null
	for side in leg_ik:
		var ik: Node = leg_ik[side]
		if is_instance_valid(ik):
			_free_rig_node(ik)
	for side in foot_target:
		var target: Node = foot_target[side]
		if is_instance_valid(target):
			_free_rig_node(target)
	for side in foot_pole:
		var pole: Node = foot_pole[side]
		if is_instance_valid(pole):
			_free_rig_node(pole)
	leg_ik.clear()
	foot_target.clear()
	foot_pole.clear()
	ground_hit.clear()
	grounded.clear()
	reach_limited.clear()
	target_gap.clear()
	sole_offset.clear()
	_upper.clear()
	_lower.clear()
	_foot.clear()
	_thigh.clear()
	_shin.clear()
	_foot_up_local.clear()
	_foot_forward.clear()
	_ankle_world.clear()
	_plant_ankle.clear()
	_exclude.clear()
	_owner_body = null
	_have_body_position = false
	_body_speed = 0.0
	_plant_locked = false
	_configured = false
	skeleton = null
	avatar_model = null


## Forget foot locks after a teleport, respawn or control-mode change.
func reset() -> void:
	_deactivate_all()
	ground_hit.clear()
	grounded.clear()
	reach_limited.clear()
	target_gap.clear()
	_ankle_world.clear()
	_plant_ankle.clear()
	_have_body_position = false
	_body_speed = 0.0
	_plant_locked = false


func _exit_tree() -> void:
	clear()


# Rest geometry


func _read_rest_geometry() -> void:
	var up := _axes.y
	var fallback_forward := _axes.z
	var mesh_lowest := _mesh_lowest(up)
	for side in SIDES:
		var names: Array = LEG_BONES[side]
		var upper := skeleton.find_bone(names[0])
		var lower := skeleton.find_bone(names[1])
		var foot := skeleton.find_bone(names[2])
		if upper < 0 or lower < 0 or foot < 0:
			continue
		var upper_rest := skeleton.get_bone_global_rest(upper)
		var lower_rest := skeleton.get_bone_global_rest(lower)
		var foot_rest := skeleton.get_bone_global_rest(foot)
		var thigh := upper_rest.origin.distance_to(lower_rest.origin)
		var shin := lower_rest.origin.distance_to(foot_rest.origin)
		if thigh < 1e-5 or shin < 1e-5:
			continue
		var toes := skeleton.find_bone(names[3])
		var toes_rest := Transform3D.IDENTITY
		if toes >= 0:
			toes_rest = skeleton.get_bone_global_rest(toes)
		_upper[side] = upper
		_lower[side] = lower
		_foot[side] = foot
		_thigh[side] = thigh
		_shin[side] = shin
		var foot_length := 0.0
		var forward := fallback_forward
		if toes >= 0:
			var toe_direction := toes_rest.origin - foot_rest.origin
			foot_length = toe_direction.length()
			var flat := toe_direction - up * toe_direction.dot(up)
			if flat.length_squared() > 1e-8:
				forward = flat.normalized()
		_foot_forward[side] = forward
		var rest_basis := foot_rest.basis.orthonormalized()
		var up_local := rest_basis.inverse() * up
		if up_local.length_squared() < 1e-8:
			up_local = Vector3.UP
		_foot_up_local[side] = up_local.normalized()
		var sole := 0.0
		if mesh_lowest < INF:
			sole = foot_rest.origin.dot(up) - mesh_lowest
			if sole < MESH_SOLE_MIN or sole > MESH_SOLE_MAX:
				sole = 0.0
		if sole <= 0.0:
			# No usable mesh bounds (or a procedurally built fixture): keep the
			# ankle off the floor using the authored foot length.
			sole = clampf(0.35 * maxf(foot_length, 0.04), MIN_SOLE, MAX_SOLE)
		sole_offset[side] = sole
		grounded[side] = false
		reach_limited[side] = false
		target_gap[side] = 0.0


## Lowest mesh point projected onto the skeleton's up axis. Skinned meshes keep
## their bind-pose AABB, which is the best available shoe/floor estimate.
func _mesh_lowest(up: Vector3) -> float:
	var lowest := INF
	if avatar_model == null:
		return lowest
	for node in avatar_model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var to_skeleton := skeleton.global_transform.affine_inverse() * mesh.global_transform
		var box := mesh.get_aabb()
		for corner in 8:
			var point := to_skeleton * box.get_endpoint(corner)
			lowest = minf(lowest, point.dot(up))
	return lowest


# IK setup


func _build_leg_ik() -> void:
	for side in SIDES:
		if not _upper.has(side):
			continue
		var suffix := "Left" if side == "left" else "Right"
		var target := Node3D.new()
		target.name = "AvatarGroundFootTarget" + suffix
		target.physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_OFF
		skeleton.add_child(target)
		var pole := Node3D.new()
		pole.name = "AvatarGroundFootPole" + suffix
		pole.physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_OFF
		skeleton.add_child(pole)
		var ik := TwoBoneIK3D.new()
		ik.name = "AvatarGroundLegIK" + suffix
		skeleton.add_child(ik)
		ik.set_setting_count(1)
		ik.set_root_bone_name(0, skeleton.get_bone_name(_upper[side]))
		ik.set_middle_bone_name(0, skeleton.get_bone_name(_lower[side]))
		ik.set_end_bone_name(0, skeleton.get_bone_name(_foot[side]))
		ik.set_target_node(0, NodePath("../" + target.name))
		ik.set_pole_node(0, NodePath("../" + pole.name))
		ik.set_pole_direction(0, SkeletonModifier3D.SECONDARY_DIRECTION_NONE)
		ik.active = false
		foot_target[side] = target
		foot_pole[side] = pole
		leg_ik[side] = ik
		grounded[side] = false
	if leg_ik.is_empty():
		return
	_foot_modifier = FootOrientationModifier.new()
	_foot_modifier.name = "AvatarGroundFootOrientation"
	skeleton.add_child(_foot_modifier)
	_foot_modifier.targets = foot_target
	_foot_modifier.grounded = grounded
	for side in _foot:
		_foot_modifier.bones[side] = _foot[side]
	# Native modifiers run in child order. Legs have to solve before the arms,
	# the wrist copy and the spring bones that were installed later.
	for side in leg_ik:
		skeleton.move_child(leg_ik[side], 0)


func _collect_exclude_rids() -> void:
	_exclude.clear()
	var node: Node = avatar_model
	while node != null:
		if node is CharacterBody3D:
			_owner_body = node as CharacterBody3D
			_exclude.append(_owner_body.get_rid())
		node = node.get_parent()
	for child in avatar_model.find_children("*", "CollisionObject3D", true, false):
		_exclude.append((child as CollisionObject3D).get_rid())


func _free_rig_node(node: Node) -> void:
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.free()


# Physics probing


func _physics_process(_delta: float) -> void:
	if not _configured or not enabled or lower_body_tracked:
		return
	if not is_inside_tree() or _ankle_world.is_empty():
		return
	var world := get_world_3d()
	if world == null:
		return
	var space := world.direct_space_state
	if space == null:
		return
	for side in _ankle_world:
		if not leg_ik.has(side):
			continue
		var ankle: Vector3 = _ankle_world[side]
		var from := ankle + Vector3.UP * _probe_up
		var to := ankle - Vector3.UP * _probe_down
		# The unbent animation ankle can be underground when the head lowers.
		# Start above the locomotion floor, not below it with the ankle.
		var body_root := avatar_model.get_parent() as Node3D
		if body_root != null:
			from.y = maxf(from.y, body_root.global_position.y + _probe_up)
			to.y = minf(to.y, body_root.global_position.y - _probe_down)
		var query := PhysicsRayQueryParameters3D.create(from, to, ground_mask, _exclude)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.hit_from_inside = false
		ground_hit[side] = space.intersect_ray(query)


# Pose solve


## Called by the driver after body placement. Uses the ray results cached during
## the previous physics tick; it never queries the physics space itself.
func solve(delta: float) -> void:
	if not _configured or skeleton == null or avatar_model == null:
		return
	if not enabled or lower_body_tracked:
		_deactivate_all()
		return
	_update_motion(delta)
	var scale := _world_scale()
	var lock := _body_speed < MOVE_LOCK_SPEED
	var was_locked := _plant_locked
	_plant_locked = lock
	for side in SIDES:
		if not leg_ik.has(side):
			continue
		_solve_side(side, scale, lock, was_locked)


func _solve_side(side: String, scale: float, lock: bool, was_locked: bool) -> void:
	var upper: int = _upper[side]
	var lower: int = _lower[side]
	var foot: int = _foot[side]
	var hip_skeleton := skeleton.get_bone_global_pose(upper).origin
	var foot_pose := skeleton.get_bone_global_pose(foot)
	var ankle_world := skeleton.global_transform * foot_pose.origin
	_ankle_world[side] = ankle_world
	var leg_world: float = (_thigh[side] + _shin[side]) * scale
	_probe_up = maxf(0.35, leg_world * 0.35)
	_probe_down = maxf(1.5, leg_world * 1.5)
	var hit: Dictionary = ground_hit.get(side, {})
	if hit.is_empty():
		_deactivate(side)
		return
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	normal = normal.normalized()
	if normal.length_squared() < 1e-8:
		normal = Vector3.UP
	if normal.dot(Vector3.UP) < 0.6:
		_deactivate(side)
		return
	var ground: Vector3 = hit.get("position", Vector3.ZERO)
	# The body root represents the locomotion floor. Do not pin feet to the
	# ground while the body is jumping/falling; remote bodies use this same
	# geometric check without depending on locally simulated is_on_floor().
	var body_root := avatar_model.get_parent() as Node3D
	if body_root != null:
		var root_height := (body_root.global_position - ground).dot(normal)
		if root_height > 0.12 * scale or root_height < -0.4 * scale:
			_deactivate(side)
			return
	if is_instance_valid(_owner_body) and _owner_body.velocity.y > 0.2:
		_deactivate(side)
		return
	var sole_world := float(sole_offset.get(side, 0.0)) * scale
	var desired := ground + normal * sole_world
	# An avatar's neutral ankle can sit above the floor because proportions
	# differ. Detect animation lift relative to that rest ankle, not the floor.
	var rest_ankle := skeleton.global_transform * skeleton.get_bone_global_rest(foot).origin
	var lift := maxf(0.0, (ankle_world - rest_ankle).dot(Vector3.UP))
	if lift > (RELEASE_HEIGHT if grounded.get(side, false) else PLANT_HEIGHT) * scale:
		grounded[side] = false
	elif not grounded.get(side, false):
		grounded[side] = true
		_plant_ankle[side] = desired
	if not grounded.get(side, false):
		_deactivate(side)
		return
	if lock:
		if not was_locked or not _plant_ankle.has(side):
			_plant_ankle[side] = desired
		var offset: Vector3 = ankle_world - _plant_ankle[side]
		var drift := Vector2(offset.x, offset.z).length()
		if drift > MAX_PLANT_DRIFT * scale:
			_plant_ankle[side] = desired
		desired = _plant_ankle[side]
		# Follow changes in surface height while keeping the planted X/Z.
		desired -= normal * ((desired - ground).dot(normal) - sole_world)
		_plant_ankle[side] = desired
	else:
		_plant_ankle[side] = desired
	var hip_world := skeleton.global_transform * hip_skeleton
	var ground_target := desired
	desired = _clamp_reach(hip_world, desired, side, scale)
	reach_limited[side] = not desired.is_equal_approx(ground_target)
	target_gap[side] = desired.distance_to(ground_target)
	var target_skeleton := skeleton.global_transform.affine_inverse() * desired
	var foot_basis := _foot_basis(side, normal, foot)
	foot_target[side].transform = Transform3D(foot_basis, target_skeleton)
	var knee_skeleton := skeleton.get_bone_global_pose(lower).origin
	var forward: Vector3 = _foot_forward.get(side, Vector3.FORWARD)
	var pole_skeleton := knee_skeleton + forward * maxf(_thigh[side] * 0.6, 0.05)
	foot_pole[side].transform = Transform3D(Basis.IDENTITY, pole_skeleton)
	leg_ik[side].active = true
	grounded[side] = true


func _deactivate(side: String) -> void:
	grounded[side] = false
	reach_limited[side] = false
	target_gap[side] = 0.0
	if leg_ik.has(side):
		leg_ik[side].active = false
	if _foot_modifier != null:
		_foot_modifier.grounded[side] = false


func _deactivate_all() -> void:
	for side in leg_ik:
		_deactivate(side)


func _update_motion(delta: float) -> void:
	if delta <= 0.0:
		return
	var body_root := avatar_model.get_parent() as Node3D
	var position_now := body_root.global_position if body_root != null else avatar_model.global_position
	if not _have_body_position:
		_last_body_position = position_now
		_have_body_position = true
		return
	var displacement := position_now - _last_body_position
	var speed := Vector2(displacement.x, displacement.z).length() / delta
	_last_body_position = position_now
	# A teleport is not locomotion; drop the smoothed speed instead of locking
	# the feet to the old position.
	if speed > 20.0:
		speed = 0.0
		ground_hit.clear()
		_plant_ankle.clear()
		_deactivate_all()
	_body_speed = lerpf(_body_speed, speed, 1.0 - exp(-10.0 * delta))


func _clamp_reach(hip: Vector3, target: Vector3, side: String, scale: float) -> Vector3:
	var offset := target - hip
	var distance := offset.length()
	if distance < 1e-6:
		return target
	var max_reach: float = (float(_thigh[side]) + float(_shin[side])) * scale * REACH_MARGIN
	var min_reach: float = absf(float(_thigh[side]) - float(_shin[side])) * scale + 0.001
	var clamped := clampf(distance, min_reach, max_reach)
	if is_equal_approx(clamped, distance):
		return target
	return hip + offset / distance * clamped


func _foot_basis(side: String, normal_world: Vector3, foot: int) -> Basis:
	var pose := skeleton.get_bone_global_pose(foot)
	var current := pose.basis.orthonormalized()
	var up_local: Vector3 = _foot_up_local.get(side, Vector3.UP)
	var current_up := (current * up_local).normalized()
	var normal_skeleton := (skeleton.global_basis.inverse() * normal_world).normalized()
	if normal_skeleton.length_squared() < 1e-8:
		normal_skeleton = Vector3.UP
	var swing := _rotation_from_to(current_up, normal_skeleton)
	return Basis((swing * current.get_rotation_quaternion()).normalized())


func _world_scale() -> float:
	if skeleton == null:
		return 1.0
	var scale := skeleton.global_basis.get_scale()
	var average := (absf(scale.x) + absf(scale.y) + absf(scale.z)) / 3.0
	return average if average > 1e-5 else 1.0


static func _rotation_from_to(from: Vector3, to: Vector3) -> Quaternion:
	var a := from.normalized()
	var b := to.normalized()
	var axis := a.cross(b)
	if axis.length_squared() < 1e-10:
		if a.dot(b) > 0.0:
			return Quaternion.IDENTITY
		var fallback := Vector3.UP if absf(a.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		return Quaternion(fallback.normalized(), PI)
	return Quaternion(axis.normalized(), a.angle_to(b))
