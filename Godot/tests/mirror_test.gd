extends SceneTree
## Headless coverage for the reusable planar mirror component.
##
## The reflection math is checked independently of rendering; the scene checks
## cover the wiring that previously left the mirror sampling an empty world.

const MIRROR_SCRIPT := preload("res://components/planar_mirror/planar_mirror.gd")
const MIRROR_MATERIAL := preload("res://components/planar_mirror/planar_mirror.tres")
const MIRROR_SCENE := preload("res://components/planar_mirror/planar_mirror.tscn")
const MIRROR_CAMERA_SCRIPT := preload("res://avatar/avatar_mirror_camera.gd")

var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func run() -> void:
	_test_reflection()
	await _test_scene()
	print("MIRROR_TEST failures=", failures)
	quit(1 if failures else 0)


func _test_reflection() -> void:
	var plane_origin := Vector3(1, 2, 3)
	var plane_normal := Vector3(0, 0, 1)
	var source := Transform3D(Basis(), Vector3(1, 2, 7))
	var reflected: Transform3D = MIRROR_SCRIPT.reflected_transform(source, plane_origin, plane_normal)
	check(reflected.origin.is_equal_approx(Vector3(1, 2, -1)), "Reflection must cross the mirror plane")
	check(is_equal_approx((reflected.origin - plane_origin).dot(plane_normal), -(source.origin - plane_origin).dot(plane_normal)), "Reflection must preserve distance to the plane")
	check(reflected.basis.z.is_equal_approx(Vector3(0, 0, -1)), "Reflected camera must look back through the mirror")
	check(reflected.basis.determinant() < 0.0, "Reflected camera pose must be mirrored, not rotated")
	var on_plane := MIRROR_SCRIPT.reflected_transform(Transform3D(Basis(), plane_origin), plane_origin, plane_normal)
	check(on_plane.origin.is_equal_approx(plane_origin), "Points on the mirror plane must not move")

	var slanted := Vector3(1, 1, 0).normalized()
	var slanted_reflection: Transform3D = MIRROR_SCRIPT.reflected_transform(source, plane_origin, slanted)
	var source_distance := (source.origin - plane_origin).dot(slanted)
	var reflected_distance := (slanted_reflection.origin - plane_origin).dot(slanted)
	check(is_equal_approx(reflected_distance, -source_distance), "Slanted mirrors must reflect in their own normal")
	var projected_source := source.origin - slanted * source_distance
	var projected_reflected := slanted_reflection.origin - slanted * reflected_distance
	check(projected_source.is_equal_approx(projected_reflected), "Reflection must preserve the point projected on the plane")


func _test_scene() -> void:
	var mirror := MIRROR_SCENE.instantiate()
	root.add_child(mirror)
	var glass := mirror.get_node("MirrorGlass") as MeshInstance3D
	var viewport := mirror.get_node("MirrorGlass/SubViewport") as SubViewport
	var reflected_camera := mirror.get_node("MirrorGlass/SubViewport/ReflectCamera") as Camera3D

	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, 4)
	camera.current = true
	root.add_child(camera)
	await process_frame
	await process_frame

	check(reflected_camera.get_script() == MIRROR_CAMERA_SCRIPT, "Reflect camera must use the avatar mirror camera setup")
	check(viewport.world_3d != null and viewport.world_3d == root.world_3d, "Mirror viewport must share the main 3D world")
	check(reflected_camera.global_position.is_equal_approx(Vector3(0, 0, -4)), "Reflect camera must follow the active player camera")
	check(reflected_camera.cull_mask & AvatarView.FULL_BODY != 0, "Mirror must draw the full local avatar")
	check(reflected_camera.cull_mask & AvatarView.FIRST_PERSON == 0, "Mirror must not draw the first-person body")
	var material := glass.material_override as ShaderMaterial
	check(material != null and material != MIRROR_MATERIAL, "Each mirror must own its material instance")
	check(material != null and material.get_shader_parameter("viewport_texture") == viewport.get_texture(), "Mirror material must sample its own viewport")
	check(viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Visible mirror must keep its reflection current")

	check(viewport.size.x == viewport.size.y, "Square glass must have a square reflection, independent of the window aspect")
	check(viewport.size.x <= 1920, "Default reflection must respect the quality cap")
	mirror.max_viewport_size = Vector2i(320, 320)
	check(viewport.size == Vector2i(320, 320), "Changing mirror quality must resize the render target")
	mirror.max_viewport_size = Vector2i(1920, 1920)
	mirror._process(0.016)
	var top_right := glass.global_transform * Vector3(1, 0, 1)
	var bottom_left := glass.global_transform * Vector3(-1, 0, -1)
	check(reflected_camera.unproject_position(top_right).distance_to(Vector2(viewport.size.x, 0)) < 0.01, "Glass top-right must project to the reflection top-right")
	check(reflected_camera.unproject_position(bottom_left).distance_to(Vector2(0, viewport.size.y)) < 0.01, "Glass bottom-left must project to the reflection bottom-left")
	check(reflected_camera.global_basis.determinant() > 0.0, "Render cameras must retain proper handedness")
	var eye_planes := MIRROR_SCRIPT._projection_planes(camera.get_camera_projection(), camera.get_camera_transform())
	check(mirror._bounds_in_planes(eye_planes, glass.global_transform), "XR projection-plane culling must retain visible glass")
	var behind_camera := glass.global_transform
	behind_camera.origin = Vector3(0, 0, 8)
	check(not mirror._bounds_in_planes(eye_planes, behind_camera), "XR projection-plane culling must reject glass behind the eye")
	var old_reflection := reflected_camera.global_transform
	camera.rotation.y = 0.2
	mirror._process(0.016)
	check(reflected_camera.global_transform.is_equal_approx(old_reflection), "Turning in place must not warp the glass projection")
	camera.rotation.y = 0.0
	# Exercise the two eye fits without requiring an attached headset.
	mirror._ensure_right_view()
	mirror._stereo = true
	mirror._resize_viewport()
	check(viewport.size == Vector2i(1920, 1920) and mirror._right_viewport.size == viewport.size, "XR reflection quality must use the full cap rather than the small desktop window")
	mirror._stereo = false
	mirror._resize_viewport()
	mirror._right_viewport.size = viewport.size
	mirror._fit_reflection(reflected_camera, Vector3(-0.032, 0, 4), 100.0)
	mirror._fit_reflection(mirror._right_camera, Vector3(0.032, 0, 4), 100.0)
	check(not reflected_camera.global_position.is_equal_approx(mirror._right_camera.global_position), "Stereo reflections must have distinct eye positions")
	check(reflected_camera.unproject_position(top_right).distance_to(mirror._right_camera.unproject_position(top_right)) < 0.01, "Both eye frustums must fit the same glass edges")
	check(reflected_camera.frustum_offset.x > 0 and mirror._right_camera.frustum_offset.x < 0, "Eye frustum offsets must have opposite signs")

	# Up close the glass can cover the screen while its center and corners are
	# all outside the tiny frustum. The reflection must keep updating.
	camera.position = Vector3(0, 0, 0.1)
	camera.look_at(Vector3(0.9, 0, 0), Vector3.UP)
	await process_frame
	await process_frame
	check(viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Close-up mirror must not freeze")

	# The back of the glass is opaque, so the extra 3D pass can stop.
	camera.position = Vector3(0, 0, -4)
	await process_frame
	await process_frame
	check(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Back-facing mirror must stop rendering")

	mirror.free()
	camera.free()
