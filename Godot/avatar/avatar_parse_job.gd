class_name AvatarParseJob
extends RefCounted
## One isolated importer owns the detached scene and its resources until packed.
## Only the resulting PackedScene crosses back to the main thread.
var bytes := PackedByteArray()
var document: GLTFDocument
var state: GLTFState
var task_id := -1
var result := ERR_UNCONFIGURED
var elapsed_ms := 0.0
var scene: PackedScene
var timings := {}

func run() -> void:
	var started := Time.get_ticks_usec()
	result = document.append_from_buffer(bytes, "", state, 8)
	elapsed_ms = (Time.get_ticks_usec() - started) / 1000.0
	timings["GLTF parse"] = elapsed_ms
	var extensions: Dictionary = state.json.get("extensions", {})
	if result != OK or not (extensions.has("VRM") or extensions.has("VRMC_vrm")):
		return
	started = Time.get_ticks_usec()
	var model := document.generate_scene(state) as Node3D
	timings["generate scene"] = (Time.get_ticks_usec() - started) / 1000.0
	if model == null:
		return
	AvatarSprings.prepare_sources(model)
	model.set_meta("avatar_decoded_textures", state.get_additional_data(&"avatar/decoded_image_hits"))
	started = Time.get_ticks_usec()
	AvatarScale.normalize(model)
	timings["normalize rig"] = (Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	scene = PackedScene.new()
	if scene.pack(model) != OK:
		scene = null
	timings["pack scene"] = (Time.get_ticks_usec() - started) / 1000.0
	model.free()
