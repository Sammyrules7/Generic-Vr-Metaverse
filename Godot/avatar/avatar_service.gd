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
# Optional injected trust store for isolated test environments; verification stays on.
var tls_options: TLSOptions


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	for script in EXTENSIONS:
		var extension: GLTFDocumentExtension = script.new()
		_extensions.append(extension)
		GLTFDocument.register_gltf_document_extension(extension, script == EXTENSIONS[0])
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


func acquire(id: String) -> AvatarLoadRequest:
	var request := AvatarLoadRequest.new()
	if not AvatarCatalog.has_avatar(id):
		request.finish(null, "Unknown avatar")
		return request
	if id == "default":
		request.finish(null)
		return request
	if _cache.has(id):
		_touch(id)
		request.finish(_cache[id])
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
			var packed := import_bytes(job.bytes)
			_complete(id, packed, "Could not import avatar" if packed == null else "")
			# One main-thread import per frame; shaders/GPU work must not run in pool.
			return
		if not load.started and _active_downloads < MAX_DOWNLOADS:
			_start(id)


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
	var error := http.request(str(definition.url))
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
	var state := GLTFState.new()
	state.set_additional_data(&"vrm/head_hiding_method", 3)
	state.set_additional_data(&"vrm/first_person_layers", 2)
	state.set_additional_data(&"vrm/third_person_layers", 1)
	if document.append_from_buffer(bytes, "", state, 8) != OK:
		return null
	var extensions: Dictionary = state.json.get("extensions", {})
	if not extensions.has("VRM") and not extensions.has("VRMC_vrm"):
		return null
	var model := document.generate_scene(state) as Node3D
	if model == null:
		return null
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
