extends MarginContainer

signal join_requested(room_id: int)

var room: roomClass


func _ready() -> void:
	%Button.pressed.connect(_join_room)
	set_room(room)


func set_room(value: roomClass) -> void:
	room = value
	if not is_node_ready() or room == null:
		return
	name = str(room.id)
	$room/roomID.text = "%s\n%s · #%d" % [room.room_name, WorldCatalog.title(room.world_id), room.id]
	$room/PlayerCount.text = "%d / 16" % room.player_count
	%Button.text = "Full" if room.player_count >= 16 else "Join";


func _join_room() -> void:
	join_requested.emit(room.id)


func set_available(available: bool) -> void:
	%Button.disabled = not available or room.player_count >= 16 or not WorldCatalog.WORLDS.has(room.world_id)
