extends Control

const lobby_element := preload("lobby_element.tscn")

var lobby_placeholder: bool = true

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	lobby_created(null)
	Networking.connect("lobby_opend", lobby_created)
	for i in range(15):
		i += 1

		var lobby = LobbyClass.new()
		lobby.id = randi()
		lobby.playercount = randi_range(1,100)

		lobby_created(lobby)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func lobby_created(lobby):

	# Check if the lobby_placeholder is in place
	if lobby_placeholder:
		%LobbyList.get_node("Placeholder").queue_free()

	var lobby_element_instance: Node = lobby_element.instantiate()
	lobby_element_instance.lobby = lobby
	%LobbyList.add_child(lobby_element_instance)

func lobby_closed(id):
	%LobbyList.get_node(id).queue_free()

func create_lobby():
	Networking.create_lobby()

class LobbyClass:
	var id: int
	var playercount: int
