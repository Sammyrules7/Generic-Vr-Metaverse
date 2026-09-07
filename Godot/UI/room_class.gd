class_name roomClass extends RefCounted

var id: int
var room_name: String
var player_count: int
var world_id: String

func _init(init_id: int, init_name: String, init_player_count: int, init_world_id := "floating_island") -> void:
	id = init_id
	room_name = init_name
	player_count = init_player_count
	world_id = init_world_id if not init_world_id.is_empty() else "floating_island"
