# One-time LightmapGI preparation for moonlit_grotto.tscn (Godot 4.7).
#
# What it does (no actual bake happens here — the final "Bake Lightmaps" click
# must run in the editor with a GPU):
#   1. Generates UV2 on every static inline ArrayMesh via lightmap_unwrap
#      (per-instance transform, 0.2 m texel size, matching the GLB import value).
#   2. Converts primitive meshes (Cylinder/Sphere/etc.) to ArrayMesh so they
#      can carry UV2 and be seen by the baker.
#   3. Marks animated/transparent surfaces as excluded from baking:
#      water, waterfall curtains, cascade ripples, the moon disc, particles.
#   4. Sets all nine static lights to Bake Static.
#   5. Adds a root-level LightmapGI node, ready to bake in the editor.
#
# The scene is self-contained (GLB flattened to inline meshes by build_grotto.gd),
# is referenced by path rather than uid, and carries no scene uid, so a re-save
# through ResourceSaver is safe (same flow build_grotto.gd itself uses).
#
# Usage (from the repository root):
#   godot --headless --xr-mode off --path Godot --script res://worlds/moonlit_grotto/tools/prepare_lightmaps.gd

extends SceneTree

const SCENE_PATH := "res://worlds/moonlit_grotto/moonlit_grotto.tscn"
const TEXEL_SIZE := 0.2

# Animated or additive surfaces that must not receive baked light.
const DO_NOT_BAKE := [
	"Stillwater",
	"Open sea",
	"Moon",
	"Waterfall",
	"Cascade ripples",
]


func _init() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("Could not load %s" % SCENE_PATH)
		quit(1)
		return
	var root := packed.instantiate() as Node3D
	if root == null:
		push_error("Scene root is not a Node3D")
		quit(1)
		return

	var unwrapped := 0
	var converted := 0
	var excluded := 0
	var _walked_meshes := 0
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)

		if node is GPUParticles3D:
			node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			excluded += 1
			continue
		if not (node is MeshInstance3D):
			continue
		var mesh_instance := node as MeshInstance3D
		_walked_meshes += 1
		if _should_exclude(mesh_instance.name):
			mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			excluded += 1
			continue

		var mesh: Mesh = mesh_instance.mesh
		if mesh == null:
			continue
		var xform := _relative_to_root(mesh_instance, root)

		if mesh is ArrayMesh:
			if _needs_uv2(mesh):
				mesh.lightmap_unwrap(xform, TEXEL_SIZE)
				unwrapped += 1
		else:
			# PrimitiveMesh and friends: rebuild as an ArrayMesh, then unwrap.
			var array_mesh := ArrayMesh.new()
			for surface in mesh.get_surface_count():
				array_mesh.add_surface_from_arrays(
					Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(surface))
				array_mesh.surface_set_material(surface, mesh.surface_get_material(surface))
			if _needs_uv2(array_mesh):
				array_mesh.lightmap_unwrap(xform, TEXEL_SIZE)
			mesh_instance.mesh = array_mesh
			converted += 1

	var lights_baked := _set_lights(root)
	var lightmap := _add_lightmap(root)
	var packed_new := PackedScene.new()
	packed_new.pack(root)
	var err := ResourceSaver.save(packed_new, SCENE_PATH)
	if err != OK:
		push_error("Saving scene failed: %s" % err)
		quit(1)
		return

	print("prepare_lightmaps: mesh nodes %d, unwrapped %d, converted %d, excluded %d, lights baked %d" % [
		_walked_meshes, unwrapped, converted, excluded, lights_baked])
	print("prepare_lightmaps: LightmapGI added (name=%s, directional=%s)" % [
		lightmap.name, lightmap.is_directional()])
	quit(0)


func _should_exclude(node_name: String) -> bool:
	for prefix in DO_NOT_BAKE:
		if node_name.begins_with(prefix) or node_name.contains(prefix):
			return true
	return false


func _relative_to_root(node: Node3D, root: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


func _needs_uv2(mesh: Mesh) -> bool:
	for surface in mesh.get_surface_count():
		if (mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_TEX_UV2) == 0:
			return true
	return false


func _set_lights(root: Node3D) -> int:
	var baked := 0
	for child in root.get_children():
		if child is Light3D:
			child.light_bake_mode = Light3D.BAKE_STATIC
			baked += 1
	return baked


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
