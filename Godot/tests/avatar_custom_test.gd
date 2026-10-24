extends SceneTree
var failures := 0
func _initialize() -> void:
	run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func mutate(bytes: PackedByteArray, change: Callable) -> PackedByteArray:
	var length := bytes.decode_u32(12)
	var json: Dictionary = JSON.parse_string(bytes.slice(20, 20 + length).get_string_from_utf8())
	change.call(json)
	var payload := JSON.stringify(json).to_utf8_buffer()
	while payload.size() % 4:
		payload.append(32)
	var result := bytes.slice(0, 20)
	result.encode_u32(12, payload.size())
	result.append_array(payload)
	result.append_array(bytes.slice(20 + length))
	result.encode_u32(8, result.size())
	return result
func reject(bytes: PackedByteArray, message: String) -> void:
	var job := AvatarCustomJob.new()
	job.bytes = bytes
	job.filename = "test.vrm"
	job.run()
	check(not job.error.is_empty(), message)
func run() -> void:
	var bytes := FileAccess.get_file_as_bytes("res://avatar/godette.vrm")
	var service := root.get_node("AvatarService")
	var manifest_existed := FileAccess.file_exists(AvatarLocalLibrary.MANIFEST)
	var manifest_backup := FileAccess.get_file_as_bytes(AvatarLocalLibrary.MANIFEST) if manifest_existed else PackedByteArray()
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	var id := hash.finish().hex_encode()
	var was_present := AvatarCatalog.has_avatar(id)
	var result: Dictionary = await service.import_local_bytes("Local Godette.vrm", bytes)
	check(result.get("error", "") == "" and result.get("id", "") == id, "VRM import through normal loader failed: " + str(result))
	check(AvatarCatalog.is_custom(id) and AvatarCatalog.replication_id(id) == "default", "Custom avatars must be private network fallbacks")
	check(AvatarCatalog.replication_id("godette") == "godette", "Public replication must stay intact")
	check(AvatarLocalLibrary.load_entries().any(func(item): return item.id == id), "Imported avatar did not persist")
	var entries_before := AvatarCatalog.search("", "Custom").size()
	var duplicate: Dictionary = await service.import_local_bytes("Duplicate.vrm", bytes)
	check(duplicate.get("id", "") == id and AvatarCatalog.search("", "Custom").size() == entries_before, "Identical content must deduplicate")
	var request: AvatarLoadRequest = service.acquire(id)
	if not request.finished:
		await request.completed
	check(request.scene != null and request.error.is_empty(), "Imported avatar cannot be previewed/equipped")
	request.release()
	var replication = load("res://player/player_replication.gd").new()
	replication._receive_avatar(42, id)
	check(replication._avatar_by_peer[42] == "default", "Incoming local hashes must not resolve even on same device")
	replication.free()
	reject(bytes.slice(0, 26), "Truncated file was accepted")
	reject(mutate(bytes, func(j): j.buffers[0].uri = "file:///etc/passwd"), "External buffer was accepted")
	reject(mutate(bytes, func(j): j.nodes[0]["extensions"] = {"GODOT_node": {"script": "x"}}), "Godot extension was accepted")
	reject(mutate(bytes, func(j): j.accessors[j.meshes[0].primitives[0].attributes.POSITION].count = 9999999), "Oversized geometry was accepted")
	reject(mutate(bytes, func(j): j.bufferViews[0].byteLength = bytes.size() * 2), "Invalid buffer bounds were accepted")
	reject(mutate(bytes, func(j): j.nodes[0].children = [0]), "Cyclic nodes were accepted")
	var bad_result: Dictionary = await service.import_local_bytes("script.gd", bytes)
	check(not bad_result.get("error", "").is_empty(), "Non-VRM filename must fail")
	if not was_present:
		AvatarCatalog.unregister_local(id)
		DirAccess.remove_absolute(AvatarLocalLibrary.path_for(id))
	if manifest_existed:
		FileAccess.open(AvatarLocalLibrary.MANIFEST, FileAccess.WRITE).store_buffer(manifest_backup)
	else:
		DirAccess.remove_absolute(AvatarLocalLibrary.MANIFEST)
	print("Custom avatar import: %d failures" % failures)
	quit(1 if failures else 0)
