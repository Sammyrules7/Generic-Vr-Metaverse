extends Node
## Persistent, deduplicated asset loading. All scene/import work stays on main.

signal selection_changed(id: String)
signal springs_changed(enabled: bool)

const CACHE_DIR := "user://avatars"
const MAX_DOWNLOADS := 2
const MAX_MEMORY_SCENES := 4
const MAX_DISK_BYTES := 128 * 1024 * 1024
const MAX_AVATAR_BYTES := 64 * 1024 * 1024
const EXTENSIONS := [
	preload("res://avatar/avatar_image_extension.gd"),
	preload("res://addons/vrm/vrm_extension.gd"),
	preload("res://addons/vrm/1.0/VRMC_vrm.gd"),
	preload("res://addons/vrm/1.0/VRMC_springBone.gd"),
	preload("res://addons/vrm/1.0/VRMC_materials_mtoon.gd"),
	preload("res://addons/vrm/1.0/VRMC_node_constraint.gd"),
	preload("res://addons/vrm/1.0/VRMC_materials_hdr_emissiveMultiplier.gd"),
]

var _extensions: Array[GLTFDocumentExtension] = []
var _loads: Dictionary = {}
var _cache: Dictionary = {}
var _lru: Array[String] = []
var _next_token := 0
var _active_downloads := 0
var _importing := false
var _image_job: AvatarImageJob
var _import_model: Node3D
var _next_import := 0
var _exiting := false
# Optional injected trust store for isolated test environments; verification stays on.
var tls_options: TLSOptions


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	for script in EXTENSIONS:
		var extension: GLTFDocumentExtension = script.new()
		_extensions.append(extension)
		GLTFDocument.register_gltf_document_extension(extension, script == preload("res://addons/vrm/vrm_extension.gd"))
	_prune_disk_cache()


func select_avatar(id: String) -> void:
	if not AvatarCatalog.has_avatar(id):
		return
	PlayerProfile.avatar_id = id
	PlayerProfile.save()
	selection_changed.emit(id)
	if Networking.player_replication != null:
		Networking.player_replication.broadcast_avatar(id)


func set_springs_enabled(enabled: bool) -> void:
	PlayerProfile.spring_bones_enabled = enabled
	PlayerProfile.save()
	springs_changed.emit(enabled)


func acquire(id: String, bytes_only := false) -> AvatarLoadRequest:
	var request := AvatarLoadRequest.new()
	request.bytes_only = bytes_only
	if not AvatarCatalog.has_avatar(id):
		request.finish(null, "Unknown avatar")
		return request
	if id == "default":
		request.finish(null)
		return request
	if _cache.has(id):
		_touch(id)
		request.finish(null if bytes_only else _cache[id])
		return request
	_next_token += 1
	var token := _next_token
	request._on_release = _release.bind(id, token)
	if not _loads.has(id):
		_loads[id] = {"requests": {}, "http": null, "job": null, "started": false, "retried": false}
	_loads[id].requests[token] = request
	return request


func _release(id: String, token: int) -> void:
	if not _loads.has(id):
		return
	var load: Dictionary = _loads[id]
	load.requests.erase(token)
	if not load.requests.is_empty():
		return
	if is_instance_valid(load.http):
		load.http.cancel_request()
		load.http.queue_free()
		_active_downloads -= 1
		load.http = null
	# Pool tasks cannot be forcibly cancelled: poll and collect before freeing.
	if load.job == null:
		_loads.erase(id)


func _process(_delta: float) -> void:
	for id: String in _loads.keys():
		if not _loads.has(id):
			continue
		var load: Dictionary = _loads[id]
		var job: AvatarAssetJob = load.job
		if job != null:
			if job.task_id >= 0 and not WorkerThreadPool.is_task_completed(job.task_id):
				continue
			if job.task_id >= 0:
				WorkerThreadPool.wait_for_task_completion(job.task_id)
			load.job = null
			if load.requests.is_empty():
				_loads.erase(id)
				continue
			if not job.error.is_empty():
				if job.from_cache and not load.retried:
					DirAccess.remove_absolute(job.path)
					load.retried = true
					load.started = false
				else:
					_complete(id, null, job.error)
				continue
			if not job.from_cache:
				_prune_disk_cache()
			# Hover requests warm the verified disk cache without importing scenes.
			for token in load.requests.keys():
				var consumer: AvatarLoadRequest = load.requests[token]
				if consumer.bytes_only:
					load.requests.erase(token)
					consumer._on_release = Callable()
					consumer.finish(null)
			if load.requests.is_empty():
				_loads.erase(id)
				continue
			load.bytes = job.bytes
		if load.has("bytes") and not load.get("importing", false) and not _importing:
			load.importing = true
			_import_and_complete(id, load.bytes)
			return
		if not load.started and _active_downloads < MAX_DOWNLOADS:
			_start(id)


func _import_and_complete(id: String, bytes: PackedByteArray) -> void:
	_importing = true
	_next_import += 1
	var generation := _next_import
	_loads[id].import_generation = generation
	_image_job = AvatarImageJob.new()
	_image_job.bytes = bytes
	if OS.has_feature("web") and not OS.has_feature("threads"):
		_image_job.run()
	else:
		_image_job.task_id = WorkerThreadPool.add_task(_image_job.run, false, "Decode avatar textures")
		while not WorkerThreadPool.is_task_completed(_image_job.task_id):
			await get_tree().process_frame
		WorkerThreadPool.wait_for_task_completion(_image_job.task_id)
	var images := _image_job.images
	_image_job = null
	if not _import_is_current(id, generation):
		_importing = false
		return
	var document := GLTFDocument.new()
	var state := _import_state()
	state.set_additional_data(&"avatar/decoded_images", images)
	state.set_additional_data(&"avatar/decoded_image_hits", 0)
	var result := document.append_from_buffer(bytes, "", state, 8)
	# Keep indivisible engine import calls on main, but don't stack parsing,
	# generation, geometry baking and consumer instantiation into one frame.
	await get_tree().process_frame
	var model: Node3D
	var extensions: Dictionary = state.json.get("extensions", {})
	if _import_is_current(id, generation) and result == OK and (extensions.has("VRM") or extensions.has("VRMC_vrm")):
		model = document.generate_scene(state) as Node3D
		_import_model = model
		if is_instance_valid(model):
			AvatarSprings.prepare_sources(model)
			model.set_meta("avatar_decoded_textures", state.get_additional_data(&"avatar/decoded_image_hits"))
	await get_tree().process_frame
	if is_instance_valid(model) and _import_is_current(id, generation):
		AvatarScale.normalize(model)
		await get_tree().process_frame
		await get_tree().process_frame
	var packed: PackedScene
	if is_instance_valid(model):
		if _import_is_current(id, generation):
			packed = PackedScene.new()
			if packed.pack(model) != OK:
				packed = null
		model.free()
	_import_model = null
	_importing = false
	if _import_is_current(id, generation):
		_complete(id, packed, "Could not import avatar" if packed == null else "")


func _import_is_current(id: String, generation: int) -> bool:
	return not _exiting and _loads.has(id) and _loads[id].get("import_generation", -1) == generation


func _import_state() -> GLTFState:
	var state := GLTFState.new()
	state.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED
	state.set_additional_data(&"vrm/head_hiding_method", 3)
	state.set_additional_data(&"vrm/first_person_layers", 2)
	state.set_additional_data(&"vrm/third_person_layers", 1)
	return state


func _start(id: String) -> void:
	var load: Dictionary = _loads[id]
	var definition := AvatarCatalog.definition(id)
	load.started = true
	if definition.has("bundled_path"):
		_verify(id, FileAccess.get_file_as_bytes(str(definition.bundled_path)), "", false)
		return
	var path := CACHE_DIR + "/" + str(definition.get("sha256", str(definition.url).sha256_text())) + ".vrm"
	if FileAccess.file_exists(path):
		_verify(id, PackedByteArray(), path, true)
		return
	var http := HTTPRequest.new()
	http.timeout = 60.0
	http.body_size_limit = mini(MAX_AVATAR_BYTES, int(definition.get("size_bytes", MAX_AVATAR_BYTES)))
	http.max_redirects = 5
	if tls_options != null:
		http.set_tls_options(tls_options)
	add_child(http)
	load.http = http
	_active_downloads += 1
	http.request_completed.connect(func(result: int, status: int, _headers: PackedStringArray, bytes: PackedByteArray):
		_active_downloads -= 1
		http.queue_free()
		if not _loads.has(id):
			return
		_loads[id].http = null
		if result != HTTPRequest.RESULT_SUCCESS or status != 200:
			_complete(id, null, "Avatar download failed (%d/%d). Try again." % [result, status])
			return
		_verify(id, bytes, path, false)
	)
	var error := http.request(AvatarAssets.url(id, "model"))
	if error != OK:
		_active_downloads -= 1
		http.queue_free()
		load.http = null
		_complete(id, null, "Could not start avatar download")


func _verify(id: String, bytes: PackedByteArray, path: String, from_cache: bool) -> void:
	var definition := AvatarCatalog.definition(id)
	var job := AvatarAssetJob.new()
	job.bytes = bytes
	job.expected_hash = definition.get("sha256", "")
	job.expected_size = int(definition.get("size_bytes", 0))
	job.path = path
	job.from_cache = from_cache
	_loads[id].job = job
	# Single-threaded Web exports do not have a worker pool.
	if OS.has_feature("web") and not OS.has_feature("threads"):
		job.run()
	else:
		job.task_id = WorkerThreadPool.add_task(job.run, false, "Verify avatar")


func _complete(id: String, packed: PackedScene, error: String) -> void:
	if not _loads.has(id):
		return
	var requests: Array = _loads[id].requests.values()
	_loads.erase(id)
	if packed != null:
		_cache[id] = packed
		_touch(id)
		while _lru.size() > MAX_MEMORY_SCENES:
			_cache.erase(_lru.pop_front())
	for request: AvatarLoadRequest in requests:
		request._on_release = Callable()
		request.finish(packed, error)


func _touch(id: String) -> void:
	_lru.erase(id)
	_lru.append(id)


func import_bytes(bytes: PackedByteArray) -> PackedScene:
	var document := GLTFDocument.new()
	var state := _import_state()
	if document.append_from_buffer(bytes, "", state, 8) != OK:
		return null
	var extensions: Dictionary = state.json.get("extensions", {})
	if not extensions.has("VRM") and not extensions.has("VRMC_vrm"):
		return null
	var model := document.generate_scene(state) as Node3D
	if model == null:
		return null
	AvatarSprings.prepare_sources(model)
	AvatarScale.normalize(model)
	var packed := PackedScene.new()
	var result := packed.pack(model)
	model.free()
	return packed if result == OK else null


func _prune_disk_cache() -> void:
	var files: Array[Dictionary] = []
	var total := 0
	for file in DirAccess.get_files_at(CACHE_DIR):
		var path := CACHE_DIR + "/" + file
		if file.ends_with(".tmp"):
			DirAccess.remove_absolute(path)
			continue
		if not file.ends_with(".vrm"):
			continue
		var handle := FileAccess.open(path, FileAccess.READ)
		if handle == null:
			continue
		var size := handle.get_length()
		handle.close()
		files.append({"path": path, "size": size, "time": FileAccess.get_modified_time(path)})
		total += size
	files.sort_custom(func(a: Dictionary, b: Dictionary): return a.time < b.time)
	for file in files:
		if total <= MAX_DISK_BYTES:
			break
		DirAccess.remove_absolute(file.path)
		total -= int(file.size)


func _exit_tree() -> void:
	_exiting = true
	if is_instance_valid(_import_model):
		_import_model.free()
	_import_model = null
	if _image_job != null and _image_job.task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_image_job.task_id)
	for load: Dictionary in _loads.values():
		if is_instance_valid(load.http):
			load.http.cancel_request()
		var job: AvatarAssetJob = load.job
		if job != null and job.task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(job.task_id)
	_loads.clear()
	for extension in _extensions:
		GLTFDocument.unregister_gltf_document_extension(extension)
	_extensions.clear()


func download_progress(id: String) -> Dictionary:
	if not _loads.has(id):
		return {}
	var entry: Dictionary = _loads[id]
	if is_instance_valid(entry.http):
		return {"downloaded": entry.http.get_downloaded_bytes(), "total": entry.http.get_body_size()}
	return {"preparing": entry.started}
