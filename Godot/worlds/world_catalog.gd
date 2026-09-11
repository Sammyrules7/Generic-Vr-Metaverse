class_name WorldCatalog
extends RefCounted

const REGISTRY_PATH := "res://worlds/world_registry.tres"

# Preserve one shared lookup for the UI, profiles, and world loader.
static var WORLDS: Dictionary = read_registry(load(REGISTRY_PATH))


static func read_registry(registry: WorldRegistry) -> Dictionary:
	var entries := {}
	if registry == null:
		push_error("World registry could not be loaded: " + REGISTRY_PATH)
		return entries
	for world: WorldDefinition in registry.worlds:
		if world == null or world.id.strip_edges().is_empty() or world.title.strip_edges().is_empty() or not FileAccess.file_exists(world.scene_path):
			push_warning("Skipping incomplete world registry entry.")
			continue
		if entries.has(world.id):
			push_warning("Skipping duplicate world ID: " + world.id)
			continue
		entries[world.id] = world
	return entries


static func title(id: String) -> String:
	return WORLDS[id].title if WORLDS.has(id) else "Unavailable world"


static func default_id() -> String:
	if WORLDS.has("floating_island"):
		return "floating_island"
	return str(WORLDS.keys()[0]) if not WORLDS.is_empty() else ""
