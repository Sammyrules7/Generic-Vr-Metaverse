extends Control

const room_element := preload("room_element.tscn")

var room_placeholder: bool = true


func _ready() -> void:
	Networking.connect("room_opend", room_created)

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if Networking.ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		%roomList.get_node("Placeholder").text = "An error occured"

	await get_tree().create_timer(5).timeout
	if room_placeholder:
		%roomList.get_node("Placeholder").text = "No lobbies found."

func room_created(room: roomClass) -> void:

	# Check if the room_placeholder is in place and remove if it is
	if room_placeholder:
		%roomList.get_node("Placeholder").queue_free()

	var room_element_instance: Node = room_element.instantiate()
	room_element_instance.room = room
	%roomList.add_child(room_element_instance)

func room_closed(id: int) -> void:
	%roomList.get_node(str(id)).queue_free()

func create_room() -> void:
	Networking.create_room()

func _exit_tree() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
