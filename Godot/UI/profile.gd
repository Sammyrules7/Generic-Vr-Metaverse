class_name PlayerProfile
extends RefCounted

static var display_name := "Explorer"
static var world_id := "floating_island"
static var avatar_id := "default"
static var avatar_favorites: Array[String] = []
static var spring_bones_enabled := true
static var microphone_enabled := false
static var voice_volume := 0.8
static var input_gain := 1.0
static var input_device := "Default"
static var push_to_talk := false

static func restore() -> void:
	var config := ConfigFile.new()
	if config.load("user://profile.cfg") == OK:
		display_name = str(config.get_value("profile", "display_name", "Explorer")).strip_edges().left(24)
		world_id = str(config.get_value("profile", "world_id", "floating_island"))
		avatar_id = str(config.get_value("profile", "avatar_id", "default"))
		if not AvatarCatalog.has_avatar(avatar_id):
			# A dropped or renamed catalog entry must never wedge the avatar.
			avatar_id = "default"
		avatar_favorites.clear()
		var favorites = config.get_value("profile", "avatar_favorites", [])
		if favorites is Array:
			for favorite in favorites:
				if favorite is String and AvatarCatalog.has_avatar(favorite) and not favorite in avatar_favorites:
					avatar_favorites.append(favorite)
		spring_bones_enabled = bool(config.get_value("profile", "spring_bones_enabled", true))
		microphone_enabled = bool(config.get_value("voice", "microphone_enabled", false))
		voice_volume = clampf(float(config.get_value("voice", "volume", 0.8)), 0.0, 1.0)
		input_gain = clampf(float(config.get_value("voice", "input_gain", 1.0)), 0.0, 2.0)
		input_device = str(config.get_value("voice", "input_device", "Default"))
		push_to_talk = bool(config.get_value("voice", "push_to_talk", false))
	if display_name.is_empty():
		display_name = "Explorer"
	if not WorldCatalog.WORLDS.has(world_id):
		world_id = WorldCatalog.default_id()

static func save() -> Error:
	var config := ConfigFile.new()
	config.set_value("profile", "display_name", display_name)
	config.set_value("profile", "world_id", world_id)
	config.set_value("profile", "avatar_id", avatar_id)
	config.set_value("profile", "avatar_favorites", avatar_favorites)
	config.set_value("profile", "spring_bones_enabled", spring_bones_enabled)
	config.set_value("voice", "microphone_enabled", microphone_enabled)
	config.set_value("voice", "volume", voice_volume)
	config.set_value("voice", "input_gain", input_gain)
	config.set_value("voice", "input_device", input_device)
	config.set_value("voice", "push_to_talk", push_to_talk)
	return config.save("user://profile.cfg")
