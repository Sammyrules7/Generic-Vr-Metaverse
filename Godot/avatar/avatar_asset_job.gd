class_name AvatarAssetJob
extends RefCounted
## CPU/file work only: no scene nodes, shared dictionaries, or rendering APIs.

var bytes := PackedByteArray()
var expected_hash := ""
var expected_size := 0
var max_bytes := 64 * 1024 * 1024
var path := ""
var from_cache := false
var error := ""
var task_id := -1


func run() -> void:
	if from_cache:
		var source := FileAccess.open(path, FileAccess.READ)
		if source == null or source.get_length() > max_bytes:
			error = "Avatar file is unavailable or exceeds the size limit"
			return
		bytes = source.get_buffer(source.get_length())
	if (expected_size > 0 and bytes.size() != expected_size) or bytes.size() < 20 or bytes.size() > max_bytes:
		error = "Avatar download has an unexpected size"
		return
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	if not expected_hash.is_empty() and hash.finish().hex_encode() != expected_hash:
		error = "Avatar download failed its integrity check"
		return
	if bytes.decode_u32(0) != 0x46546c67 or bytes.decode_u32(4) != 2 or bytes.decode_u32(8) != bytes.size():
		error = "Avatar is not a valid GLB/VRM file"
		return
	if not from_cache and not path.is_empty():
		var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
		if file != null:
			file.store_buffer(bytes)
			file.close()
			DirAccess.rename_absolute(path + ".tmp", path)
