class_name AvatarLocalLibrary
extends RefCounted
## Private device storage. Paths are derived from hashes, never manifest input.
const DIRECTORY := "user://avatars/custom"
const MANIFEST := DIRECTORY + "/library.json"
const MAX_FILES := 32
const MAX_DISK_BYTES := 256 * 1024 * 1024

static func valid_id(id: String) -> bool:
	return id.length() == 64 and id == id.to_lower() and id.is_valid_hex_number(false)

static func path_for(id: String) -> String:
	return DIRECTORY + "/" + id + ".vrm" if valid_id(id) else ""

static func entry(id: String, title: String, size: int) -> Dictionary:
	return {"id": id, "title": title.strip_edges().left(80), "collection": "Custom", "local_custom": true, "local_path": path_for(id), "sha256": id, "size_bytes": size, "url": "", "license": "Local", "attribution": "Shared with peers while worn"}

static func load_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var manifest := FileAccess.open(MANIFEST, FileAccess.READ)
	if manifest == null or manifest.get_length() > 128 * 1024:
		return result
	var data: Variant = JSON.parse_string(manifest.get_as_text())
	if not data is Array:
		return result
	var seen := {}
	for item in data:
		if not item is Dictionary:
			continue
		var id := str(item.get("id", ""))
		if not valid_id(id) or seen.has(id) or not FileAccess.file_exists(path_for(id)):
			continue
		seen[id] = true
		result.append(entry(id, str(item.get("title", "Custom avatar")), int(item.get("size_bytes", 0))))
		if result.size() >= MAX_FILES:
			break
	return result

static func save_entries(entries: Array[Dictionary]) -> Error:
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	var records: Array[Dictionary] = []
	for item in entries:
		if item.get("local_custom", false):
			records.append({"id": item.id, "title": item.title, "size_bytes": item.size_bytes})
	var file := FileAccess.open(MANIFEST + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(records))
	file.close()
	return DirAccess.rename_absolute(MANIFEST + ".tmp", MANIFEST)
