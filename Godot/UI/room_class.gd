class_name roomClass extends RefCounted

var id: int
var player_count: int

func _init(init_id: int, init_player_count: int) -> void:
	id = init_id
	player_count = init_player_count
