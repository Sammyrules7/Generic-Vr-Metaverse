class_name PlayerProfile
extends RefCounted

static var display_name := "Explorer"
static var world_id := "floating_island"

static func restore() -> void:
	var config := ConfigFile.new()
	if config.load("user://profile.cfg") == OK:
		display_name = str(config.get_value("profile", "display_name", "Explorer")).strip_edges().left(24)
		world_id = str(config.get_value("profile", "world_id", "floating_island"))
	if display_name.is_empty():
		display_name = "Explorer"
	if not WorldCatalog.WORLDS.has(world_id):
		world_id = WorldCatalog.default_id()

static func save() -> Error:
	var config := ConfigFile.new()
	config.set_value("profile", "display_name", display_name)
	config.set_value("profile", "world_id", world_id)
	return config.save("user://profile.cfg")
