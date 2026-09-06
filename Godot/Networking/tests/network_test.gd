extends Node

const Network = preload("res://Networking/Networking.gd")
const Packets = preload("res://Networking/Generated/Packets.gd")
var failures: Array[String] = []
@onready var root := get_tree().root


func quit(code := 0) -> void:
	get_tree().quit(code)


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> bool:
	if not condition:
		push_error(description)
		quit(1)
	return condition


func _client(client_name: String) -> Node:
	var branch := Node3D.new()
	branch.name = client_name
	root.add_child(branch)
	var api := SceneMultiplayer.new()
	api.root_path = branch.get_path()
	get_tree().set_multiplayer(api, branch.get_path())
	var client := Network.new()
	client.name = "Networking"
	client.network_error.connect(func(reason: String):
		push_error(reason)
		quit(1)
	)
	branch.add_child(client)
	client.room_networking.operation_finished.connect(func(_op, success: bool, reason: String):
		if not success:
			failures.append(reason)
	)
	client.room_networking.room_joined.connect(func(room: roomClass):
		var state: RoomNetworking = client.room_networking
		_check(state.current_room == room and state.rtc_mesh != null and state.multiplayer.multiplayer_peer == state.rtc_mesh.multiplayer_peer, "Join signal preceded room state")
	)
	client.room_networking.room_left.connect(func():
		var state: RoomNetworking = client.room_networking
		_check(state.current_room == null and state.rtc_mesh == null and state.multiplayer.multiplayer_peer is OfflineMultiplayerPeer, "Leave signal preceded cleanup")
	)
	var players := Node3D.new()
	players.name = "Players"
	branch.add_child(players)
	var spawn := Marker3D.new()
	spawn.name = "SpawnPoint"
	branch.add_child(spawn)
	_manager(client)
	return client


func _manager(client: Node) -> PlayerManager:
	var branch := client.get_parent()
	var manager := PlayerManager.new()
	manager.name = "PlayerManager"
	manager.players = branch.get_node("Players")
	manager.spawn_point = branch.get_node("SpawnPoint")
	manager.room_networking = client.room_networking
	manager.replication = client.player_replication
	branch.add_child(manager)
	return manager


func _wait_until(condition: Callable, description: String) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while not condition.call():
		if Time.get_ticks_msec() >= deadline:
			return _check(false, "Timed out: " + description)
		await get_tree().process_frame
	return true


func _idle(client: Node) -> bool:
	return await _wait_until(func(): return client.room_networking.pending_operation == RoomNetworking.Operation.NONE, "room operation reply")


func _check_room_ui() -> bool:
	var network := root.get_node("Networking")
	var original: RoomNetworking = network.room_networking
	var state := RoomNetworking.new(SceneMultiplayer.new())
	state.connected = true
	network.room_networking = state
	var sent: Array = []
	state.packet_created.connect(func(packet): sent.append(packet))
	var ui: Control = load("res://UI/room_selector.tscn").instantiate()
	root.add_child(ui)
	ui.get_node("%CreateRoom").pressed.emit()
	var busy: bool = ui.get_node("%CreateRoom").disabled and sent.size() == 1
	var reply := Packets.ServerPacket.new()
	reply.set_request_id(sent[0].get_request_id() + 1)
	reply.new_error().set_reason("Room rejected")
	state.handle_packet(reply, 2)
	busy = busy and ui.get_node("%CreateRoom").disabled
	reply.set_request_id(sent[0].get_request_id())
	state.handle_packet(reply, 2)
	var recovered: bool = not ui.get_node("%CreateRoom").disabled and ui.get_node("%roomList/Placeholder").text == "Room rejected"
	ui.free()
	network.room_networking = original
	return _check(busy and recovered, "Room UI did not disable pending actions or recover after failure")


func _run() -> void:
	root.get_node("Networking").set_process(false)
	root.get_node("Networking").ws.close(-1)
	if not _check_room_ui():
		return
	# The room service can be used without a Node or a WebSocket.
	var isolated := RoomNetworking.new(SceneMultiplayer.new())
	if not _check(isolated.join_room(1) == ERR_UNAVAILABLE, "Offline room command was accepted"):
		return
	var a := _client("ClientA")
	var b := _client("ClientB")
	var am: PlayerManager = a.get_parent().get_node("PlayerManager")
	var bm: PlayerManager = b.get_parent().get_node("PlayerManager")
	if not await _wait_until(func(): return a.client_id > 0 and b.client_id > 0, "signaling handshake"):
		return
	a.room_networking.create_room("Networking regression test")
	if not _check(a.room_networking.join_room(999) == ERR_BUSY, "Concurrent room command was accepted"):
		return
	if not await _idle(a):
		return
	var room_id: int = a.room_networking.current_room.id
	b.room_networking.join_room(room_id)
	if not await _idle(b):
		return
	if not await _wait_until(func(): return am.players.get_child_count() == 2 and bm.players.get_child_count() == 2, "WebRTC and player spawning"):
		return
	if not _check(am.local_player.controls != null and (am.players.get_node(str(b.client_id)) as NetworkPlayer).controls == null, "Remote player instantiated local controls"):
		return
	var mesh: WebRTCMesh = b.room_networking.rtc_mesh
	b.room_networking.join_room(room_id)
	if not await _idle(b):
		return
	if not _check(b.room_networking.rtc_mesh == mesh, "Duplicate join replaced the mesh"):
		return
	b.room_networking.join_room(999999)
	if not await _idle(b):
		return
	if not _check(failures.size() == 1 and b.room_networking.rtc_mesh == mesh, "Failed join did not retain membership and complete the operation"):
		return
	failures.clear()
	# The same room and peer IDs must still get a fresh membership session.
	var old_session: int = mesh.session_id
	b.room_networking.leave_room()
	if not await _idle(b):
		return
	if not _check(bm.local_player == null and bm.players.get_child_count() == 0, "Leaving kept local players"):
		return
	b.room_networking.join_room(room_id)
	if not await _idle(b):
		return
	if not await _wait_until(func(): return am.players.get_child_count() == 2 and bm.players.get_child_count() == 2, "same-room rejoin"):
		return
	if not _check(b.room_networking.rtc_mesh.session_id != old_session, "Rejoin reused the old session"):
		return
	var stale := Packets.ServerRelay.new()
	stale.set_sender_id(a.client_id)
	stale.set_sender_session_id(a.room_networking.rtc_mesh.session_id)
	stale.set_destination_session_id(old_session)
	b.room_networking.rtc_mesh.receive_relay(stale)
	stale.set_sender_id(b.client_id)
	stale.set_sender_session_id(old_session)
	stale.set_destination_session_id(a.room_networking.rtc_mesh.session_id)
	a.room_networking.rtc_mesh.receive_relay(stale)
	var late: Array = []
	mesh.packet_created.connect(func(packet): late.append(packet))
	mesh._candidate_created("0", 0, "late", a.client_id, a.room_networking.rtc_mesh.session_id)
	if not _check(late.is_empty(), "Old mesh emitted a candidate"):
		return
	# Replace the world-owned manager while staying in the room.
	am.free()
	if not await _wait_until(func(): return bm.players.get_child_count() == 1, "departing world despawns its avatar"):
		return
	am = _manager(a)
	if not await _wait_until(func(): return am.players.get_child_count() == 2, "world manager recreation"):
		return
	# Exercise body/head/hand replication without requiring an XR runtime.
	am.local_player.use_vr = true
	a.player_replication.spawn_player.rpc_id(b.client_id, true, am.local_player.global_transform)
	if not await _wait_until(func(): return (bm.players.get_node(str(a.client_id)) as NetworkPlayer).use_vr, "remote VR representation"):
		return
	if not _check(bm.players.get_node(str(a.client_id)).get_node("Avatar/LeftHand").visible, "VR avatar hands stayed hidden"):
		return
	am.local_player.set_physics_process(false)
	am.local_player.global_position = Vector3(3, 4, 5)
	am.local_player.controls.head.position = Vector3(0.1, 1.8, 0.2)
	var hand := Node3D.new()
	am.local_player.controls.add_child(hand)
	hand.position = Vector3(-0.5, 1, -0.3)
	am.local_player.controls.left_hand = hand
	if not await _wait_until(func():
		var remote: NetworkPlayer = bm.players.get_node(str(a.client_id))
		return remote.global_position.is_equal_approx(Vector3(3, 4, 5)) and remote.get_node("Avatar/Head").position.is_equal_approx(Vector3(0.1, 1.8, 0.2)) and remote.get_node("Avatar/LeftHand").position.is_equal_approx(hand.position), "shared player pose replication"):
		return
	# A new room resets scene-owned players as well as the old mesh.
	a.room_networking.create_room("Another room")
	if not await _idle(a):
		return
	if not await _wait_until(func(): return bm.players.get_child_count() == 1, "room switch cleanup"):
		return
	var previous_id: int = b.client_id
	b.room_networking.join_room(a.room_networking.current_room.id)
	b.ws.close(-1)
	if not await _wait_until(func(): return b.client_id == 0, "disconnect cleanup"):
		return
	if not _check(b.room_networking.current_room == null and b.room_networking.rooms.is_empty() and bm.local_player == null and b.room_networking.pending_operation == RoomNetworking.Operation.NONE and failures.size() == 1, "Disconnect retained state or failed to finish its pending operation"):
		return
	failures.clear()
	if not await _wait_until(func(): return b.client_id > 0 and b.client_id != previous_id, "automatic reconnect"):
		return
	a.ws.close(-1)
	b.ws.close(-1)
	if not await _wait_until(func(): return a.client_id == 0 and b.client_id == 0, "test cleanup"):
		return
	a.get_parent().free()
	b.get_parent().free()
	if not await _check_game_scene():
		return
	print("Networking and player integration checks passed")
	quit()


func _check_game_scene() -> bool:
	var network := root.get_node("Networking")
	network.set_process(true)
	var game: Node = load("res://Main.tscn").instantiate()
	root.add_child(game)
	if not await _wait_until(func(): return network.client_id > 0, "game signaling"):
		return false
	game.get_node("roomSelector/%CreateRoom").pressed.emit()
	var manager: PlayerManager = game.get_node("PlayerManager")
	if not await _wait_until(func(): return manager.local_player != null and manager.local_player.is_on_floor(), "game player landing"):
		return false
	var initial := manager.local_player.global_position
	Input.action_press("move_forward")
	for frame in range(12):
		await get_tree().physics_frame
	Input.action_release("move_forward")
	var distance := manager.local_player.global_position - initial
	distance.y = 0
	if not _check(distance.length() > 0.1, "Shared player did not respond to desktop movement"):
		return false
	Input.action_press("jump")
	for frame in range(3):
		await get_tree().physics_frame
	Input.action_release("jump")
	if not _check(manager.local_player.velocity.y > 0, "Shared player did not jump"):
		return false
	# A pending out-of-bounds respawn must not touch a freed room player.
	game.get_node("World/Bounds")._on_body_exited(manager.local_player)
	game.get_node("roomSelector/%LeaveRoom").pressed.emit()
	if not await _idle(network):
		return false
	if not _check(manager.local_player == null and game.get_node("roomSelector/VBoxContainer").visible, "Game leave did not clear players and restore the lobby"):
		return false
	await get_tree().create_timer(2.6).timeout
	game.free()
	network.ws.close(-1)
	return true
