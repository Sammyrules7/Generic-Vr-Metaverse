@tool
class_name PlanarMirror
extends Node3D
## Drop-in planar mirror: instance this scene and place it in the world.
##
## MirrorGlass renders the view from the player camera reflected across the
## glass plane into an off-axis viewport fitted to the glass. XR gets one
## reflection per eye; mesh UVs stay stable when the headset turns.
##
## The glass must stay single-sided (cull_back): the reflected camera sits
## behind the mirror, so the glass back face is never drawn into its own view.
##
## In the editor the mirror follows the main 3D view camera and renders through
## an internal, unsaved SubViewport. The scene's own SubViewport is left alone so
## saving the scene never serializes an editor World3D override.

## Cap the reflection pass; the aspect ratio follows the glass. XR is capped
## at 1024 per eye because stereo requires two scene renders.
@export var max_viewport_size := Vector2i(1920, 1920):
	set(value):
		max_viewport_size = Vector2i(maxi(1, value.x), maxi(1, value.y))
		if is_node_ready():
			_resize_viewport()

@onready var mirror_glass: MeshInstance3D = $MirrorGlass
@onready var sub_viewport: SubViewport = $MirrorGlass/SubViewport
@onready var reflect_camera: Camera3D = $MirrorGlass/SubViewport/ReflectCamera

var _right_viewport: SubViewport
var _right_camera: Camera3D
var _runtime_material: ShaderMaterial
var _stereo := false
var _source_camera: Camera3D
var _viewport_size := Vector2i.ZERO
var _preview_viewport: SubViewport
var _preview_camera: Camera3D
var _preview_material: ShaderMaterial


func _ready() -> void:
	var source_material := mirror_glass.get_active_material(0) as ShaderMaterial
	if source_material == null:
		push_error("MirrorGlass needs a ShaderMaterial with a viewport_texture uniform")
		if not Engine.is_editor_hint():
			sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		set_process(false)
		return
	if Engine.is_editor_hint():
		_setup_editor_preview(source_material)
	else:
		_setup_runtime(source_material)
	var viewport := _view_viewport()
	if viewport != null:
		viewport.size_changed.connect(_resize_viewport)
	_resize_viewport()


func _exit_tree() -> void:
	if Engine.is_editor_hint() and _preview_material != null:
		_preview_material.set_shader_parameter("viewport_texture", null)


func _setup_runtime(source_material: ShaderMaterial) -> void:
	# Each mirror owns its viewport texture; sharing planar_mirror.tres between
	# two loaded worlds would make them fight over the same reflection.
	var material := source_material.duplicate() as ShaderMaterial
	mirror_glass.material_override = material
	_runtime_material = material
	material.set_shader_parameter("viewport_texture", sub_viewport.get_texture())
	# A SubViewport nested under MeshInstance3D does not inherit the world on its
	# own, so share it explicitly or the reflection renders an empty scene.
	sub_viewport.world_3d = get_world_3d()


func _setup_editor_preview(source_material: ShaderMaterial) -> void:
	# Touching the scene's SubViewport in the editor would mark it dirty and save
	# a World3D override into the scene. An internal viewport is never serialized.
	_preview_material = source_material
	_preview_viewport = SubViewport.new()
	_preview_viewport.name = "EditorMirrorViewport"
	add_child(_preview_viewport, false, Node.INTERNAL_MODE_FRONT)
	_preview_viewport.world_3d = get_world_3d()
	_preview_camera = Camera3D.new()
	_preview_camera.name = "EditorMirrorCamera"
	_preview_camera.current = true
	_preview_viewport.add_child(_preview_camera, false, Node.INTERNAL_MODE_FRONT)
	_preview_material.set_shader_parameter("viewport_texture", _preview_viewport.get_texture())


func _process(_delta: float) -> void:
	var target_viewport := _target_viewport()
	if target_viewport == null:
		return
	if _viewport_size == Vector2i.ZERO or Engine.is_editor_hint():
		_resize_viewport()
	var source := _view_camera()
	var interface := XRServer.primary_interface
	var stereo := not Engine.is_editor_hint() and source is XRCamera3D and get_viewport().use_xr and interface != null and interface.is_initialized() and interface.get_view_count() >= 2
	if stereo != _stereo:
		_stereo = stereo
		if stereo:
			_ensure_right_view()
		if _runtime_material != null:
			_runtime_material.set_shader_parameter("stereo", stereo)
		_resize_viewport()
	if source == null:
		_set_updates(false)
		return
	_source_camera = source
	var glass := mirror_glass.global_transform
	var normal := glass.basis.y.normalized()
	var eye := source.get_camera_transform().origin
	var right_eye := eye
	var active := _is_front_side(eye, glass.origin, normal)
	if stereo:
		# XRInterface expects the origin transform, not the already-tracked head.
		var origin := (source.get_parent() as Node3D).global_transform
		var left_view := interface.get_transform_for_view(0, origin)
		var right_view := interface.get_transform_for_view(1, origin)
		eye = left_view.origin
		right_eye = right_view.origin
		var left_projection := interface.get_projection_for_view(0, 1.0, source.near, source.far)
		var right_projection := interface.get_projection_for_view(1, 1.0, source.near, source.far)
		active = active and (_bounds_in_planes(_projection_planes(left_projection, left_view), glass) or _bounds_in_planes(_projection_planes(right_projection, right_view), glass))
	else:
		active = active and _is_in_view(source, glass)
	_set_updates(active)
	if not active:
		return
	if stereo:
		_fit_reflection(_right_camera, right_eye, source.far)
	_fit_reflection(_target_camera(), eye, source.far)


func _ensure_right_view() -> void:
	if _right_viewport != null:
		return
	_right_viewport = SubViewport.new()
	_right_viewport.name = "RightEyeReflection"
	_right_viewport.world_3d = get_world_3d()
	add_child(_right_viewport, false, Node.INTERNAL_MODE_FRONT)
	_right_camera = Camera3D.new()
	_right_camera.current = true
	AvatarView.configure_mirror_camera(_right_camera)
	_right_viewport.add_child(_right_camera)
	_runtime_material.set_shader_parameter("right_eye_texture", _right_viewport.get_texture())


func _set_updates(active: bool) -> void:
	_target_viewport().render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if _right_viewport != null:
		_right_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active and _stereo else SubViewport.UPDATE_DISABLED


func _fit_reflection(camera: Camera3D, eye: Vector3, far_distance: float) -> void:
	var glass := mirror_glass.global_transform
	var bounds := mirror_glass.get_aabb()
	var center := glass * bounds.get_center()
	var right := glass.basis.x.normalized()
	var up := glass.basis.z.normalized()
	var normal := glass.basis.y.normalized()
	var reflected_eye := _reflect_point(eye, center, normal)
	# A proper-handed camera, fixed to the glass, avoids the negative camera
	# determinant and head-rotation-dependent SCREEN_UV mapping of the old path.
	camera.global_transform = Transform3D(Basis(right, up, -normal), reflected_eye)
	var depth := maxf(0.01, (center - reflected_eye).dot(normal))
	var offset := Vector2((center - reflected_eye).dot(right), (center - reflected_eye).dot(up))
	var height := bounds.size.z * glass.basis.z.length()
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	camera.set_frustum(height, offset, depth, maxf(depth + 1.0, far_distance + depth))


## Mirror a camera pose across the plane. Reflecting the full basis keeps a
## mathematical reflection. Rendering uses proper-handed off-axis cameras.
static func reflected_transform(source: Transform3D, plane_origin: Vector3, plane_normal: Vector3) -> Transform3D:
	var reflected_basis := Basis(
		_reflect_direction(source.basis.x, plane_normal),
		_reflect_direction(source.basis.y, plane_normal),
		_reflect_direction(source.basis.z, plane_normal)
	)
	return Transform3D(reflected_basis, _reflect_point(source.origin, plane_origin, plane_normal))


static func _reflect_direction(direction: Vector3, plane_normal: Vector3) -> Vector3:
	return direction - 2.0 * plane_normal * direction.dot(plane_normal)


static func _reflect_point(point: Vector3, plane_origin: Vector3, plane_normal: Vector3) -> Vector3:
	return point - 2.0 * plane_normal * (point - plane_origin).dot(plane_normal)


static func _is_front_side(position: Vector3, plane_origin: Vector3, plane_normal: Vector3) -> bool:
	return (position - plane_origin).dot(plane_normal) > 0.0


func _is_in_view(source: Camera3D, glass: Transform3D) -> bool:
	return _bounds_in_planes(source.get_frustum(), glass)


static func _projection_planes(projection: Projection, pose: Transform3D) -> Array[Plane]:
	var planes: Array[Plane] = []
	for index in 6:
		planes.append(pose * projection.get_projection_plane(index))
	return planes


func _bounds_in_planes(planes: Array[Plane], glass: Transform3D) -> bool:
	# Test the glass as an oriented box against the camera frustum. Sampling the
	# center and corners breaks down when the player puts their face up against
	# the glass: the mirror covers the screen while all nine sample points sit
	# outside the tiny close-up frustum, which used to freeze the last frame.
	var bounds := mirror_glass.get_aabb()
	var center := glass * bounds.get_center()
	var axis_x := glass.basis.x.normalized()
	var axis_y := glass.basis.y.normalized()
	var axis_z := glass.basis.z.normalized()
	var extent_x := bounds.size.x * glass.basis.x.length() * 0.5
	var extent_y := bounds.size.y * glass.basis.y.length() * 0.5
	var extent_z := bounds.size.z * glass.basis.z.length() * 0.5
	if planes.is_empty():
		return true
	for plane in planes:
		var radius := absf(plane.normal.dot(axis_x)) * extent_x
		radius += absf(plane.normal.dot(axis_y)) * extent_y
		radius += absf(plane.normal.dot(axis_z)) * extent_z
		# Camera frustum planes point out of the visible volume.
		if plane.distance_to(center) - radius > 0.0:
			return false
	return true


func _view_viewport() -> Viewport:
	if Engine.is_editor_hint():
		var editor := Engine.get_singleton("EditorInterface")
		if editor != null:
			return editor.call("get_editor_viewport_3d", 0) as Viewport
		return null
	return get_viewport()


func _view_camera() -> Camera3D:
	var viewport := _view_viewport()
	return viewport.get_camera_3d() if viewport != null else null


func _target_viewport() -> SubViewport:
	return _preview_viewport if Engine.is_editor_hint() else sub_viewport


func _target_camera() -> Camera3D:
	return _preview_camera if Engine.is_editor_hint() else reflect_camera


func _resize_viewport() -> void:
	var viewport := _view_viewport()
	if viewport == null:
		return
	var size := viewport.get_visible_rect().size
	if size.x < 1.0 or size.y < 1.0:
		return
	# Fit the glass aspect rather than the desktop/XR framebuffer aspect.
	var bounds := mirror_glass.get_aabb()
	var glass := mirror_glass.global_transform
	var aspect := maxf(0.01, bounds.size.x * glass.basis.x.length()) / maxf(0.01, bounds.size.z * glass.basis.z.length())
	var cap := max_viewport_size
	if _stereo:
		cap = Vector2i(mini(cap.x, 1024), mini(cap.y, 1024))
	var width := minf(cap.x, size.x)
	var height := width / aspect
	if height > minf(cap.y, size.y):
		height = minf(cap.y, size.y)
		width = height * aspect
	var target := Vector2i(maxi(1, roundi(width)), maxi(1, roundi(height)))
	_viewport_size = target
	var target_viewport := _target_viewport()
	if target_viewport != null:
		target_viewport.size = target
	if _right_viewport != null:
		_right_viewport.size = target
