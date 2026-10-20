# One-time LightmapGI preparation for observatory.tscn (Godot 4.7).
#
# The final "Bake Lightmaps" still runs in the editor with a GPU; this script
# makes the scene bake-ready:
#   1. Sets the twenty static interior lantern/telegraph lights to Bake Static.
#      "Moonlight" stays Dynamic so the terraces keep realtime moon shadows.
#   2. Marks everything that moves or paints its own light as excluded
#      (GI Mode Disabled): the rotating star globe subtree, sea of clouds,
#      particle systems. Rotating constellations cannot be baked.
#   3. Adds a root-level LightmapGI node following the briarwick_manor pattern.
#
# Usage (from the repository root, after reimporting the GLB with UV2 enabled):
#   godot --headless --xr-mode off --path Godot --script res://worlds/starlight_observatory/tools/prepare_lightmaps.gd

extends SceneTree

const SCENE_PATH := "res://worlds/starlight_observatory/observatory.tscn"


func _init() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("Could not load %s" % SCENE_PATH)
		quit(1)
		return
	var root := packed.instantiate() as Node3D

	var lights_static := 0
	var lights_dynamic := 0
	for child in root.get_children():
		if child is Light3D:
			if child.name == "Moonlight":
				child.light_bake_mode = Light3D.BAKE_DYNAMIC
				lights_dynamic += 1
			else:
				child.light_bake_mode = Light3D.BAKE_STATIC
				lights_static += 1

	var excluded := _exclude_dynamic_gi(root)
	# Note: the four hidden "-col" trimesh meshes inside the Architecture GLB
	# instance are NOT excluded. Doing so would require editable-instance
	# overrides, which duplicate the whole GLB subtree into the .tscn. They are
	# duplicates of visible surfaces inside solid geometry; baking them costs a
	# little atlas area but is harmless.
	var lightmap := _add_lightmap(root)

	var new_packed := PackedScene.new()
	new_packed.pack(root)
	var err := ResourceSaver.save(new_packed, SCENE_PATH)
	if err != OK:
		push_error("Saving scene failed: %s" % err)
		quit(1)
		return

	print("prepare_lightmaps: lights static %d, dynamic %d, instances excluded %d" % [
		lights_static, lights_dynamic, excluded])
	print("prepare_lightmaps: LightmapGI added (%s)" % lightmap.name)
	quit(0)


func _exclude_dynamic_gi(root: Node) -> int:
	var excluded := 0
	# The whole star globe rotates at runtime (globe.gd); sea of clouds and
	# particles animate in shaders. Mark every instanced geometry under them.
	for path in ["StarGlobe", "SeaOfClouds"]:
		var node := root.find_child(path, true, false)
		if node == null:
			push_warning("Expected node not found: %s" % path)
			continue
		excluded += _disable_gi_recursively(node)
	# The four particle systems: fireflies, stardust, terrace breeze, cloudbank wind.
	for node in root.get_children():
		if node is GPUParticles3D:
			node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			excluded += 1
	return excluded


func _disable_gi_recursively(node: Node) -> int:
	var count := 0
	if node is GeometryInstance3D:
		node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		count += 1
	for child in node.get_children():
		count += _disable_gi_recursively(child)
	return count


func _add_lightmap(root: Node3D) -> LightmapGI:
	var existing := root.find_child("LightmapGI", false, false)
	if existing and existing is LightmapGI:
		return existing
	var lightmap := LightmapGI.new()
	lightmap.name = "LightmapGI"
	lightmap.texel_scale = 1.0
	lightmap.directional = true
	root.add_child(lightmap)
	lightmap.owner = root
	return lightmap
