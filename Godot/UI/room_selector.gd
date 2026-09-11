extends Control

signal menu_changed(open: bool)
signal control_plane_warning_changed(message: String)
signal xr_requested

const ROOM_ELEMENT := preload("res://UI/room_element.tscn")
var room_networking: RoomNetworking
var vr_mode := false
var menu_open := true
var keyboard_target: LineEdit
var uppercase := false
var world_index := 0
var disconnect_status := false
var control_plane_warning := ""


func _ready() -> void:
	_apply_theme()
	get_viewport().size_changed.connect(_fit_ui)
	_fit_ui()
	PlayerProfile.restore()
	%DisplayName.text = PlayerProfile.display_name
	%DisplayName.focus_exited.connect(_remember_preferences)
	%PreviousWorld.pressed.connect(func(): _step_world(-1))
	%NextWorld.pressed.connect(func(): _step_world(1))
	_select_world(PlayerProfile.world_id)
	_build_keyboard()
	for field: LineEdit in [%DisplayName, %RoomName, %Search]:
		field.focus_entered.connect(func():
			keyboard_target = field
			_set_keyboard_visible(vr_mode)
		)
	room_networking = Networking.room_networking
	room_networking.rooms_replaced.connect(_replace_rooms)
	room_networking.room_updated.connect(_upsert_room)
	room_networking.room_removed.connect(_remove_room)
	room_networking.room_joined.connect(_room_joined)
	room_networking.room_left.connect(_room_left)
	room_networking.operation_started.connect(_operation_started)
	room_networking.operation_finished.connect(_operation_finished)
	Networking.signaling_connected.connect(_on_connected)
	Networking.signaling_disconnected.connect(_update_controls)
	Networking.network_error.connect(_show_error)
	multiplayer.peer_connected.connect(func(_peer): _refresh_session_count())
	multiplayer.peer_disconnected.connect(func(_peer): _refresh_session_count())
	%CreateRoom.pressed.connect(_create_room)
	%LeaveRoom.pressed.connect(func(): _check_request(room_networking.leave_room()))
	%Resume.pressed.connect(func(): set_menu_open(false))
	%Search.text_changed.connect(func(_text): _replace_rooms(room_networking.rooms.values()))
	%DisplayName.text_changed.connect(func(_text): _update_controls())
	%RoomName.text_submitted.connect(func(_text): _create_room())
	_replace_rooms(room_networking.rooms.values())
	_update_controls()
	if room_networking.current_room != null:
		_room_joined(room_networking.current_room)


func _apply_theme() -> void:
	var ui_theme := Theme.new()
	ui_theme.default_font_size = 18
	for type: String in ["Button", "LineEdit", "PanelContainer"]:
		for state: String in (["normal", "hover", "pressed", "disabled", "focus"] if type == "Button" else ["normal", "focus"] if type == "LineEdit" else ["panel"]):
			var style := StyleBoxFlat.new()
			style.bg_color = Color("#142237") if type == "PanelContainer" else Color("#21344b")
			if state in ["hover", "pressed"]:
				style.bg_color = Color("#354e65")
			style.set_corner_radius_all(8)
			style.content_margin_left = 16
			style.content_margin_right = 16
			style.content_margin_top = 12
			style.content_margin_bottom = 12
			if state == "focus":
				style.bg_color = Color.TRANSPARENT
				style.set_border_width_all(2)
				style.border_color = Color("#a0bdd4")
			ui_theme.set_stylebox(state, type, style)
	ui_theme.set_color("font_color", "Label", Color("#dce7f4"))
	ui_theme.set_color("font_disabled_color", "Button", Color("#74869a"))
	theme = ui_theme
	var primary := ui_theme.get_stylebox("normal", "Button").duplicate() as StyleBoxFlat
	primary.bg_color = Color("#a0bdd4")
	%CreateRoom.add_theme_stylebox_override("normal", primary)
	%CreateRoom.add_theme_color_override("font_color", Color("#162838"))
	var preview_frame := StyleBoxFlat.new()
	preview_frame.bg_color = Color("#21344b")
	preview_frame.set_corner_radius_all(14)
	%WorldPreviewFrame.add_theme_stylebox_override("panel", preview_frame)


func _fit_ui() -> void:
	# Keep the full lobby visible in narrow Quest browser windows while retaining
	# the authored size in the fixed-resolution in-headset viewport.
	var available := get_viewport_rect().size
	theme.default_base_scale = clampf(minf(available.x / 1120.0, available.y / 800.0), 0.65, 1.0)


func _select_world(id: String) -> void:
	var ids := WorldCatalog.WORLDS.keys()
	%PreviousWorld.disabled = ids.size() <= 1
	%NextWorld.disabled = ids.size() <= 1
	if not WorldCatalog.WORLDS.has(id):
		%WorldTitle.text = "Worlds"
		%WorldDescription.text = "No worlds configured."
		%WorldPreview.texture = null
		%PreviewPlaceholder.show()
		%WorldPosition.text = "0 / 0"
		return
	world_index = ids.find(id)
	PlayerProfile.world_id = id
	%WorldTitle.text = WorldCatalog.title(id)
	%WorldDescription.text = WorldCatalog.WORLDS[id].description
	%WorldPreview.texture = WorldCatalog.WORLDS[id].preview
	%PreviewPlaceholder.visible = %WorldPreview.texture == null
	%WorldPosition.text = "%d / %d" % [world_index + 1, ids.size()]
	_remember_preferences()


func _step_world(direction: int) -> void:
	var ids := WorldCatalog.WORLDS.keys()
	if ids.size() > 1:
		_select_world(ids[posmod(world_index + direction, ids.size())])


func _remember_preferences() -> void:
	var value: String = %DisplayName.text.strip_edges()
	if not value.is_empty():
		PlayerProfile.display_name = value
		PlayerProfile.save()


func _save_identity() -> bool:
	var value: String = %DisplayName.text.strip_edges()
	if value.is_empty():
		_show_error("Enter a display name first.")
		%DisplayName.grab_focus()
		return false
	PlayerProfile.display_name = value
	if PlayerProfile.save() != OK:
		_show_error("Your name will work this session, but preferences could not be saved.")
	return true


func _create_room() -> void:
	if not WorldCatalog.WORLDS.has(PlayerProfile.world_id):
		_show_error("No world selected.")
		return
	if not _save_identity():
		return
	var room_name: String = %RoomName.text.strip_edges()
	if room_name.is_empty():
		room_name = PlayerProfile.display_name
		while room_name.to_utf8_buffer().size() > 41:
			room_name = room_name.left(room_name.length() - 1)
		room_name += "'s room"
	if room_name.to_utf8_buffer().size() > 48:
		_show_error("Please shorten the room name; emoji and some letters use more of the limit.")
		return
	%CreateRoom.text = "Creating room…"
	%CreateRoom.disabled = true
	# WebXR initialization must happen directly inside a user gesture.
	xr_requested.emit()
	_check_request(room_networking.create_room(room_name, PlayerProfile.world_id))


func _replace_rooms(rooms: Array) -> void:
	var focus := get_viewport().gui_get_focus_owner()
	var focus_path := %roomList.get_path_to(focus) if focus != null and %roomList.is_ancestor_of(focus) else NodePath()
	for child in %roomList.get_children():
		child.free()
	var query: String = %Search.text.strip_edges().to_lower()
	for room: roomClass in rooms:
		if query.is_empty() or (room.room_name + " " + WorldCatalog.title(room.world_id)).to_lower().contains(query):
			_add_room(room)
	if not focus_path.is_empty():
		var replacement := %roomList.get_node_or_null(focus_path) as Button
		if replacement != null and not replacement.disabled:
			replacement.grab_focus()
		else:
			%Scroll.grab_focus()
	if %roomList.get_child_count() == 0:
		var message := "No rooms available.\nCreate a room to start a session."
		if not room_networking.connected:
			message = "Rooms will appear when the server reconnects.\nYou can still set up your name and world."
		elif not query.is_empty():
			message = "No matching rooms."
		_show_placeholder(message)


func _upsert_room(_room: roomClass) -> void:
	_replace_rooms(room_networking.rooms.values())
	if room_networking.current_room != null:
		_update_session()


func _add_room(room: roomClass) -> void:
	var element = ROOM_ELEMENT.instantiate()
	element.room = room
	element.join_requested.connect(func(room_id: int):
		if _save_identity():
			_check_request(room_networking.join_room(room_id))
	)
	%roomList.add_child(element)
	element.set_available(_available())


func _remove_room(_room_id: int) -> void:
	_replace_rooms(room_networking.rooms.values())


func _room_joined(_room: roomClass) -> void:
	_set_keyboard_visible(false)
	_update_session()
	set_menu_open(false)
	_update_controls()


func _update_session() -> void:
	var room := room_networking.current_room
	%SessionInfo.text = "%s\n%s · %d people" % [room.room_name, WorldCatalog.title(room.world_id), multiplayer.get_peers().size() + 1]


func _refresh_session_count() -> void:
	if room_networking.current_room != null:
		_update_session()


func _room_left() -> void:
	%SessionStatus.text = ""
	set_menu_open(true)
	_update_controls()


func set_menu_open(open: bool) -> void:
	menu_open = open
	var in_room := room_networking.current_room != null
	$VBoxContainer.visible = not in_room
	$Session.visible = in_room and open
	$MenuHint.visible = in_room and not open and not vr_mode
	if vr_mode:
		$Session.set_anchors_preset(Control.PRESET_CENTER)
		$Session.offset_left = -260
		$Session.offset_top = -150
		$Session.offset_right = 260
		$Session.offset_bottom = 150
	$Background.visible = not in_room or (vr_mode and open)
	mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
	if not vr_mode:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED)
	menu_changed.emit(open)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("exit") and room_networking.current_room != null:
		set_menu_open(not menu_open)
		get_viewport().set_input_as_handled()


func _check_request(result: Error) -> void:
	if result != OK:
		_show_error(error_string(result))
		_update_controls()


func _operation_started(operation: RoomNetworking.Operation) -> void:
	_update_controls()
	_set_status({RoomNetworking.Operation.CREATE: "Creating room…", RoomNetworking.Operation.JOIN: "Joining room…", RoomNetworking.Operation.LEAVE: "Leaving room…"}[operation])


func _operation_finished(_operation: RoomNetworking.Operation, success: bool, reason: String) -> void:
	_update_controls()
	if not success:
		_show_error(reason)
	else:
		_set_status("")
		_replace_rooms(room_networking.rooms.values())


func _available() -> bool:
	return room_networking.connected and room_networking.pending_operation == RoomNetworking.Operation.NONE


func _update_controls() -> void:
	var available := _available()
	%CreateRoom.text = "Creating room…" if room_networking.pending_operation == RoomNetworking.Operation.CREATE else "Create room"
	%Connection.visible = not room_networking.connected
	%Connection.text = Networking.connection_message
	%Connection.add_theme_color_override("font_color", Color("#a0bdd4") if room_networking.connected else Color("#f5bc79"))
	%CreateRoom.disabled = not available or %DisplayName.text.strip_edges().is_empty() or WorldCatalog.WORLDS.is_empty()
	%LeaveRoom.disabled = room_networking.current_room == null or room_networking.pending_operation != RoomNetworking.Operation.NONE
	var warning := "Control plane offline\nPeer-to-peer session continues" if room_networking.current_room != null and not room_networking.connected else ""
	%ControlPlaneNotice.visible = not warning.is_empty() and not vr_mode
	%ControlPlaneText.text = warning
	if warning != control_plane_warning:
		control_plane_warning = warning
		control_plane_warning_changed.emit(warning)
	%DisplayName.editable = room_networking.pending_operation == RoomNetworking.Operation.NONE
	%RoomName.editable = %DisplayName.editable
	for element in %roomList.get_children():
		if element.has_method("set_available"):
			element.set_available(available and not %DisplayName.text.strip_edges().is_empty())


func _on_connected() -> void:
	if disconnect_status:
		_set_status("")
		disconnect_status = false
	_update_controls()


func _set_status(message: String) -> void:
	%Status.visible = not message.is_empty()
	%SessionStatus.visible = not message.is_empty()
	%Status.text = message
	%SessionStatus.text = message


func _show_error(reason: String) -> void:
	disconnect_status = not room_networking.connected
	_set_status(reason)


func _show_placeholder(message: String) -> void:
	var placeholder := Label.new()
	placeholder.name = "Placeholder"
	placeholder.text = message
	placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	placeholder.custom_minimum_size.y = 100
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	%roomList.add_child(placeholder)


func _build_keyboard() -> void:
	for letters: String in ["1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm-'", ".:/"]:
		var row := HBoxContainer.new()
		%Keyboard.add_child(row)
		for letter: String in letters:
			var key := Button.new()
			key.text = letter
			key.focus_mode = Control.FOCUS_NONE
			key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			key.pressed.connect(func(): _type_key(letter.to_upper() if uppercase else letter))
			row.add_child(key)
	var actions := HBoxContainer.new()
	%Keyboard.add_child(actions)
	for action: String in ["Shift", "Space", "Backspace", "Done"]:
		var key := Button.new()
		key.text = action
		key.focus_mode = Control.FOCUS_NONE
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key.pressed.connect(func():
			if action == "Done":
				_set_keyboard_visible(false)
			elif action == "Shift":
				uppercase = not uppercase
				key.text = "SHIFT" if uppercase else "Shift"
			elif action == "Space":
				_type_key(" ")
			elif is_instance_valid(keyboard_target) and keyboard_target.editable:
				keyboard_target.grab_focus()
				if keyboard_target.has_selection():
					_delete_selection()
				else:
					var caret := keyboard_target.caret_column
					keyboard_target.delete_text(maxi(0, caret - 1), caret)
				keyboard_target.text_changed.emit(keyboard_target.text)
		)
		actions.add_child(key)


func _type_key(value: String) -> void:
	if is_instance_valid(keyboard_target) and keyboard_target.editable:
		keyboard_target.grab_focus()
		if keyboard_target.has_selection():
			_delete_selection()
		keyboard_target.insert_text_at_caret(value)
		keyboard_target.deselect()
		keyboard_target.text_changed.emit(keyboard_target.text)


func _delete_selection() -> void:
	var start := keyboard_target.get_selection_from_column()
	keyboard_target.delete_text(start, keyboard_target.get_selection_to_column())
	keyboard_target.deselect()
	keyboard_target.caret_column = start


func _set_keyboard_visible(show_keyboard: bool) -> void:
	%Keyboard.visible = show_keyboard
	%Search.visible = not show_keyboard or keyboard_target == %Search
	%Scroll.visible = not show_keyboard
	%BrowseTitle.text = "Type " + str(keyboard_target.name).to_snake_case().replace("_", " ") if show_keyboard and keyboard_target != null else "Available rooms"
