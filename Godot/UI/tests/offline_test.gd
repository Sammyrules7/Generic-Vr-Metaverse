extends Node

var failed := false


func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func _ready() -> void:
	_run.call_deferred()


func _wait_until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return condition.call()


func _run() -> void:
	var profile_existed := FileAccess.file_exists("user://profile.cfg")
	var profile_backup := FileAccess.get_file_as_bytes("user://profile.cfg") if profile_existed else PackedByteArray()
	var server_existed := FileAccess.file_exists("user://server.cfg")
	var server_backup := FileAccess.get_file_as_bytes("user://server.cfg") if server_existed else PackedByteArray()
	var actual_server := Networking.ws_url
	var game = load("res://Main.tscn").instantiate()
	add_child(game)
	var ui = game.get_node("roomSelector")
	ui.get_node("%DisplayName").text = "Offline explorer"
	ui.get_node("%RoomName").text = "Keep this room name"
	Networking.retry_connection("ws://127.0.0.1:1/ws")
	check(await _wait_until(func(): return Networking.connection_message.contains("offline")), "Unreachable server did not become offline")
	var deadline := Networking.connect_deadline
	await get_tree().create_timer(2.3).timeout
	check(Networking.connect_deadline > deadline, "Offline connection did not retry automatically")
	check(ui.get_node("%CreateRoom").disabled, "Offline room creation is enabled")
	check(ui.get_node("%Connection").text.contains("offline"), "Offline banner not updated")
	Networking.retry_connection(actual_server)
	check(await _wait_until(func(): return Networking.room_networking.connected), "Failed to recover when server returned")
	check(not ui.get_node("%CreateRoom").disabled, "Room actions did not recover")
	check(not ui.get_node("%Connection").visible, "Connection status remained visible online")
	check(ui.get_node("%RoomName").text == "Keep this room name", "Reconnect erased form state")
	Networking.room_networking.create_room("Disconnect test", "moon_garden")
	check(await _wait_until(func(): return Networking.room_networking.current_room != null), "Test room did not open")
	var player: NetworkPlayer = game.get_node("PlayerManager").local_player
	var mesh: WebRTCMesh = Networking.room_networking.rtc_mesh
	var original_room: roomClass = Networking.room_networking.current_room
	Networking.ws.close(-1)
	check(await _wait_until(func(): return not Networking.room_networking.connected), "Disconnect was not detected")
	check(game.get_node("PlayerManager").local_player == player and Networking.room_networking.rtc_mesh == mesh and Networking.room_networking.current_room == original_room, "Control-plane loss destroyed the live room")
	check(not ui.menu_open and player.controls.input_enabled and not ui.get_node("VBoxContainer").visible, "Control-plane loss interrupted gameplay")
	check(ui.get_node("%ControlPlaneNotice").visible and not ui.get_node("%LeaveRoom").disabled, "Control-plane notice or offline leave action missing")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/control-plane-offline.png")
	check(await _wait_until(func(): return Networking.room_networking.connected), "Session disconnect did not reconnect")
	check(not ui.get_node("%ControlPlaneNotice").visible and Networking.room_networking.rtc_mesh == mesh and game.get_node("PlayerManager").local_player == player, "Reconnect replaced the live session or retained its warning")
	# A TCP connection without the protocol handshake must also time out.
	Networking.client_id = 0
	Networking.connect_deadline = Time.get_ticks_msec() - 1
	check(await _wait_until(func(): return Networking.connection_message.contains("offline")), "Missing handshake did not time out")
	check(Networking.room_networking.leave_room() == OK, "Explicit offline leave was rejected")
	check(Networking.room_networking.current_room == null and game.get_node("PlayerManager").local_player == null and ui.get_node("VBoxContainer").visible, "Explicit offline leave did not return to lobby")
	game.free()
	Networking.set_process(false)
	Networking.ws.close(-1)
	if server_existed:
		FileAccess.open("user://server.cfg", FileAccess.WRITE).store_buffer(server_backup)
	else:
		DirAccess.remove_absolute("user://server.cfg")
	if profile_existed:
		FileAccess.open("user://profile.cfg", FileAccess.WRITE).store_buffer(profile_backup)
	else:
		DirAccess.remove_absolute("user://profile.cfg")
	print("Offline/reconnect tests: ", "FAIL" if failed else "PASS")
	get_tree().quit(1 if failed else 0)
