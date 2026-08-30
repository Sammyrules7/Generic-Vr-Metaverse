extends Control

const ROOM_ELEMENT := preload("res://UI/room_element.tscn")


func _ready() -> void:
	Networking.rooms_replaced.connect(_replace_rooms)
	Networking.room_updated.connect(_upsert_room)
	Networking.room_removed.connect(_remove_room)
	Networking.room_joined.connect(_room_joined)
	Networking.room_left.connect(_room_left)
	Networking.network_error.connect(_show_error)
	%CreateRoom.pressed.connect(func(): Networking.create_room())
	_replace_rooms(Networking.rooms.values())
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _replace_rooms(rooms: Array) -> void:
	for child in %roomList.get_children():
		child.free()
	for room in rooms:
		_add_room(room)
	if rooms.is_empty():
		_show_placeholder("No rooms found. Create one!")


func _upsert_room(room: roomClass) -> void:
	var existing := %roomList.get_node_or_null(str(room.id))
	if existing != null:
		existing.set_room(room)
		return
	var placeholder := %roomList.get_node_or_null("Placeholder")
	if placeholder != null:
		placeholder.queue_free()
	_add_room(room)


func _add_room(room: roomClass) -> void:
	var element = ROOM_ELEMENT.instantiate()
	element.room = room
	%roomList.add_child(element)


func _remove_room(room_id: int) -> void:
	var element := %roomList.get_node_or_null(str(room_id))
	if element != null:
		element.queue_free()


func _room_joined(_room: roomClass) -> void:
	hide()


func _room_left() -> void:
	show()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _show_error(reason: String) -> void:
	_show_placeholder(reason)


func _show_placeholder(text: String) -> void:
	var placeholder := %roomList.get_node_or_null("Placeholder")
	if placeholder == null:
		placeholder = Label.new()
		placeholder.name = "Placeholder"
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		%roomList.add_child(placeholder)
	placeholder.text = text
