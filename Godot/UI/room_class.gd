class_name roomClass extends RefCounted

var id: int
var room_name: String
var player_count: int

func _init(init_id: int, init_name: String, init_player_count: int) -> void:
	id = init_id
	room_name = init_name
	player_count = init_player_count
