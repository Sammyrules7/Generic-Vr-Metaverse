class_name NeutralHandVisual
extends Node3D
## A neutral shell built from measured joints: no authored skin, handedness or
## wrist-axis assumptions. Three instanced batches, independent of joint count.
const SHADER := preload("res://player/neutral_hand.gdshader")
const FINGERS := [[2, 3, 4, 5], [6, 7, 8, 9, 10], [11, 12, 13, 14, 15], [16, 17, 18, 19, 20], [21, 22, 23, 24, 25]]
const TIPS := [5, 10, 15, 20, 25]
static var _overlay_shader: Shader
var joints: MultiMesh
var links: MultiMesh
var palm: MultiMesh
var material := ShaderMaterial.new()
var points := PackedVector3Array()

func _ready() -> void:
	material.shader = SHADER
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	cylinder.height = 1.0
	cylinder.radial_segments = 10
	joints = _batch(sphere, 25)
	links = _batch(cylinder, 24)
	palm = _batch(sphere, 1)
	points.resize(XRHandTracker.HAND_JOINT_MAX)

func _batch(mesh: Mesh, count: int) -> MultiMesh:
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_custom_data = true
	batch.mesh = mesh
	batch.instance_count = count
	batch.custom_aabb = AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = batch
	instance.material_override = material
	instance.layers = AvatarView.FIRST_PERSON
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(instance)
	return batch

func set_appearance(alpha: float, overlay: bool) -> void:
	if overlay and _overlay_shader == null:
		_overlay_shader = Shader.new()
		_overlay_shader.code = SHADER.code.replace("depth_draw_never;", "depth_draw_never, depth_test_disabled;")
	material.shader = _overlay_shader if overlay else SHADER
	material.set_shader_parameter("opacity", clampf(alpha, 0.0, 1.0))

func update_joints(tracker: XRHandTracker, palm_pose: Transform3D) -> void:
	var inverse := palm_pose.affine_inverse()
	for joint in points.size():
		points[joint] = inverse * tracker.get_hand_joint_transform(joint).origin
	for joint in range(1, points.size()):
		var radius := _radius(tracker, joint)
		joints.set_instance_transform(joint - 1, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * radius), points[joint]))
		joints.set_instance_custom_data(joint - 1, Color(1.0 if joint in TIPS else 0.0, 0, 0, 0))
	var index := 0
	for finger in FINGERS:
		for segment in range(finger.size() - 1):
			var start: int = finger[segment]
			var end: int = finger[segment + 1]
			_link(index, points[start], points[end], minf(_radius(tracker, start), _radius(tracker, end)), 0.7 if end in TIPS else 0.0)
			index += 1
		_link(index, points[1], points[finger[0]], _radius(tracker, finger[0]) * 0.8, 0.0)
		index += 1
	var across := points[7] - points[22]
	var forward := (points[7] + points[22]) * 0.5 - points[1]
	if across.length_squared() > 0.000001 and forward.length_squared() > 0.000001 and across.cross(forward).length_squared() > 0.00000001:
		var x := across.normalized()
		var y := x.cross(forward).normalized()
		var z := x.cross(y).normalized()
		var center := (points[7] + points[22] + points[1] * 2.0) * 0.25
		palm.set_instance_transform(0, Transform3D(Basis(x, y, z).scaled_local(Vector3(across.length() * 0.58, 0.012, forward.length() * 0.58)), center))
	else:
		palm.set_instance_transform(0, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.001), points[0]))

func _radius(tracker: XRHandTracker, joint: int) -> float:
	var radius := tracker.get_hand_joint_radius(joint)
	return clampf(radius if is_finite(radius) and radius > 0.0 else 0.007, 0.003, 0.014)

func _link(index: int, a: Vector3, b: Vector3, radius: float, tip: float) -> void:
	var direction := b - a
	var length := direction.length()
	var basis := Basis.IDENTITY
	if length > 0.00001:
		basis = Basis(Quaternion(Vector3.UP, direction / length))
	links.set_instance_transform(index, Transform3D(basis.scaled_local(Vector3(radius, maxf(length, 0.00001), radius)), (a + b) * 0.5))
	links.set_instance_custom_data(index, Color(tip, 0, 0, 0))
