extends Node

signal joining_lobby(id: int)

var lobby: LobbyClass

func _ready() -> void:
	%Button.connect("pressed", join_lobby)

	if lobby == null:
		printerr("Lobby element lobby was null")

	self.name = str(lobby.id)
	get_child(1).get_child(0).text = str(lobby.id)
	get_child(1).get_child(1).text = str(lobby.player_count)

func join_lobby() -> void:
	%Button.text = "Joining!"
	emit_signal("joining_lobby", self.name)
	Networking.join_lobby(int(self.name))
