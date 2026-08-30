extends MarginContainer

var room: roomClass


func _ready() -> void:
	%Button.pressed.connect(_join_room)
	set_room(room)


func set_room(value: roomClass) -> void:
	room = value
	if not is_node_ready() or room == null:
		return
	name = str(room.id)
	$room/roomID.text = "%s (#%d)" % [room.room_name, room.id]
	$room/PlayerCount.text = "%d / 16" % room.player_count
	%Button.text = "Join"


func _join_room() -> void:
	%Button.text = "Joining..."
	Networking.join_room(room.id)
