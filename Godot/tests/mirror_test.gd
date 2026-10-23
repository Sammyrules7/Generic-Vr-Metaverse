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

	var source_size := root.get_visible_rect().size
	var expected_scale := minf(1.0, minf(1920.0 / source_size.x, 1920.0 / source_size.y))
	check(viewport.size == Vector2i(roundi(source_size.x * expected_scale), roundi(source_size.y * expected_scale)), "Default mirror must use the available higher resolution")
	check(viewport.size.x <= 1920 and viewport.size.y <= 1920, "Default reflection must respect its higher resolution cap")
	mirror.max_viewport_size = Vector2i(320, 320)
	check(viewport.size.x <= 320 and viewport.size.y <= 320, "Changing the mirror cap must resize its render target")
	check(absf(float(viewport.size.x) / viewport.size.y - source_size.x / source_size.y) < 0.02, "Mirror quality changes must preserve aspect ratio")
	mirror.max_viewport_size = Vector2i(1920, 1920)

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
