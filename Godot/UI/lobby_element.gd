extends Node

signal joining_lobby(id)

var lobby

func _ready() -> void:
	%Button.connect("pressed", join_lobby)

	var lobby_new = LobbyClass.new()
	lobby_new.id = randi()
	lobby_new.player_count = randi_range(1,100)
	lobby = lobby_new

	self.name = str(lobby.id)
	get_child(1).get_child(0).text = str(lobby.id)
	get_child(1).get_child(1).text = str(lobby.player_count)

func join_lobby():
	%Button.text = "Joining!"
	emit_signal("joining_lobby", self.name)
	Networking.join_lobby(self.name)

class LobbyClass:
	var id: int
	var player_count: int
