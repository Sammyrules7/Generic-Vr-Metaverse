extends Node

class FocusedOpenXR extends XRInterfaceExtension:
	func _get_name() -> StringName:
		return &"OpenXR"

	func _is_initialized() -> bool:
		return true

	var pulses: Array = []

	func _trigger_haptic_pulse(action_name: String, tracker_name: StringName, frequency: float, amplitude: float, duration_sec: float, delay_sec: float) -> void:
		pulses.append([action_name, tracker_name, frequency, amplitude, duration_sec, delay_sec])

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
	ui.get_node("%InputGain").value = 125
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
	var action_map := load("res://openxr_action_map.tres") as OpenXRActionMap
	var quest_menu_found := false
	for interaction in action_map.interaction_profiles:
		for binding in interaction.bindings:
			check(not binding.binding_path.contains("/system/"), "Application binds a runtime system button")
			if interaction.interaction_profile_path == "/interaction_profiles/oculus/touch_controller" and binding.action.resource_name == "menu_button":
				check(binding.binding_path == "/user/hand/left/input/menu/click", "Quest app menu is not the left menu button")
				quest_menu_found = true
	check(quest_menu_found, "Quest left-menu binding is missing")
	ui.set_webxr_supported(false)
	ui.vr_mode = true
	check(ui.get_node("%VRModeText").text == "VR", "Native VR was labelled Desktop")
	ui.set_webxr_supported(false)
	check(ui.get_node("%VRModeText").text == "VR", "WebXR capability changed the active VR label")
	ui.vr_mode = false
	check(ui.get_node("%VRModeText").text == "Desktop", "Leaving VR did not update mode label")
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
	await _test_single_activation(ui, panel)
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
	game._controller_button_pressed("by_button", &"left_hand")
	check(state.pending_operation == RoomNetworking.Operation.NONE, "Furnishing B/Y button must not leave the room")
	game._controller_button_pressed("menu_button", &"right_hand")
	game._controller_button_pressed("select_button", &"left_hand")
	check(state.pending_operation == RoomNetworking.Operation.NONE, "System/right/select button must not leave the room")
	var start_xr := game.get_node("StartXR") as XRToolsStartXR
	var saved_interface := start_xr.xr_interface
	start_xr.xr_interface = FocusedOpenXR.new()
	game._disable_xr_lobby()
	check(not ui.menu_open and state.pending_operation == RoomNetworking.Operation.NONE, "Runtime dashboard/focus loss changed the app menu or left the room")
	start_xr.xr_interface = saved_interface
	game._controller_button_pressed("menu_button", &"left_hand")
	check(ui.menu_open and state.pending_operation == RoomNetworking.Operation.NONE and state.current_room != null, "Triple-line menu button must open UI without leaving the room")
	game._controller_button_pressed("menu_button", &"left_hand")
	check(not ui.menu_open and ui.get_node("QuickSession").visible, "Closing the menu did not restore compact VR UI")
	check(ui.xr_point_is_visible(ui.get_node("%InGameMicrophone").get_global_rect().get_center()), "Compact VR microphone is not touchable")
	ui.set_menu_open(true)
	ui.get_node("%OpenSessionVoiceSettings").pressed.emit()
	check(ui.get_node("%VoiceSettings").visible and not ui.get_node("Session").visible, "Session voice settings did not replace the room menu")
	check(is_equal_approx(ui.get_node("%InputGain").value, 145.0), "Shared voice form lost microphone gain after joining")
	ui.get_node("%VoiceVolume").value = 55
	check(is_equal_approx(Networking.voice_chat.output_volume, 0.55), "Session voice settings did not update playback")
	ui.get_node("%CloseVoiceSettings").pressed.emit()
	check(not ui.get_node("%VoiceSettings").visible and ui.get_node("Session").visible, "Closing session voice settings did not restore the room menu")
	ui.get_node("%OpenSessionVoiceSettings").pressed.emit()
	ui.set_menu_open(false)
	check(not ui.get_node("%VoiceSettings").visible and ui.get_node("QuickSession").visible, "Closing the room menu left voice settings open")

	check(not game.has_method("_hand_menu_gesture"), "Menu still has a hand gesture binding")
	await _test_immediate_touch(game, ui, panel)
	await _test_feedback(ui, panel)
	# Explicit leave remains quiet; an unsolicited server exit reports why.
	var room_errors: Array = []
	var capture_error := func(reason): room_errors.append(reason)
	state.network_error.connect(capture_error)
	var leave := Packets.ServerPacket.new()
	leave.new_room_left()
	state.pending_operation = RoomNetworking.Operation.LEAVE
	state.handle_packet(leave, 2)
	check(room_errors.is_empty(), "Explicit leave was reported as an unexpected exit")
	state.current_room = roomClass.new(20, "Unexpected exit", 1)
	state.pending_operation = RoomNetworking.Operation.NONE
	state.handle_packet(leave, 2)
	check(room_errors == ["The room server ended this session"], "Unexpected server exit did not provide a reason")
	state.network_error.disconnect(capture_error)
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
	# Flush stopped audio playbacks before shutting down the audio server.
	panel.click_audio.stop()
	game.get_node("World").queue_free()
	await get_tree().create_timer(0.08).timeout
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
	var touch := InputEventScreenTouch.new()
	touch.index = 7
	touch.position = world.get_global_rect().get_center()
	touch.pressed = true
	before = PlayerProfile.world_id
	nav._input(touch)
	var drag := InputEventScreenDrag.new()
	drag.index = touch.index
	drag.position = touch.position - Vector2(100, 0)
	nav._input(drag)
	touch.position = drag.position
	touch.pressed = false
	nav._input(touch)
	check(PlayerProfile.world_id != before and not nav._dragging, "Native touchscreen world swipe failed")
	before = PlayerProfile.world_id
	touch.pressed = true
	nav._input(touch)
	touch.pressed = false
	touch.canceled = true
	nav._input(touch)
	check(PlayerProfile.world_id == before and not nav._dragging, "Canceled native touch changed the selected world")
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
	check(not nav._dragging and clicks[0] == 1, "Pointer exit failed to cancel drag")
	await get_tree().create_timer(0.11).timeout
	var second_pointer := Node3D.new()
	panel.add_child(second_pointer)
	XRToolsPointerEvent.entered(pointer, target, start)
	XRToolsPointerEvent.pressed(pointer, target, start)
	XRToolsPointerEvent.moved(pointer, target, end, start)
	scroll.scroll_vertical = 0
	await get_tree().process_frame
	XRToolsPointerEvent.entered(second_pointer, target, start)
	XRToolsPointerEvent.pressed(second_pointer, target, start)
	XRToolsPointerEvent.released(second_pointer, target, start)
	XRToolsPointerEvent.released(pointer, target, start)
	await get_tree().process_frame
	check(clicks[0] == 2 and not nav._dragging, "Second pointer takeover repeated or lost the room tap")
	XRToolsPointerEvent.exited(second_pointer, target, start)
	second_pointer.queue_free()

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
	return panel.to_global(Vector3((point.x / 1120.0 - 0.5) * panel.screen_size.x, (0.5 - point.y / 800.0) * panel.screen_size.y, 0))


func _tap(panel: Node3D, button: BaseButton, pointer: Node3D) -> void:
	var point := _panel_point(panel, button.get_global_rect().get_center())
	var body := panel.get_node("StaticBody3D")
	XRToolsPointerEvent.entered(pointer, body, point)
	XRToolsPointerEvent.moved(pointer, body, point, point)
	XRToolsPointerEvent.pressed(pointer, body, point)
	XRToolsPointerEvent.released(pointer, body, point)
	XRToolsPointerEvent.exited(pointer, body, point)


func _test_single_activation(ui: Control, panel: Node3D) -> void:
	ui.vr_mode = true
	ui._set_keyboard_visible(false)
	ui._microphone_toggled(true)
	await get_tree().process_frame
	var mic: BaseButton = ui.get_node("%QuickMicrophoneEnabled")
	var count := [0]
	var capture := func(_value): count[0] += 1
	mic.toggled.connect(capture)
	_tap(panel, mic, panel.hand_contacts.right.pointer)
	check(count[0] == 1 and not PlayerProfile.microphone_enabled and Networking.voice_chat.muted, "One physical microphone tap must toggle exactly once")
	_tap(panel, mic, panel.hand_contacts.left.pointer)
	check(count[0] == 1 and Networking.voice_chat.muted, "Second-hand bounce within 100 ms toggled microphone again")
	await get_tree().create_timer(0.11).timeout
	_tap(panel, mic, panel.hand_contacts.left.pointer)
	check(count[0] == 2 and PlayerProfile.microphone_enabled and not Networking.voice_chat.muted, "Left-hand deliberate tap did not enable microphone")
	mic.toggled.disconnect(capture)
	var next: Button = ui.get_node("%NextWorld")
	var before: int = ui.world_index
	_tap(panel, next, panel.hand_contacts.right.pointer)
	check(ui.world_index == posmod(before + 1, WorldCatalog.WORLDS.size()), "One world-arrow tap must advance exactly one world")
	_tap(panel, next, panel.hand_contacts.left.pointer)
	check(ui.world_index == posmod(before + 1, WorldCatalog.WORLDS.size()), "World-arrow bounce within 100 ms was not suppressed")
	for index in 4:
		await get_tree().create_timer(0.11).timeout
		_tap(panel, next, panel.hand_contacts["left" if index % 2 == 0 else "right"].pointer)
		check(ui.world_index == posmod(before + index + 2, WorldCatalog.WORLDS.size()), "Rapid intentional world tap was dropped or doubled")
	var state: RoomNetworking = Networking.room_networking
	for path in ["%MicrophoneEnabled", "%SessionMicrophoneEnabled", "%InGameMicrophone"]:
		if path == "%MicrophoneEnabled":
			ui._set_voice_settings_open(true)
		else:
			ui._set_voice_settings_open(false)
			state.current_room = roomClass.new(20, "Microphone touch test", 1)
			ui.set_menu_open(path != "%InGameMicrophone")
		ui._microphone_toggled(true)
		await get_tree().process_frame
		mic = ui.get_node(path)
		check(mic.is_visible_in_tree(), "Microphone fixture is not visible: " + path)
		_tap(panel, mic, panel.hand_contacts.left.pointer)
		check(not PlayerProfile.microphone_enabled and Networking.voice_chat.muted, "Microphone did not mute on first contact: " + path)
		for other in ["%QuickMicrophoneEnabled", "%SessionMicrophoneEnabled", "%MicrophoneEnabled", "%InGameMicrophone"]:
			check(not ui.get_node(other).button_pressed, "Microphone state not synchronized: " + other)
		await get_tree().create_timer(0.11).timeout
		_tap(panel, mic, panel.hand_contacts.right.pointer)
		check(PlayerProfile.microphone_enabled and not Networking.voice_chat.muted, "Microphone did not enable on next contact: " + path)
	state.current_room = null
	ui.set_menu_open(true)
	ui._microphone_toggled(true)


func _test_immediate_touch(game: Node3D, ui: Control, panel: Node3D) -> void:
	var previous_panel = game.panel
	game.panel = panel
	game.xr_active = true
	game.set_process(false)
	var origin := XROrigin3D.new()
	game.add_child(origin)
	var head := XRCamera3D.new()
	origin.add_child(head)
	head.position.y = 1.7
	panel.bind_rig(origin, head)
	var tracker := XRHandTracker.new()
	tracker.name = "/user/hand_tracker/right"
	tracker.has_tracking_data = true
	tracker.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
	tracker.set_hand_joint_flags(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID)
	XRServer.add_tracker(tracker)
	var count := [0]
	var capture := func(): count[0] += 1
	panel.click_feedback.connect(capture)
	ui.set_menu_open(false)
	await get_tree().process_frame
	check(panel.visible and panel.enabled and panel.compact, "Compact UI disabled its physical panel")
	var button: Button = ui.get_node("%OpenRoomMenu")
	check(button.action_mode == BaseButton.ACTION_MODE_BUTTON_PRESS, "VR buttons still wait for finger release")
	var point: Vector3 = _panel_point(panel, button.get_global_rect().get_center())
	_set_tip(tracker, origin, point + panel.global_basis.z * 0.03)
	panel._process(0.0)
	_set_tip(tracker, origin, point + panel.global_basis.z * 0.005)
	panel._process(0.0)
	check(ui.menu_open, "Menu button did not activate immediately on fingertip contact")
	check(count[0] == 1, "Initial contact repeated its feedback during UI change")
	for frame in 5:
		panel._process(0.016)
	check(ui.menu_open and count[0] == 1 and not panel.hand_contacts.right.armed, "A resting finger repeated its action after menu change")
	tracker.has_tracking_data = false
	panel._process(0.0)
	tracker.has_tracking_data = true
	panel._process(0.0)
	check(count[0] == 1 and not panel.hand_contacts.right.armed, "Tracking loss repeated a resting finger click")
	_set_tip(tracker, origin, point + panel.global_basis.z * 0.06)
	panel._process(0.0)
	check(panel.hand_contacts.right.armed, "Production UI did not rearm after finger withdrawal")
	await get_tree().process_frame
	var left := XRHandTracker.new()
	left.name = "/user/hand_tracker/left"
	left.has_tracking_data = true
	left.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
	left.set_hand_joint_flags(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID)
	var mic: BaseButton = ui.get_node("%SessionMicrophoneEnabled")
	ui._microphone_toggled(true)
	var mic_point := _panel_point(panel, mic.get_global_rect().get_center())
	_set_tip(left, origin, mic_point + panel.global_basis.z * 0.014)
	XRServer.add_tracker(left)
	panel._process(0.0)
	_set_tip(left, origin, mic_point + panel.global_basis.z * 0.005)
	panel._process(0.0)
	check(count[0] == 2 and Networking.voice_chat.muted, "Tracked left fingertip did not toggle microphone once")
	_set_tip(tracker, origin, mic_point + panel.global_basis.z * 0.005)
	panel._process(0.0)
	check(count[0] == 2 and Networking.voice_chat.muted, "Tracked right fingertip bypassed same-button debounce")
	panel.release_touch()
	panel.click_feedback.disconnect(capture)
	game.xr_active = false
	game.panel = previous_panel
	game.set_process(true)
	XRServer.remove_tracker(tracker)
	XRServer.remove_tracker(left)
	origin.free()
	panel._process(0.0)


func _set_tip(tracker: XRHandTracker, origin: XROrigin3D, point: Vector3) -> void:
	var tracking_point := (origin.global_transform * XRServer.get_reference_frame()).affine_inverse() * point / XRServer.world_scale
	tracker.set_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, Transform3D(Basis.IDENTITY, tracking_point))


func _test_feedback(ui: Control, panel: Node3D) -> void:
	var count := [0]
	var capture := func(): count[0] += 1
	panel.click_feedback.connect(capture)
	var saved_interface := XRServer.primary_interface
	var interface := FocusedOpenXR.new()
	XRServer.add_interface(interface)
	XRServer.primary_interface = interface
	var tracker := XRControllerTracker.new()
	tracker.name = "left_hand"
	tracker.type = XRServer.TRACKER_CONTROLLER
	tracker.set_pose("default", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(tracker)
	var controller := XRController3D.new()
	controller.tracker = "left_hand"
	panel.add_child(controller)
	var pointer := Node3D.new()
	controller.add_child(pointer)
	panel.input_pointer = pointer
	check(controller.get_is_active(), "Feedback controller fixture is inactive")
	ui.vr_mode = true
	ui.get_node("%Resume").pressed.emit()
	check(count[0] == 1, "VR button did not produce click feedback")
	check(panel.click_audio.playing, "VR click tone did not play")
	check(interface.pulses.size() == 1 and interface.pulses[0] == ["haptic", &"left_hand", 0.0, 0.25, 0.035, 0.0], "VR feedback did not route a pulse to the selecting controller")
	ui.vr_mode = false
	ui.get_node("%Resume").pressed.emit()
	check(count[0] == 1, "Desktop button produced VR feedback")
	check(interface.pulses.size() == 1, "Desktop button triggered haptics")
	check(ui.get_node("%Resume").action_mode == BaseButton.ACTION_MODE_BUTTON_RELEASE, "Desktop action mode was not restored")
	ui.vr_mode = true
	panel.input_pointer = panel.hand_contacts.right.pointer
	ui.get_node("%Resume").pressed.emit()
	check(count[0] == 2 and interface.pulses.size() == 1, "Bare-hand clicks should play tone without controller haptics")
	panel.click_audio.stop()
	controller.free()
	XRServer.remove_tracker(tracker)
	XRServer.primary_interface = saved_interface
	XRServer.remove_interface(interface)
	panel.click_feedback.disconnect(capture)
