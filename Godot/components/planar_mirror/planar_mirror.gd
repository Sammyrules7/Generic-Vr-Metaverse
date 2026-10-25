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
## behind the mirror. Layer 18 also excludes glass from reflection passes:
## face culling alone does not prevent WebGL framebuffer-feedback validation.
##
## In the editor the mirror follows the main 3D view camera and renders through
## an internal, unsaved SubViewport. The scene's own SubViewport is left alone so
## saving the scene never serializes an editor World3D override.

## Detail capture size. A half-resolution overview supplies the periphery;
## close views keep a sharp, gaze-centered patch at a stable world-space density.
@export var max_viewport_size := Vector2i(2048, 2048):
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
var _detail_close := false
var _detail_left: SubViewport
var _detail_right: SubViewport
var _detail_left_camera: Camera3D
var _detail_right_camera: Camera3D
var _detail_left_crop := Rect2(0, 0, 1, 1)
var _detail_right_crop := Rect2(0, 0, 1, 1)
var _left_crop := Rect2(0, 0, 1, 1)
var _right_crop := Rect2(0, 0, 1, 1)


func _ready() -> void:
	add_to_group("planar_mirrors")
	mirror_glass.layers = AvatarView.MIRROR_SURFACE
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
	_full_resolution(sub_viewport)


func _setup_editor_preview(source_material: ShaderMaterial) -> void:
	# Touching the scene's SubViewport in the editor would mark it dirty and save
	# a World3D override into the scene. An internal viewport is never serialized.
	_preview_material = source_material
	_preview_viewport = SubViewport.new()
	_preview_viewport.name = "EditorMirrorViewport"
	add_child(_preview_viewport, false, Node.INTERNAL_MODE_FRONT)
	_preview_viewport.world_3d = get_world_3d()
	_full_resolution(_preview_viewport)
	_preview_camera = Camera3D.new()
	_preview_camera.name = "EditorMirrorCamera"
	_preview_camera.current = true
	AvatarView.configure_mirror_camera(_preview_camera)
	_preview_viewport.add_child(_preview_camera, false, Node.INTERNAL_MODE_FRONT)
	_preview_material.set_shader_parameter("viewport_texture", _preview_viewport.get_texture())


func _process(_delta: float) -> void:
	var target_viewport := _target_viewport()
	if target_viewport == null:
		return
	if _viewport_size == Vector2i.ZERO or Engine.is_editor_hint():
		_resize_viewport()
	var source := _view_camera()
	var interface := _active_xr_interface()
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
	var left_direction := -source.get_camera_transform().basis.z
	var right_direction := left_direction
	var active := _is_front_side(eye, glass.origin, normal)
	var left_planes: Array[Plane] = []
	var right_planes: Array[Plane] = []
	if stereo:
		# XRInterface expects the origin transform, not the already-tracked head.
		var origin := (source.get_parent() as Node3D).global_transform
		var left_view := interface.get_transform_for_view(0, origin)
		var right_view := interface.get_transform_for_view(1, origin)
		eye = left_view.origin
		right_eye = right_view.origin
		left_direction = -left_view.basis.z
		right_direction = -right_view.basis.z
		var left_projection := interface.get_projection_for_view(0, 1.0, source.near, source.far)
		var right_projection := interface.get_projection_for_view(1, 1.0, source.near, source.far)
		left_planes = _projection_planes(left_projection, left_view)
		right_planes = _projection_planes(right_projection, right_view)
		active = active and (_bounds_in_planes(left_planes, glass) or _bounds_in_planes(right_planes, glass))
	else:
		left_planes = source.get_frustum()
		active = active and _bounds_in_planes(left_planes, glass)
	_set_updates(active)
	if not active:
		return
	# A stable overview avoids reallocating or diluting the entire capture on
	# head turns. The detail pass follows the gaze intersection on the glass;
	# its physical extent depends on distance, never on the head's rotation.
	_left_crop = Rect2(0, 0, 1, 1)
	_right_crop = _left_crop
	_fit_reflection(_target_camera(), eye, source.far)
	if stereo:
		_fit_reflection(_right_camera, right_eye, source.far)
	if Engine.is_editor_hint():
		return
	_ensure_detail_views()
	var height := mirror_glass.get_aabb().size.z * glass.basis.z.length()
	var distance := absf((eye - glass.origin).dot(normal))
	var close := distance < height * (0.3 if _detail_close else 0.2)
	if close != _detail_close:
		_detail_close = close
		_resize_viewport()
	_target_viewport().render_target_update_mode = SubViewport.UPDATE_ALWAYS if _detail_close else SubViewport.UPDATE_DISABLED
	if _right_viewport != null:
		_right_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _detail_close and stereo else SubViewport.UPDATE_DISABLED
	_runtime_material.set_shader_parameter("close_detail", _detail_close)
	_detail_left_crop = _detail_crop(eye, left_direction, glass, _detail_left.size)
	_fit_reflection(_detail_left_camera, eye, source.far, _detail_left_crop)
	_detail_left.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if stereo:
		_detail_right_crop = _detail_crop(right_eye, right_direction, glass, _detail_right.size)
		_fit_reflection(_detail_right_camera, right_eye, source.far, _detail_right_crop)
		_detail_right.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_runtime_material.set_shader_parameter("detail_left_rect", Vector4(_detail_left_crop.position.x, _detail_left_crop.position.y, _detail_left_crop.size.x, _detail_left_crop.size.y))
	_runtime_material.set_shader_parameter("detail_right_rect", Vector4(_detail_right_crop.position.x, _detail_right_crop.position.y, _detail_right_crop.size.x, _detail_right_crop.size.y))
	_runtime_material.set_shader_parameter("detail_enabled", true)


func _ensure_detail_views() -> void:
	if _detail_left == null:
		_detail_left = _make_detail_view("LeftEyeDetail")
		_detail_left_camera = _detail_left.get_child(0) as Camera3D
		_runtime_material.set_shader_parameter("detail_texture", _detail_left.get_texture())
	if _stereo and _detail_right == null:
		_detail_right = _make_detail_view("RightEyeDetail")
		_detail_right_camera = _detail_right.get_child(0) as Camera3D
		_runtime_material.set_shader_parameter("right_detail_texture", _detail_right.get_texture())
	_resize_viewport()


func _make_detail_view(label: String) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = label
	viewport.world_3d = get_world_3d()
	_full_resolution(viewport)
	add_child(viewport, false, Node.INTERNAL_MODE_FRONT)
	var camera := Camera3D.new()
	camera.current = true
	AvatarView.configure_mirror_camera(camera)
	viewport.add_child(camera)
	return viewport


func _detail_crop(eye: Vector3, direction: Vector3, glass: Transform3D, target_size: Vector2i) -> Rect2:
	if not _detail_close:
		return Rect2(0, 0, 1, 1)
	var bounds := mirror_glass.get_aabb()
	var normal := glass.basis.y.normalized()
	var distance := (eye - glass.origin).dot(normal)
	var toward := direction.dot(normal)
	var hit := eye - normal * distance
	if toward < -0.001:
		hit = eye + direction * (-distance / toward)
	var local := glass.affine_inverse() * hit - bounds.get_center()
	var center := Vector2(local.x / bounds.size.x + 0.5, 0.5 - local.z / bounds.size.z)
	# The center remains on the visible glass even near an edge. Padding may
	# extend beyond it; only the physical glass samples this texture.
	center = center.clamp(Vector2.ZERO, Vector2.ONE)
	var side := maxf(0.04, absf(distance) * 4.0)
	var size := Vector2(side * float(target_size.x) / target_size.y / (bounds.size.x * glass.basis.x.length()), side / (bounds.size.z * glass.basis.z.length()))
	return Rect2(center - size * 0.5, size)


func _ensure_right_view() -> void:
	if _right_viewport != null:
		return
	_right_viewport = SubViewport.new()
	_right_viewport.name = "RightEyeReflection"
	_right_viewport.world_3d = get_world_3d()
	_full_resolution(_right_viewport)
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
	if _detail_left != null:
		_detail_left.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if _detail_right != null:
		_detail_right.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active and _stereo else SubViewport.UPDATE_DISABLED


func _fit_reflection(camera: Camera3D, eye: Vector3, far_distance: float, crop := Rect2(0, 0, 1, 1)) -> void:
	var glass := mirror_glass.global_transform
	var bounds := mirror_glass.get_aabb()
	var center := glass * bounds.get_center()
	var right := glass.basis.x.normalized()
	var up := glass.basis.z.normalized()
	var normal := glass.basis.y.normalized()
	var reflected_eye := _reflect_point(eye, center, normal)
	var crop_center := crop.get_center()
	center += right * ((crop_center.x - 0.5) * bounds.size.x * glass.basis.x.length())
	center += up * ((0.5 - crop_center.y) * bounds.size.z * glass.basis.z.length())
	# A proper-handed camera, fixed to the glass, avoids the negative camera
	# determinant and head-rotation-dependent SCREEN_UV mapping of the old path.
	camera.global_transform = Transform3D(Basis(right, up, -normal), reflected_eye)
	var depth := maxf(0.01, (center - reflected_eye).dot(normal))
	var offset := Vector2((center - reflected_eye).dot(right), (center - reflected_eye).dot(up))
	var height := bounds.size.z * glass.basis.z.length() * crop.size.y
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
	# Fit the glass aspect rather than the desktop/XR framebuffer aspect.
	var bounds := mirror_glass.get_aabb()
	var glass := mirror_glass.global_transform
	var aspect := maxf(0.01, bounds.size.x * glass.basis.x.length()) / maxf(0.01, bounds.size.z * glass.basis.z.length())
	var cap := max_viewport_size if Engine.is_editor_hint() else max_viewport_size / 2
	var target := _fit_size(cap, aspect)
	_viewport_size = target
	var target_viewport := _target_viewport()
	if target_viewport != null and target_viewport.size != target:
		target_viewport.size = target
	if _right_viewport != null and _right_viewport.size != target:
		_right_viewport.size = target
	var detail_size := _fit_size(max_viewport_size, 1.0 if _detail_close else aspect)
	for detail in [_detail_left, _detail_right]:
		if detail != null and detail.size != detail_size:
			detail.size = detail_size


static func _fit_size(cap: Vector2i, aspect: float) -> Vector2i:
	var width := float(cap.x)
	var height := width / aspect
	if height > cap.y:
		height = float(cap.y)
		width = height * aspect
	return Vector2i(maxi(1, roundi(width)), maxi(1, roundi(height)))


static func _active_xr_interface() -> XRInterface:
	var primary := XRServer.primary_interface
	if primary != null and primary.is_initialized():
		return primary
	for name in ["WebXR", "OpenXR"]:
		var interface := XRServer.find_interface(name)
		if interface != null and interface.is_initialized():
			return interface
	return null


static func _full_resolution(viewport: SubViewport) -> void:
	viewport.canvas_cull_mask = 0
	viewport.vrs_mode = Viewport.VRS_DISABLED
	viewport.scaling_3d_scale = 1.0
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED


func debug_report() -> String:
	return "Mirror: %s | stereo %s | overview %s | detail L %s / R %s | close %s | patch L %s / R %s | VRS disabled, scale 1" % [name, _stereo, _target_viewport().size, _detail_left.size if _detail_left != null else Vector2i.ZERO, _detail_right.size if _detail_right != null else Vector2i.ZERO, _detail_close, _detail_left_crop, _detail_right_crop]
