class_name AvatarCatalog
extends RefCounted
## Only these pinned assets can be requested by a peer. URLs never cross RPCs.

static var _entries: Array[Dictionary] = []


static func entries() -> Array[Dictionary]:
	if _entries.is_empty():
		_entries.append({"id": "default", "title": "Explorer", "url": "", "license": "Bundled", "attribution": "Built-in Explorer avatar"})
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://avatar/catalog.json"))
		if data is Array:
			for entry in data:
				if entry is Dictionary:
					_entries.append(entry)
	return _entries.duplicate(true)


static func has_avatar(id: String) -> bool:
	return not definition(id).is_empty()


static func definition(id: String) -> Dictionary:
	if id.length() > 64:
		return {}
	for entry in entries():
		if entry.id == id:
			return entry
	return {}
