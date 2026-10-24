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
	for entry in AvatarLocalLibrary.load_entries():
		_entries.append(entry)
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
	var names: Array[String] = ["Custom"]
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


static func is_custom(id: String) -> bool:
	var entry := definition(id)
	return bool(entry.get("local_custom", false)) or bool(entry.get("remote_custom", false))


static func replication_id(id: String) -> String:
	return id if has_avatar(id) and not definition(id).get("remote_custom", false) else "default"


static func register_local(entry: Dictionary) -> void:
	_ensure_loaded()
	if not AvatarLocalLibrary.valid_id(str(entry.get("id", ""))) or (_by_id.has(entry.id) and not definition(entry.id).get("remote_custom", false)):
		return
	_entries.append(entry.duplicate(true))
	_by_id[entry.id] = _entries.back()


static func unregister_local(id: String) -> void:
	if not is_custom(id):
		return
	for i in range(_entries.size() - 1, -1, -1):
		if _entries[i].id == id:
			_entries.remove_at(i)
	_by_id.erase(id)


static func is_owned(id: String) -> bool:
	return bool(definition(id).get("local_custom", false))


static func register_remote(entry: Dictionary) -> void:
	_ensure_loaded()
	if AvatarLocalLibrary.valid_id(str(entry.get("id", ""))) and not is_owned(entry.id):
		# Received assets are resolvable for rendering but never browseable,
		# favoriteable or selectable as one's own avatar.
		_by_id[entry.id] = entry.duplicate(true)
