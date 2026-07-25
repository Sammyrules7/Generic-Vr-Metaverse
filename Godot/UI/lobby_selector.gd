extends Control

const lobby_element := preload("lobby_element.tscn")

var lobby_placeholder: bool = true


func _ready() -> void:
	Networking.connect("lobby_opend", lobby_created)

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if Networking.ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		%LobbyList.get_node("Placeholder").text = "An error occured"

	await get_tree().create_timer(5).timeout
	if lobby_placeholder:
		%LobbyList.get_node("Placeholder").text = "No lobbies found."

func lobby_created(lobby: LobbyClass) -> void:

	# Check if the lobby_placeholder is in place and remove if it is
	if lobby_placeholder:
		%LobbyList.get_node("Placeholder").queue_free()

	var lobby_element_instance: Node = lobby_element.instantiate()
	lobby_element_instance.lobby = lobby
	%LobbyList.add_child(lobby_element_instance)

func lobby_closed(id: int) -> void:
	%LobbyList.get_node(str(id)).queue_free()

func create_lobby() -> void:
	Networking.create_lobby()

func _exit_tree() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
