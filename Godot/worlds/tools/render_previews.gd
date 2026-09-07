extends Node

# Run with a renderer: godot --xr-mode off --path Godot res://worlds/tools/render_previews.tscn
const SHOTS := {
	"floating_island": Vector3(9, 7, 11),
	"moon_garden": Vector3(23, 17, 26),
}


func _ready() -> void:
	_render.call_deferred()


func _render() -> void:
	for id: String in SHOTS:
		if not WorldCatalog.WORLDS.has(id):
			continue
		var viewport := SubViewport.new()
		viewport.size = Vector2i(640, 360)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var world: Node3D = WorldCatalog.WORLDS[id].scene.instantiate()
		viewport.add_child(world)
		var camera := Camera3D.new()
		viewport.add_child(camera)
		camera.position = SHOTS[id]
		camera.fov = 60
		camera.look_at(Vector3(0, 1, 0))
		camera.current = true
		for frame in range(8):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var result := viewport.get_texture().get_image().save_png("res://worlds/previews/" + id + ".png")
		if result != OK:
			push_error("Could not save preview: " + id)
			get_tree().quit(1)
			return
		viewport.free()
	get_tree().quit()
