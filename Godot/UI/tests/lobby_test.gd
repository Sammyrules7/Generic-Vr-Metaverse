extends Node

const Packets = preload("res://Networking/Generated/Packets.gd")
var failed := false
var capture_viewport: SubViewport


func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func _ready() -> void:
	_run.call_deferred()


func _capture(path: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	capture_viewport.get_texture().get_image().save_png(path)


func _run() -> void:
	var profile_existed := FileAccess.file_exists("user://profile.cfg")
	var profile_backup := FileAccess.get_file_as_bytes("user://profile.cfg") if profile_existed else PackedByteArray()
	Networking.set_process(false)
	Networking.ws.close(-1)
	Networking.room_networking.reset()
	Networking.connection_message = "Server offline · Retrying automatically"
	var game = load("res://Main.tscn").instantiate()
	add_child(game)
	var ui = game.get_node("roomSelector")
	var registry := load(WorldCatalog.REGISTRY_PATH) as WorldRegistry
	check(registry != null and not registry.worlds.is_empty(), "Bundled world registry did not load")
	check(WorldCatalog.WORLDS.size() == 7 and WorldCatalog.WORLDS.has("moon_garden") and WorldCatalog.WORLDS.has("moonlit_grotto") and WorldCatalog.WORLDS.has("starlight_observatory") and WorldCatalog.WORLDS.has("blackthorn_house") and WorldCatalog.WORLDS.has("briarwick_manor"), "Bundled worlds are missing from the registry")
	ui._select_world(registry.worlds[0].id)
	for index in range(registry.worlds.size()):
		var definition: WorldDefinition = registry.worlds[index]
		check(ui.get_node("%WorldTitle").text == definition.title and ui.get_node("%WorldPreview").texture == definition.preview, "Carousel title and preview do not match registry")
		check(ui.get_node("%WorldPosition").text == "%d / %d" % [index + 1, registry.worlds.size()], "Carousel position is incorrect")
		ui.get_node("%NextWorld").pressed.emit()
	check(PlayerProfile.world_id == registry.worlds[0].id, "Carousel did not wrap forward")
	ui.get_node("%PreviousWorld").pressed.emit()
	check(PlayerProfile.world_id == registry.worlds[-1].id, "Carousel did not wrap backward")
	var custom_registry := WorldRegistry.new()
	var custom_world := WorldDefinition.new()
	custom_world.id = "custom_world"
	custom_world.title = "Custom world"
	custom_world.scene_path = registry.worlds[0].scene_path
	custom_registry.worlds.append(custom_world)
	var custom_lookup := WorldCatalog.read_registry(custom_registry)
	check(custom_lookup.has("custom_world") and custom_lookup.custom_world.preview == null, "Custom world without a preview should be usable")
	var original_worlds := WorldCatalog.WORLDS
	WorldCatalog.WORLDS = custom_lookup
	ui._select_world("custom_world")
	check(ui.get_node("%NextWorld").disabled and ui.get_node("%PreviousWorld").disabled, "Single-world carousel should disable navigation")
	check(ui.get_node("%PreviewPlaceholder").visible, "Missing preview should show a placeholder")
	WorldCatalog.WORLDS = {}
	ui._select_world("")
	ui._update_controls()
	check(ui.get_node("%WorldPosition").text == "0 / 0" and ui.get_node("%CreateRoom").disabled, "Empty registry should disable creation")
	WorldCatalog.WORLDS = original_worlds
	ui._select_world(registry.worlds[0].id)
	check(ui.find_child("ServerAddress", true, false) == null, "Server address must not be exposed in the UI")
	ui.get_node("%OpenVoiceSettings").pressed.emit()
	check(ui.get_node("%VoiceSettings").visible and not ui.get_node("VBoxContainer").visible, "Main-menu voice settings did not replace the room menu")
	check(ui.theme.has_stylebox("normal", "OptionButton") and ui.theme.has_stylebox("panel", "PopupMenu"), "Microphone selector does not use the menu theme")
	ui.get_node("%LobbyInputGain").value = 125
	check(is_equal_approx(PlayerProfile.input_gain, 1.25) and is_equal_approx(ui.get_node("%InputGain").value, 125.0), "Main-menu voice settings did not synchronize")
	ui.get_node("%CloseVoiceSettings").pressed.emit()
	check(not ui.get_node("%VoiceSettings").visible and ui.get_node("VBoxContainer").visible, "Main-menu voice settings did not return to the room menu")
	ui.get_node("%MicrophoneEnabled").button_pressed = false
	check(not PlayerProfile.microphone_enabled and Networking.voice_chat.muted, "Microphone control did not mute voice transmission")
	ui.get_node("%VoiceVolume").value = 35
	check(is_equal_approx(PlayerProfile.voice_volume, 0.35) and is_equal_approx(Networking.voice_chat.output_volume, 0.35), "Voice volume control did not update playback")
	ui.get_node("%InputGain").value = 145
	check(is_equal_approx(PlayerProfile.input_gain, 1.45) and is_equal_approx(Networking.voice_chat.input_gain, 1.45), "Microphone input level did not update")
	ui.get_node("%PushToTalk").button_pressed = true
	check(PlayerProfile.push_to_talk and Networking.voice_chat.push_to_talk, "Push-to-talk control did not update voice mode")
	check(ui.get_node("%InputDevice").item_count > 0, "Microphone device selector is empty")
	var panel = load("res://UI/vr_panel.tscn").instantiate()
	game.add_child(panel)
	capture_viewport = panel.get_node("Viewport")
	ui.reparent(capture_viewport)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var state: RoomNetworking = Networking.room_networking
	await get_tree().process_frame
	ui.get_node("%DisplayName").text = "Nova"
	ui.get_node("%RoomName").text = "Friday room"
	check(ui.get_node("%CreateRoom").disabled, "Offline create must be disabled")
	check(ui.get_node("%Connection").visible and ui.get_node("%Connection").text.contains("offline"), "Offline banner missing")
	check(state.create_room("offline") == ERR_UNAVAILABLE, "Offline requests must be rejected")
	await _capture("/tmp/lobby-offline.png")
	var sent: Array = []
	state.packet_created.disconnect(Networking._send)
	state.packet_created.connect(func(packet): sent.append(packet))
	state.connected = true
	Networking.connection_message = "Connected · Rooms update live"
	Networking.signaling_connected.emit()
	check(not ui.get_node("%Connection").visible, "Online connection status should be hidden")
	ui._select_world("moon_garden")
	ui.get_node("%CreateRoom").pressed.emit()
	check(sent.size() == 1, "Create should send exactly one command")
	check(sent[0].get_room_create().get_name() == "Friday room", "Room name missing from packet")
	check(sent[0].get_room_create().get_world_id() == "moon_garden", "World missing from packet")
	check(PlayerProfile.display_name == "Nova", "Chosen identity not applied")
	var reply := Packets.ServerPacket.new()
	reply.set_request_id(sent[0].get_request_id())
	reply.new_error().set_reason("Room rejected")
	state.handle_packet(reply, 2)
	check(not ui.get_node("%CreateRoom").disabled, "Create did not recover after rejection")
	check(ui.get_node("%Status").text == "Room rejected", "Error status missing")
	for room: roomClass in [roomClass.new(10, "The cloud club", 3), roomClass.new(11, "Late night lounge", 8, "moon_garden"), roomClass.new(12, "Full house", 16)]:
		state.rooms[room.id] = room
	state.rooms_replaced.emit(state.rooms.values())
	check(ui.get_node("%roomList/12/%Button").disabled, "Full rooms must be disabled")
	ui._set_status("")
	await _capture("/tmp/lobby-preview.png")
	ui.get_node("%Search").text = "moon"
	ui.get_node("%Search").text_changed.emit("moon")
	check(ui.get_node("%roomList").get_child_count() == 1, "World search failed")
	ui.get_node("%Search").text = ""
	ui.get_node("%Search").text_changed.emit("")
	await _test_navigation(ui, panel, state)
	ui.vr_mode = true
	# Exercise the same 3D pointer-to-Control path used by the controller laser.
	var pointer := Node3D.new()
	game.add_child(pointer)
	var target: Node3D = panel.get_node("StaticBody3D")
	var center: Vector2 = ui.get_node("%DisplayName").get_global_rect().get_center()
	var point: Vector3 = panel.to_global(Vector3((center.x / 1120.0 - 0.5) * panel.screen_size.x, (0.5 - center.y / 800.0) * panel.screen_size.y, 0))
	XRToolsPointerEvent.entered(pointer, target, point)
	XRToolsPointerEvent.pressed(pointer, target, point)
	XRToolsPointerEvent.released(pointer, target, point)
	await get_tree().process_frame
	check(ui.get_node("%DisplayName").has_focus(), "VR pointer did not focus the display name")
	ui.get_node("%DisplayName").select_all()
	ui._type_key("x")
	check(ui.get_node("%DisplayName").text == "x", "VR keyboard failed to replace selected text")
	ui._type_key("y")
	check(ui.get_node("%DisplayName").text == "xy", "VR keyboard kept a stale selection")
	check(ui.get_node("%Keyboard").visible, "VR keyboard did not open")
	state.current_room = roomClass.new(20, "Menu test", 1)
	ui.set_menu_open(false)
	game._controller_button_pressed("by_button")
	check(state.pending_operation == RoomNetworking.Operation.NONE, "Furnishing B/Y button must not leave the room")
	game._controller_button_pressed("menu_button")
	check(state.pending_operation == RoomNetworking.Operation.LEAVE, "Controller menu button did not leave the VR room")
	state.pending_operation = RoomNetworking.Operation.NONE
	state.current_room = null
	ui.set_menu_open(true)
	await _capture("/tmp/lobby-keyboard.png")
	ui._set_keyboard_visible(false)
	# The same allowlisted scene must load for every room member.
	var spawn: Marker3D = await game.load_world("moon_garden")
	check(spawn.get_parent().name == "World" and game.get_node("World/Floor") != null, "World choice did not load")
	spawn = await game.load_world("starlight_observatory")
	check(spawn.get_parent().name == "World" and game.get_node("World/StarGlobe") != null, "Starlight Observatory did not load from the registry")
	spawn = await game.load_world("moonlit_grotto")
	check(spawn.get_parent().name == "World" and game.get_node("World/Waterfall curtain") != null, "Moonlit Grotto did not load from the registry")
	# Mid-operation disconnect must clear pending actions and preserve entered fields.
	ui.get_node("%CreateRoom").pressed.emit()
	Networking.last_disconnect_reason = "Disconnected from signaling server"
	Networking.connection_message = "Server offline · Retrying automatically"
	state.reset()
	Networking.signaling_disconnected.emit()
	check(state.pending_operation == RoomNetworking.Operation.NONE and state.current_room == null, "Disconnect did not clear membership")
	check(ui.get_node("%CreateRoom").disabled and ui.get_node("%roomList").get_child_count() == 1, "Offline UI has stale rooms or active actions")
	check(ui.get_node("%RoomName").text == "Friday room", "Offline recovery lost room name")
	check(Networking.retry_connection("https://invalid") == ERR_INVALID_PARAMETER, "Invalid server address accepted")
	game.free()
	if profile_existed:
		FileAccess.open("user://profile.cfg", FileAccess.WRITE).store_buffer(profile_backup)
	else:
		DirAccess.remove_absolute("user://profile.cfg")
	print("Lobby tests: ", "FAIL" if failed else "PASS")
	get_tree().quit(1 if failed else 0)


func _test_navigation(ui: Control, panel: Node3D, state: RoomNetworking) -> void:
	var nav = ui.get_node("Navigation")
	var scroll: ScrollContainer = ui.get_node("%Scroll")
	check(ui.find_child("Paging", true, false) == null, "Scroll buttons should be removed")
	for index in range(20, 45):
		state.rooms[index] = roomClass.new(index, "Room %d" % index, 1)
	state.rooms_replaced.emit(state.rooms.values())
	await get_tree().process_frame
	await get_tree().process_frame
	var point := scroll.get_global_rect().get_center()
	var wheel := InputEventMouseButton.new()
	wheel.position = point
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.button_mask = 0
	capture_viewport.push_input(wheel, true)
	check(scroll.scroll_vertical > 0, "Desktop wheel did not scroll rooms")
	scroll.scroll_vertical = 0
	scroll.grab_focus()
	var key := InputEventKey.new()
	key.keycode = KEY_DOWN
	key.pressed = true
	for index in range(15):
		capture_viewport.push_input(key, true)
	check(scroll.scroll_vertical > 0, "Arrow navigation did not follow focused room")
	check(not capture_viewport.gui_get_focus_owner().disabled, "Arrow navigation selected a disabled room")
	var world: Control = ui.get_node("%WorldPreviewFrame")
	world.grab_focus()
	var before := PlayerProfile.world_id
	key.keycode = KEY_RIGHT
	capture_viewport.push_input(key, true)
	check(PlayerProfile.world_id != before, "Right arrow did not select world")
	before = PlayerProfile.world_id
	ui.get_node("%DisplayName").grab_focus()
	capture_viewport.push_input(key, true)
	check(PlayerProfile.world_id == before, "Text editing changed world")
	wheel.position = world.get_global_rect().get_center()
	capture_viewport.push_input(wheel, true)
	check(PlayerProfile.world_id != before, "World wheel navigation failed")
	wheel.pressed = false
	capture_viewport.push_input(wheel, true)
	ui.vr_mode = true
	ui._set_keyboard_visible(false)
	scroll.scroll_vertical = 0
	nav.handle_stick(Vector2(0, -0.2), point, 1.0)
	check(scroll.scroll_vertical == 0, "Joystick deadzone failed")
	nav.handle_stick(Vector2(0, -1), point, 0.5)
	check(scroll.scroll_vertical == 300, "Joystick room scroll failed")
	scroll.scroll_vertical = 0
	await get_tree().process_frame
	var join: Button = ui.get_node("%roomList/10/%Button")
	var clicks := [0]
	# Observe activation without initiating a network operation.
	for connection in join.pressed.get_connections():
		join.pressed.disconnect(connection.callable)
	join.pressed.connect(func(): clicks[0] += 1)
	var pointer := Node3D.new()
	panel.add_child(pointer)
	panel.pointer_event.connect(nav.pointer_event)
	var target: Node3D = panel.get_node("StaticBody3D")
	var center := join.get_global_rect().get_center()
	var start := _panel_point(panel, center)
	var end := _panel_point(panel, center - Vector2(0, 100))
	XRToolsPointerEvent.entered(pointer, target, start)
	XRToolsPointerEvent.pressed(pointer, target, start)
	XRToolsPointerEvent.moved(pointer, target, end, start)
	XRToolsPointerEvent.released(pointer, target, end)
	check(scroll.scroll_vertical >= 99 and clicks[0] == 0, "VR drag activated Join or failed to scroll")
	scroll.scroll_vertical = 0
	await get_tree().process_frame
	XRToolsPointerEvent.moved(pointer, target, start, end)
	XRToolsPointerEvent.pressed(pointer, target, start)
	XRToolsPointerEvent.released(pointer, target, start)
	await get_tree().process_frame
	check(clicks[0] == 1, "VR tap must activate Join exactly once")
	XRToolsPointerEvent.pressed(pointer, target, start)
	XRToolsPointerEvent.exited(pointer, target, start)
	check(nav._touch_index == -1 and clicks[0] == 1, "Pointer exit failed to cancel drag")
	before = PlayerProfile.world_id
	var world_point := world.get_global_rect().get_center()
	nav.handle_stick(Vector2.RIGHT, world_point, 0.01)
	check(PlayerProfile.world_id != before, "Joystick world navigation failed")
	var selected := PlayerProfile.world_id
	nav.handle_stick(Vector2.RIGHT, world_point, 0.1)
	check(PlayerProfile.world_id == selected, "Joystick world repeat was too fast")
	start = _panel_point(panel, world_point)
	end = _panel_point(panel, world_point - Vector2(100, 0))
	XRToolsPointerEvent.entered(pointer, target, start)
	XRToolsPointerEvent.pressed(pointer, target, start)
	XRToolsPointerEvent.moved(pointer, target, end, start)
	XRToolsPointerEvent.released(pointer, target, end)
	check(PlayerProfile.world_id != selected, "VR world swipe failed")
	XRToolsPointerEvent.exited(pointer, target, end)
	pointer.free()
	for index in range(20, 45):
		state.rooms.erase(index)
	state.rooms_replaced.emit(state.rooms.values())
	await get_tree().process_frame


func _panel_point(panel: Node3D, point: Vector2) -> Vector3:
	return panel.to_global(Vector3((point.x / 1120.0 - 0.5) * 2.24, (0.5 - point.y / 800.0) * 1.6, 0))
