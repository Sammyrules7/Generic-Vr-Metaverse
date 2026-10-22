class_name AvatarCatalog
extends RefCounted
## Registry snapshot IDs resolve locally. Peers never supply download URLs.

static var _entries: Array[Dictionary] = []
static var _by_id: Dictionary = {}


static func _ensure_loaded() -> void:
	if not _entries.is_empty():
		return
	_entries.append({"id": "default", "title": "Explorer", "url": "", "collection": "Bundled", "license": "Bundled", "attribution": "Built-in Explorer avatar"})
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://avatar/catalog.json"))
	if data is Array:
		for entry in data:
			if entry is Dictionary:
				_entries.append(entry)
	for entry in _entries:
		_by_id[entry.id] = entry


static func entries() -> Array[Dictionary]:
	_ensure_loaded()
	return _entries.duplicate(true)


static func has_avatar(id: String) -> bool:
	_ensure_loaded()
	return id.length() <= 64 and _by_id.has(id)


static func definition(id: String) -> Dictionary:
	_ensure_loaded()
	return _by_id.get(id, {}).duplicate(true) if id.length() <= 64 else {}


static func collections() -> Array[String]:
	_ensure_loaded()
	var names: Array[String] = []
	for entry in _entries:
		var collection := str(entry.get("collection", "Bundled"))
		if not collection in names:
			names.append(collection)
	names.sort()
	return names


static func search(query: String = "", collection: String = "") -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	query = query.strip_edges().to_lower()
	for entry in _entries:
		if not collection.is_empty() and entry.get("collection", "Bundled") != collection:
			continue
		var text := "%s %s %s" % [entry.get("title", ""), entry.get("collection", "Bundled"), entry.get("creator", "")]
		if query.is_empty() or query in text.to_lower():
			result.append(entry.duplicate(true))
	return result
