extends Node

signal joining_room(id: int)

var room: roomClass

func _ready() -> void:
	%Button.connect("pressed", join_room)

	if room == null:
		printerr("room element room was null")

	self.name = str(room.id)
	get_child(1).get_child(0).text = str(room.id)
	get_child(1).get_child(1).text = str(room.player_count)

func join_room() -> void:
	%Button.text = "Joining!"
	emit_signal("joining_room", self.name)
	Networking.join_room(int(self.name))
