extends Control

const ROOM_ELEMENT := preload("res://UI/room_element.tscn")
var room_networking: RoomNetworking


func _ready() -> void:
	room_networking = Networking.room_networking
	room_networking.rooms_replaced.connect(_replace_rooms)
	room_networking.room_updated.connect(_upsert_room)
	room_networking.room_removed.connect(_remove_room)
	room_networking.room_joined.connect(_room_joined)
	room_networking.room_left.connect(_room_left)
	room_networking.operation_started.connect(_operation_started)
	room_networking.operation_finished.connect(_operation_finished)
	Networking.signaling_connected.connect(_update_controls)
	Networking.signaling_disconnected.connect(_update_controls)
	Networking.network_error.connect(_show_error)
	%CreateRoom.pressed.connect(func(): _check_request(room_networking.create_room()))
	%LeaveRoom.pressed.connect(func(): _check_request(room_networking.leave_room()))
	_replace_rooms(room_networking.rooms.values())
	_update_controls()
	if room_networking.current_room != null:
		_room_joined(room_networking.current_room)
	else:
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
		placeholder.free()
	_add_room(room)


func _add_room(room: roomClass) -> void:
	var element = ROOM_ELEMENT.instantiate()
	element.room = room
	element.join_requested.connect(func(room_id: int): _check_request(room_networking.join_room(room_id)))
	%roomList.add_child(element)
	element.set_available(room_networking.connected and room_networking.pending_operation == RoomNetworking.Operation.NONE)


func _remove_room(room_id: int) -> void:
	var element := %roomList.get_node_or_null(str(room_id))
	if element != null:
		element.free()
	if %roomList.get_child_count() == 0:
		_show_placeholder("No rooms found. Create one!")


func _room_joined(_room: roomClass) -> void:
	$VBoxContainer.hide()
	%LeaveRoom.show()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _room_left() -> void:
	$VBoxContainer.show()
	%LeaveRoom.hide()
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _check_request(result: Error) -> void:
	if result != OK:
		_show_error(error_string(result))


func _operation_started(operation: RoomNetworking.Operation) -> void:
	_update_controls()
	_show_placeholder({RoomNetworking.Operation.CREATE: "Creating room...", RoomNetworking.Operation.JOIN: "Joining room...", RoomNetworking.Operation.LEAVE: "Leaving room..."}[operation])


func _operation_finished(_operation: RoomNetworking.Operation, success: bool, reason: String) -> void:
	_update_controls()
	if not success:
		_show_error(reason)
	else:
		_replace_rooms(room_networking.rooms.values())


func _update_controls() -> void:
	var available := room_networking.connected and room_networking.pending_operation == RoomNetworking.Operation.NONE
	%CreateRoom.disabled = not available
	%LeaveRoom.disabled = not available
	for element in %roomList.get_children():
		if element.has_method("set_available"):
			element.set_available(available)


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
