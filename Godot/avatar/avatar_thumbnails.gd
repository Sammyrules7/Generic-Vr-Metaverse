class_name AvatarThumbnails
extends Node
## Small, bounded thumbnail loads. Models are acquired only by the picker.
signal loaded(url: String, texture: Texture2D)

var enabled := true
var _queue: Array[String] = []
var _http: Dictionary = {}
var _jobs: Dictionary = {}
var _cache: Dictionary = {}
var _lru: Array[String] = []

func request(url: String) -> Texture2D:
	if _cache.has(url):
		_lru.erase(url)
		_lru.append(url)
		return _cache[url]
	if enabled and url.begins_with("https://") and not _queue.has(url) and not _http.has(url) and not _jobs.has(url):
		_queue.append(url)
	return null

func _process(_delta: float) -> void:
	for url: String in _jobs.keys():
		var job: AvatarThumbnailJob = _jobs[url]
		if job.task_id >= 0 and not WorkerThreadPool.is_task_completed(job.task_id):
			continue
		if job.task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(job.task_id)
		_jobs.erase(url)
		var texture: Texture2D = ImageTexture.create_from_image(job.image) if job.image != null else null
		_remember(url, texture)
		loaded.emit(url, texture)
	while not _queue.is_empty() and _http.size() + _jobs.size() < 2:
		_start(_queue.pop_front())

func _start(url: String) -> void:
	var http := HTTPRequest.new()
	http.timeout = 12.0
	http.body_size_limit = 4 * 1024 * 1024
	if AvatarService.tls_options != null:
		http.set_tls_options(AvatarService.tls_options)
	add_child(http)
	_http[url] = http
	http.request_completed.connect(func(result: int, status: int, _headers: PackedStringArray, bytes: PackedByteArray):
		_http.erase(url)
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or status != 200:
			_remember(url, null)
			loaded.emit(url, null)
			return
		var job := AvatarThumbnailJob.new()
		job.bytes = bytes
		_jobs[url] = job
		if OS.has_feature("web") and not OS.has_feature("threads"):
			job.run()
		else:
			job.task_id = WorkerThreadPool.add_task(job.run, false, "Avatar thumbnail")
	)
	if http.request(url) != OK:
		_http.erase(url)
		http.queue_free()

func cancel_pending() -> void:
	_queue.clear()
	for http: HTTPRequest in _http.values():
		http.cancel_request()
		http.queue_free()
	_http.clear()
	# Jobs are collected without delivering results to old cards by the picker.

func _exit_tree() -> void:
	cancel_pending()
	for job: AvatarThumbnailJob in _jobs.values():
		if job.task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(job.task_id)

func _remember(url: String, texture: Texture2D) -> void:
	_cache[url] = texture
	_lru.erase(url)
	_lru.append(url)
	while _lru.size() > 64:
		_cache.erase(_lru.pop_front())
