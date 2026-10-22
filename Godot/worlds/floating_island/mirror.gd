@tool
extends Node3D
## Planar mirror for the floating island.
##
## MirrorGlass renders the view from the player camera reflected across the
## glass plane into its SubViewport. The glass samples that view in screen space
## so the reflection lines up with the player's actual viewpoint instead of
## stretching a whole camera image across the mesh.
##
## The glass must stay single-sided (cull_back): the reflected camera sits
## behind the mirror, so the glass back face is never drawn into its own view.
##
## In the editor the mirror follows the main 3D view camera and renders through
## an internal, unsaved SubViewport. The scene's own SubViewport is left alone so
## saving the scene never serializes an editor World3D override.

## Cap the extra 3D pass; the aspect ratio stays matched to the player viewport.
const MAX_VIEWPORT_SIZE := Vector2i(1024, 1024)

@onready var mirror_glass: MeshInstance3D = $MirrorGlass
@onready var sub_viewport: SubViewport = $MirrorGlass/SubViewport
@onready var reflect_camera: Camera3D = $MirrorGlass/SubViewport/ReflectCamera

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
	# Each mirror owns its viewport texture; sharing mirror.tres between two
	# loaded worlds would make them fight over the same reflection.
	var material := source_material.duplicate() as ShaderMaterial
	mirror_glass.material_override = material
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
	if _viewport_size == Vector2i.ZERO:
		_resize_viewport()
	if target_viewport.world_3d == null:
		target_viewport.world_3d = get_world_3d()
	# The active camera is the desktop camera, the XR head, or the editor's 3D
	# view, so rebinding a replacement camera also handles mode switches.
	var source := _view_camera()
	if source == null:
		_source_camera = null
		target_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var target_camera := _target_camera()
	if source != _source_camera or Engine.is_editor_hint():
		_source_camera = source
		_copy_projection(target_camera, source)
	var glass := mirror_glass.global_transform
	var normal := glass.basis.y.normalized()
	# The back of a mirror is opaque and off-screen from its own reflection.
	var active := _is_front_side(source.global_position, glass.origin, normal) and _is_in_view(source, glass)
	target_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if not active:
		return
	target_camera.global_transform = reflected_transform(source.global_transform, glass.origin, normal)


## Mirror a camera pose across the plane. Reflecting the full basis keeps a
## true planar reflection; the shader samples the result in screen space.
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
	# A large mirror can cover the screen with every corner outside the frustum.
	if source.is_position_in_frustum(glass.origin):
		return true
	var bounds := mirror_glass.get_aabb()
	for index in 8:
		if source.is_position_in_frustum(glass * bounds.get_endpoint(index)):
			return true
	return false


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


func _copy_projection(target: Camera3D, source: Camera3D) -> void:
	# Copy the projection settings rather than the matrix: Camera3D rebuilds its
	# projection from these for the target viewport's aspect ratio.
	target.projection = source.projection
	target.fov = source.fov
	target.size = source.size
	target.near = source.near
	target.far = source.far
	target.keep_aspect = source.keep_aspect
	target.frustum_offset = source.frustum_offset
	target.h_offset = source.h_offset
	target.v_offset = source.v_offset


func _resize_viewport() -> void:
	var viewport := _view_viewport()
	if viewport == null:
		return
	var size := viewport.get_visible_rect().size
	if size.x < 1.0 or size.y < 1.0:
		return
	var scale := minf(1.0, minf(MAX_VIEWPORT_SIZE.x / size.x, MAX_VIEWPORT_SIZE.y / size.y))
	var target := Vector2i(maxi(1, roundi(size.x * scale)), maxi(1, roundi(size.y * scale)))
	if target == _viewport_size:
		return
	_viewport_size = target
	var target_viewport := _target_viewport()
	if target_viewport != null:
		target_viewport.size = target
