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

## Cap the extra 3D pass; the aspect ratio stays matched to the main viewport.
const MAX_VIEWPORT_SIZE := Vector2i(1024, 1024)

@onready var mirror_glass: MeshInstance3D = $MirrorGlass
@onready var sub_viewport: SubViewport = $MirrorGlass/SubViewport
@onready var reflect_camera: Camera3D = $MirrorGlass/SubViewport/ReflectCamera

var _source_camera: Camera3D
var _viewport_size := Vector2i.ZERO


func _ready() -> void:
	var source_material := mirror_glass.get_active_material(0) as ShaderMaterial
	if source_material == null:
		push_error("MirrorGlass needs a ShaderMaterial with a viewport_texture uniform")
		sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		set_process(false)
		return
	# Each mirror owns its viewport texture; sharing mirror.tres between two
	# loaded worlds would make them fight over the same reflection.
	var material := source_material.duplicate() as ShaderMaterial
	mirror_glass.material_override = material
	material.set_shader_parameter("viewport_texture", sub_viewport.get_texture())
	# A SubViewport nested under MeshInstance3D does not inherit the world on its
	# own, so share it explicitly or the reflection renders an empty scene.
	sub_viewport.world_3d = get_world_3d()
	get_viewport().size_changed.connect(_resize_viewport)
	_resize_viewport()


func _process(_delta: float) -> void:
	if sub_viewport.world_3d == null:
		sub_viewport.world_3d = get_world_3d()
	# The active camera is the desktop camera, the XR head, or the loading
	# camera, so rebinding a replacement camera also handles mode switches.
	var source := get_viewport().get_camera_3d()
	if source == null:
		_source_camera = null
		sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if source != _source_camera:
		_source_camera = source
		_copy_projection(source)
	var glass := mirror_glass.global_transform
	var normal := glass.basis.y.normalized()
	# The back of a mirror is opaque and off-screen from its own reflection.
	var active := _is_front_side(source.global_position, glass.origin, normal) and _is_in_view(source, glass)
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if not active:
		return
	reflect_camera.global_transform = reflected_transform(source.global_transform, glass.origin, normal)


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


func _copy_projection(source: Camera3D) -> void:
	# Copy the projection settings rather than the matrix: Camera3D rebuilds its
	# projection from these for the SubViewport's aspect ratio.
	reflect_camera.projection = source.projection
	reflect_camera.fov = source.fov
	reflect_camera.size = source.size
	reflect_camera.near = source.near
	reflect_camera.far = source.far
	reflect_camera.keep_aspect = source.keep_aspect
	reflect_camera.frustum_offset = source.frustum_offset
	reflect_camera.h_offset = source.h_offset
	reflect_camera.v_offset = source.v_offset


func _resize_viewport() -> void:
	var size := get_viewport().get_visible_rect().size
	if size.x < 1.0 or size.y < 1.0:
		return
	var scale := minf(1.0, minf(MAX_VIEWPORT_SIZE.x / size.x, MAX_VIEWPORT_SIZE.y / size.y))
	var target := Vector2i(maxi(1, roundi(size.x * scale)), maxi(1, roundi(size.y * scale)))
	if target == _viewport_size:
		return
	_viewport_size = target
	sub_viewport.size = target
