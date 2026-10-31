extends Node

const Network = preload("res://Networking/Networking.gd")
const Packets = preload("res://Networking/Generated/Packets.gd")
var failures: Array[String] = []
var profile_existed := false
var profile_backup := PackedByteArray()
var _custom_fixture := ""
var _custom_owned := false
var _custom_manifest_existed := false
var _custom_manifest_backup := PackedByteArray()
@onready var root := get_tree().root


func quit(code := 0) -> void:
	if not _custom_fixture.is_empty():
		if not _custom_owned:
			AvatarCatalog.unregister_local(_custom_fixture)
			DirAccess.remove_absolute(AvatarLocalLibrary.path_for(_custom_fixture))
		if _custom_manifest_existed:
			FileAccess.open(AvatarLocalLibrary.MANIFEST, FileAccess.WRITE).store_buffer(_custom_manifest_backup)
		else:
			DirAccess.remove_absolute(AvatarLocalLibrary.MANIFEST)
		_custom_fixture = ""
	if profile_existed:
		FileAccess.open("user://profile.cfg", FileAccess.WRITE).store_buffer(profile_backup)
	else:
		DirAccess.remove_absolute("user://profile.cfg")
	get_tree().quit(code)


func _ready() -> void:
	profile_existed = FileAccess.file_exists("user://profile.cfg")
	if profile_existed:
		profile_backup = FileAccess.get_file_as_bytes("user://profile.cfg")
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
	manager.voice_chat = client.voice_chat
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
	var recovered: bool = not ui.get_node("%CreateRoom").disabled and ui.get_node("%Status").text == "Room rejected"
	ui._operation_started(RoomNetworking.Operation.REFRESH)
	ui._operation_finished(RoomNetworking.Operation.REFRESH, false, "Turn refresh timed out")
	recovered = recovered and ui.get_node("%Status").text == "Room rejected"
	ui.free()
	network.room_networking = original
	return _check(busy and recovered, "Room UI did not disable pending actions or recover after failure")


func _check_recovery_retries() -> bool:
	var api := SceneMultiplayer.new()
	var state := RoomNetworking.new(api)
	state.connected = true
	state.detached_session = true
	state.current_room = roomClass.new(42, "Recovery test", 1)
	state.rtc_mesh = WebRTCMesh.new()
	state.rtc_mesh.start(20, 30)
	api.multiplayer_peer = state.rtc_mesh.multiplayer_peer
	var mesh := state.rtc_mesh
	var peer := Packets.Peer.new()
	peer.set_id(21)
	peer.set_session_id(31)
	mesh.add_peer(peer, false)
	var connection := mesh._get_connection(21)
	mesh.suspend_peer_signaling(21)
	mesh.add_peer(peer, false)
	var restored := not mesh.signaling_unavailable.has(21) and mesh._get_connection(21) == connection
	var relays: Array = []
	mesh.packet_created.connect(func(packet): relays.append(packet))
	mesh._candidate_created("0", 0, "candidate", 21, 31, mesh._peer_attempts[21])
	restored = restored and relays.size() == 1
	var requests: Array = []
	state.packet_created.connect(func(packet): requests.append(packet))
	state.recover_room()
	var reply := Packets.ServerPacket.new()
	reply.new_error().set_reason("recovered identity is already in use")
	reply.set_request_id(state._request_id)
	state.handle_packet(reply, 20)
	var retried := state._recover_at > Time.get_ticks_msec() and state.pending_operation == RoomNetworking.Operation.NONE and state.rtc_mesh == mesh
	state.poll_recovery()
	retried = retried and requests.size() == 1
	state._recover_at = Time.get_ticks_msec() - 1
	state.poll_recovery()
	retried = retried and requests.size() == 2 and state.pending_operation == RoomNetworking.Operation.RECOVER
	# A delayed rejection from the first request must not complete its retry.
	state.handle_packet(reply, 20)
	retried = retried and state.pending_operation == RoomNetworking.Operation.RECOVER
	var joined := Packets.ServerPacket.new()
	joined.set_request_id(state._request_id)
	joined.new_room_joined().set_session_id(30)
	var room = joined.get_room_joined().new_room()
	room.set_id(42)
	room.set_name("Recovery test")
	room.set_world_id("floating_island")
	state.handle_packet(joined, 20)
	retried = retried and not state.detached_session and state.rtc_mesh == mesh and api.get_unique_id() == 20
	# Permanent conflicts stop automatic retries without dropping the live mesh.
	state.signaling_lost()
	state.connected = true
	state.recover_room()
	reply.set_request_id(state._request_id)
	reply.get_error().set_reason("recovered room conflicts with an existing room")
	state.handle_packet(reply, 20)
	var bounded := state._recover_at == -1 and state.detached_session and state.rtc_mesh == mesh
	var before := requests.size()
	state.poll_recovery()
	bounded = bounded and requests.size() == before
	# Explicit leave cancels an otherwise scheduled retry.
	state.recover_room()
	reply.set_request_id(state._request_id)
	reply.get_error().set_reason("recovered identity is already in use")
	state.handle_packet(reply, 20)
	bounded = bounded and state._recover_at > 0
	state.leave_room()
	before = requests.size()
	state.poll_recovery()
	bounded = bounded and requests.size() == before and state.pending_operation == RoomNetworking.Operation.LEAVE
	var left := Packets.ServerPacket.new()
	left.set_request_id(state._request_id)
	left.new_room_left()
	state.handle_packet(left, 20)
	bounded = bounded and state._recover_at == 0 and state.current_room == null and state.rtc_mesh == null
	state.reset()
	return (
		_check(restored, "Recovered peer remained suspended or replaced its connection")
		and _check(retried, "Recovery did not retry a temporary conflict and retain its mesh on success")
		and _check(bounded, "Recovery must stop on permanent failure or leave")
	)


func _check_relay_rebuild() -> bool:
	# A locally pruned connection must be rebuilt only by an inbound offer:
	# an answer without a local offer is stale negotiation data.
	var mesh := WebRTCMesh.new()
	if mesh.start(10, 20) != OK:
		return _check(false, "Could not start an isolated mesh")
	var peer := Packets.Peer.new()
	peer.set_id(11)
	peer.set_session_id(21)
	mesh.add_peer(peer, false)
	var created := mesh._get_connection(11) != null
	# Simulate Godot pruning the failed connection while membership remains.
	mesh.multiplayer_peer.remove_peer(11)
	var pruned := mesh._get_connection(11) == null and mesh.peer_sessions.has(11)
	var relay := Packets.ServerRelay.new()
	relay.set_sender_id(11)
	relay.set_sender_session_id(21)
	relay.set_destination_session_id(20)
	relay.new_description().set_type("answer")
	relay.get_description().set_sdp("v=0")
	mesh.receive_relay(relay)
	var ignored_answer: bool = mesh._get_connection(11) == null
	var source := WebRTCPeerConnection.new()
	var offers: Array[String] = []
	source.session_description_created.connect(func(_type: String, sdp: String): offers.append(sdp))
	if source.initialize({}) != OK:
		source.close()
		mesh.close()
		return _check(false, "Could not generate the relay fixture's offer")
	var channel := source.create_data_channel("fixture", {"negotiated": true, "id": 0})
	if channel == null or source.create_offer() != OK:
		source.close()
		mesh.close()
		return _check(false, "Could not create the relay fixture's data channel")
	var deadline := Time.get_ticks_msec() + 3000
	while offers.is_empty() and Time.get_ticks_msec() < deadline:
		source.poll()
		await get_tree().process_frame
	source.close()
	if offers.is_empty():
		mesh.close()
		return _check(false, "Relay fixture's offer generation timed out")
	relay.get_description().set_type("offer")
	relay.get_description().set_sdp(offers[0])
	mesh.receive_relay(relay)
	var rebuilt_offer: bool = mesh._get_connection(11) != null
	mesh.close()
	return (
		_check(created and pruned, "Relay rebuild fixture lost its membership or connection")
		and _check(ignored_answer, "A stale answer rebuilt a missing connection")
		and _check(rebuilt_offer, "An inbound re-offer failed to repair a missing connection")
	)


func _check_refresh_timeout() -> bool:
	# A TURN refresh is an idempotent same-room join: its timeout must complete
	# locally and retry on the backoff instead of demanding a reconnect.
	var state := RoomNetworking.new(SceneMultiplayer.new())
	state.connected = true
	state.current_room = roomClass.new(7, "Refresh test", 1)
	state.rtc_mesh = WebRTCMesh.new()
	var requests: Array = []
	state.packet_created.connect(func(packet): requests.append(packet))
	state._request(RoomNetworking.Operation.REFRESH, Packets.ClientPacket.new())
	state._deadline = Time.get_ticks_msec() - 1
	var completed: bool = state.request_expired() and state.finish_expired_refresh() and state.pending_operation == RoomNetworking.Operation.NONE
	# A late reply to the abandoned request must not restart the operation.
	var reply := Packets.ServerPacket.new()
	reply.set_request_id(state._request_id)
	reply.new_room_joined().set_session_id(9)
	var room = reply.get_room_joined().new_room()
	room.set_id(7)
	room.set_name("Refresh test")
	state.handle_packet(reply, 8)
	completed = completed and state.pending_operation == RoomNetworking.Operation.NONE
	# The retry honors the refresh backoff, then resends the same-room join.
	state._turn_expires_at = Time.get_ticks_msec() + 60000
	state._turn_refresh_at = Time.get_ticks_msec() - 1
	state.poll_recovery()
	var deferred: bool = requests.size() == 1
	state._turn_refresh_retry_at = Time.get_ticks_msec() - 1
	state.poll_recovery()
	deferred = deferred and requests.size() == 2 and state.pending_operation == RoomNetworking.Operation.REFRESH
	state._deadline = Time.get_ticks_msec() - 1
	if not state.finish_expired_refresh():
		return _check(false, "Second timed-out refresh did not complete locally")
	# Membership-changing operations still expire into a reconnect.
	var join := Packets.ClientPacket.new()
	join.new_room_join().set_room_id(7)
	if state._request(RoomNetworking.Operation.JOIN, join) != OK:
		return _check(false, "Fixture could not start a join")
	state._deadline = Time.get_ticks_msec() - 1
	var membership: bool = state.request_expired() and not state.finish_expired_refresh()
	state.reset()
	return (
		_check(completed, "Timed-out refresh did not complete locally and ignore its late reply")
		and _check(deferred, "Timed-out refresh did not defer and then retry on the backoff")
		and _check(membership, "Refresh timeout path captured a membership-changing operation")
	)


func _run() -> void:
	var network := root.get_node("Networking")
	network.set_process(false)
	if not _check(network.ws.supported_protocols.has(Network.SIGNALING_PROTOCOL), "Signaling client did not request the versioned subprotocol"):
		return
	network.ws.close(-1)
	if not _check_room_ui():
		return
	if not _check_recovery_retries():
		return
	if not await _check_relay_rebuild():
		return
	if not _check_refresh_timeout():
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
	if not _check(a.ws.get_selected_protocol() == Network.SIGNALING_PROTOCOL and b.ws.get_selected_protocol() == Network.SIGNALING_PROTOCOL, "Signaling sockets did not negotiate the versioned subprotocol"):
		return
	a.room_networking.create_room("Networking regression test", "moon_garden")
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
	# Voice uses the mesh's explicitly configured fourth data channel. Exercising
	# the actual RPC catches confusing transfer-channel/physical-channel mappings.
	var codec: TwovoipOpusEncoder = a.voice_chat._create_encoder(VoiceChat.SAMPLE_RATE)
	var speech := PackedVector2Array()
	speech.resize(VoiceChat.SAMPLES_PER_FRAME)
	speech.fill(Vector2(0.1, 0.1))
	codec.process_chunk(speech)
	var voice_frame: PackedByteArray = codec.encode_chunk()
	if not _check(not voice_frame.is_empty() and voice_frame.size() < VoiceChat.SAMPLES_PER_FRAME * 2, "TwoVoip did not compress the voice frame"):
		return
	b.voice_chat.set_audience_policy(func(_sender, _listener): return false)
	a.voice_chat.send_voice(voice_frame)
	await get_tree().create_timer(0.2).timeout
	if not _check(not b.voice_chat.speakers.has(a.client_id), "Receiver accepted voice outside its audience"):
		return
	b.voice_chat.set_audience_policy(Callable())
	a.voice_chat.set_audience_policy(func(_sender, _listener): return false)
	a.voice_chat.send_voice(voice_frame)
	await get_tree().create_timer(0.2).timeout
	if not _check(not b.voice_chat.speakers.has(a.client_id), "Sender broadcast voice outside its audience"):
		return
	a.voice_chat.set_audience_policy(Callable())
	a.voice_chat.voice_packet.rpc_id(b.client_id, voice_frame)
	if not await _wait_until(func(): return b.voice_chat.peer_activity_deadlines.has(a.client_id), "Opus decoded from dedicated voice channel"):
		return
	if not _check(a.room_networking.rtc_mesh.multiplayer_peer.get_peer(b.client_id).channels.size() == 5, "Voice and avatar data channels were not negotiated"):
		return
	a.voice_chat._speaker_playback(b.client_id)
	var remote_head := am.players.get_node(str(b.client_id) + "/Avatar/Head")
	if not _check(a.voice_chat.speakers.has(b.client_id) and a.voice_chat.speakers[b.client_id].get_parent() == remote_head, "Remote voice was not attached to the avatar head"):
		return
	b.player_replication.broadcast_avatar("godette")
	if not await _wait_until(func(): return am.get_player(b.client_id).get_node("Avatar").model != null, "reliable avatar selection and runtime import"):
		return
	if not _check(a.voice_chat.speakers[b.client_id].get_parent() == remote_head, "Avatar swap replaced the stable voice anchor"):
		return
	# Force actual bulk bytes over the fifth WebRTC data channel, even though
	# these fixture peers share their process/catalog.
	_custom_manifest_existed = FileAccess.file_exists(AvatarLocalLibrary.MANIFEST)
	_custom_manifest_backup = FileAccess.get_file_as_bytes(AvatarLocalLibrary.MANIFEST) if _custom_manifest_existed else PackedByteArray()
	var custom_bytes := FileAccess.get_file_as_bytes("res://avatar/godette.vrm")
	var custom_hash := HashingContext.new()
	custom_hash.start(HashingContext.HASH_SHA256)
	custom_hash.update(custom_bytes)
	_custom_fixture = custom_hash.finish().hex_encode()
	_custom_owned = AvatarCatalog.is_owned(_custom_fixture)
	var custom: Dictionary = await root.get_node("AvatarService").import_local_bytes("WebRTC fixture.vrm", custom_bytes)
	if not _check(custom.get("id", "") == _custom_fixture, "Could not import WebRTC custom fixture"):
		return
	var transfer = a.player_replication.avatar_transfer
	var completed_before: int = transfer.completed_transfers
	var bytes_before: int = transfer.received_bytes_total
	b.player_replication.broadcast_avatar(_custom_fixture)
	if not await _wait_until(func(): return am.get_player(b.client_id).get_node("Avatar").avatar_id == _custom_fixture, "custom content hash announced"):
		return
	transfer.ensure(b.client_id, _custom_fixture, true)
	if not await _wait_until(func():
		var indicator := am.get_player(b.client_id).get_node_or_null("AvatarProgress")
		return indicator != null and indicator.visible, "remote avatar download appears beneath name"):
		return
	if not await _wait_until(func(): return transfer.completed_transfers > completed_before, "verified custom VRM over dedicated WebRTC channel"):
		return
	if not _check(transfer.received_bytes_total - bytes_before == custom_bytes.size(), "WebRTC avatar bytes were lost or duplicated"):
		return
	if not await _wait_until(func(): return am.get_player(b.client_id).get_node("Avatar").avatar_id == _custom_fixture, "custom avatar applied to remote player"):
		return
	if not _check(a.voice_chat.speakers[b.client_id].get_parent() == remote_head, "P2P avatar swap replaced the voice anchor"):
		return
	if not await _wait_until(func(): return not am.get_player(b.client_id).get_node("AvatarProgress").visible, "remote avatar progress disappears after equipping"):
		return
	b.player_replication.broadcast_avatar("godette")
	if not await _wait_until(func(): return am.get_player(b.client_id).get_node("Avatar").avatar_id == "godette", "custom to catalog avatar switch"):
		return
	b.player_replication.announce_avatar.rpc("https://example.com/untrusted.vrm")
	if not await _wait_until(func(): return am.get_player(b.client_id).get_node("Avatar").avatar_id == "default", "unknown avatar ID falls back without fetching peer URLs"):
		return
	b.voice_chat.set_audience_policy(func(_sender, _listener): return false)
	if not _check(not b.voice_chat.speakers.has(a.client_id), "Audience change retained queued voice playback"):
		return
	b.voice_chat.set_audience_policy(Callable())
	var oversized := PackedByteArray()
	oversized.resize(VoiceChat.MAX_PACKET_BYTES + 1)
	a.voice_chat.voice_packet.rpc_id(b.client_id, oversized)
	a.voice_chat.voice_packet.rpc_id(b.client_id, PackedByteArray())
	await get_tree().create_timer(0.2).timeout
	if not _check(not b.voice_chat.speakers.has(a.client_id), "Invalid voice packet created native playback"):
		return
	if not _check(a.room_networking.current_room.world_id == "moon_garden" and b.room_networking.current_room.world_id == "moon_garden", "Peers received different world choices"):
		return
	if not await _wait_until(func(): return am.players.get_node(str(b.client_id)).get_node_or_null("NameTag") != null, "display name replication"):
		return
	if not _check(am.players.get_node(str(b.client_id)).get_node("NameTag").text == PlayerProfile.display_name, "Remote name does not match chosen identity"):
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
	PlayerProfile.avatar_id = "godette"
	a.player_replication.broadcast_avatar("godette")
	b.room_networking.join_room(room_id)
	if not await _idle(b):
		return
	if not await _wait_until(func(): return am.players.get_child_count() == 2 and bm.players.get_child_count() == 2, "same-room rejoin"):
		return
	if not _check(b.room_networking.rtc_mesh.session_id != old_session, "Rejoin reused the old session"):
		return
	if not await _wait_until(func(): return bm.get_player(a.client_id).get_node("Avatar").avatar_id == "godette" and am.get_player(b.client_id).get_node("Avatar").avatar_id == "godette", "avatar selection included in late-join snapshots"):
		return
	PlayerProfile.avatar_id = "default"
	for manager in [am, bm]:
		manager.local_player.set_avatar("default")
	for client in [a, b]:
		client.player_replication.broadcast_avatar("default")
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
	mesh._candidate_created("0", 0, "late", a.client_id, a.room_networking.rtc_mesh.session_id, -1)
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
	am.local_player.motor.set_physics_process(false)
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
	# Killing the data channel with membership intact (a coturn restart) must
	# renegotiate in place: no despawns, no rejoin, same mesh session.
	var mesh_before: WebRTCMesh = a.room_networking.rtc_mesh
	var session_before: int = mesh_before.session_id
	var doomed = mesh_before._get_connection(b.client_id)
	if not _check(doomed != null, "no live connection to drop"):
		return
	doomed.close()
	await get_tree().create_timer(0.5).timeout
	if not _check(am.players.get_child_count() == 2 and bm.players.get_child_count() == 2, "transport loss despawned avatars"):
		return
	am.local_player.global_position = Vector3(7, 8, 9)
	if not await _wait_until(func():
		var remote: NetworkPlayer = bm.players.get_node(str(a.client_id))
		return remote.global_position.is_equal_approx(Vector3(7, 8, 9)), "post-recovery pose replication"):
		return
	if not _check(a.room_networking.rtc_mesh == mesh_before and mesh_before.session_id == session_before, "recovery replaced the mesh session"):
		return
	# A new room resets scene-owned players as well as the old mesh.
	if not await _check_control_plane_survival(a, b):
		return
	a.room_networking.create_room("Another room")
	if not await _idle(a):
		return
	if not await _wait_until(func(): return bm.players.get_child_count() == 1, "room switch cleanup"):
		return
	var previous_id: int = b.client_id
	var previous_mesh: WebRTCMesh = b.room_networking.rtc_mesh
	var previous_player: NetworkPlayer = bm.local_player
	b.room_networking.join_room(a.room_networking.current_room.id)
	b.ws.close(-1)
	if not await _wait_until(func(): return b.client_id == 0, "disconnect cleanup"):
		return
	if not _check(b.room_networking.current_room != null and b.room_networking.rooms.is_empty() and bm.local_player == previous_player and b.room_networking.rtc_mesh == previous_mesh and b.room_networking.pending_operation == RoomNetworking.Operation.NONE and failures.size() == 1, "Disconnect destroyed the live session or failed to finish its pending operation"):
		return
	failures.clear()
	# Reject the first recovery locally after sending it. Its real server reply
	# becomes stale; the transport must poll a retry and accept the next reply.
	var recovery_requests := [0]
	var reject_first_recovery := func(packet: Packets.ClientPacket):
		if packet.get_payload_case() == Packets.ClientPacket.PayloadCase.ROOM_JOIN and b.room_networking.pending_operation == RoomNetworking.Operation.RECOVER:
			recovery_requests[0] += 1
			if recovery_requests[0] == 1:
				var rejection := Packets.ServerPacket.new()
				rejection.set_request_id(packet.get_request_id())
				rejection.new_error().set_reason("recovered identity is already in use")
				b.room_networking.handle_packet(rejection, b.client_id)
	b.room_networking.packet_created.connect(reject_first_recovery)
	if not await _wait_until(func(): return b.client_id == previous_id and b.room_networking.connected and not b.room_networking.detached_session, "automatic room recovery"):
		return
	b.room_networking.packet_created.disconnect(reject_first_recovery)
	if not _check(recovery_requests[0] >= 2 and b.room_networking.rtc_mesh == previous_mesh and bm.local_player == previous_player, "Transport did not retry recovery without replacing the live session"):
		return
	failures.clear()
	a.ws.close(-1)
	b.ws.close(-1)
	if not await _wait_until(func(): return a.client_id == 0 and b.client_id == 0, "test cleanup"):
		return
	a.room_networking.reset()
	b.room_networking.reset()
	a.get_parent().free()
	b.get_parent().free()
	if not await _check_game_scene():
		return
	print("Networking and player integration checks passed")
	quit()


func _check_control_plane_survival(a: Node, b: Node) -> bool:
	var am: PlayerManager = a.get_parent().get_node("PlayerManager")
	var bm: PlayerManager = b.get_parent().get_node("PlayerManager")
	var a_id: int = a.client_id
	var b_id: int = b.client_id
	var a_mesh: WebRTCMesh = a.room_networking.rtc_mesh
	var b_mesh: WebRTCMesh = b.room_networking.rtc_mesh
	var a_player := am.local_player
	var b_player := bm.local_player
	b_player.set_physics_process(false)
	# The other side still has signaling and receives the server's peer-loss message.
	b.ws.close(-1)
	if not await _wait_until(func(): return b.client_id == 0, "one-sided signaling loss"):
		return false
	b.set_process(false)
	for frame in range(30):
		await get_tree().physics_frame
	if not _check(am.players.get_node_or_null(str(b_id)) != null and bm.local_player == b_player, "One-sided signaling loss removed a connected peer"):
		return false
	a_player.global_position = Vector3(6, 7, 8)
	if not await _wait_until(func():
		var remote := bm.players.get_node_or_null(str(a_id)) as NetworkPlayer
		return remote != null and remote.global_position.is_equal_approx(Vector3(6, 7, 8)), "poses after one-sided signaling loss"):
		return false
	# Both control-plane sockets are gone; P2P packets must still flow.
	a.ws.close(-1)
	if not await _wait_until(func(): return a.client_id == 0, "both control-plane sockets down"):
		return false
	a.set_process(false)
	b_player.global_position = Vector3(9, 10, 11)
	if not await _wait_until(func():
		var remote := am.players.get_node_or_null(str(b_id)) as NetworkPlayer
		return remote != null and remote.global_position.is_equal_approx(Vector3(9, 10, 11)), "poses without the control plane"):
		return false
	a.set_process(true)
	b.set_process(true)
	if not await _wait_until(func(): return a.client_id > 0 and b.client_id > 0, "control plane reconnect"):
		return false
	if not _check(a.room_networking.rtc_mesh == a_mesh and b.room_networking.rtc_mesh == b_mesh and am.local_player == a_player and bm.local_player == b_player and a.multiplayer.get_unique_id() == a_id and b.multiplayer.get_unique_id() == b_id, "Signaling reconnect replaced the established P2P identity"):
		return false
	# Fresh directory IDs may collide after a restart. They cannot rewrite this room.
	var original_name: String = a.room_networking.current_room.room_name
	var update := Packets.ServerPacket.new()
	var room := update.new_room_updated().new_room()
	room.set_id(a.room_networking.current_room.id)
	room.set_name("Unrelated new directory room")
	a.room_networking.handle_packet(update, a.client_id)
	if not _check(a.room_networking.current_room.room_name == original_name, "Fresh directory metadata replaced the surviving room"):
		return false
	# Late ICE callbacks from the old session must not go to a new server identity.
	var late_packet := Packets.ClientPacket.new()
	late_packet.new_relay().set_destination_id(a_id)
	b._send(late_packet)
	b.room_networking.leave_room()
	if not await _wait_until(func(): return am.players.get_child_count() == 1 and bm.local_player == null, "explicit leave from detached session"):
		return false
	a.room_networking.leave_room()
	if not await _idle(a):
		return false
	a.room_networking.create_room("New signaling session", "moon_garden")
	if not await _idle(a):
		return false
	b.room_networking.join_room(a.room_networking.current_room.id)
	if not await _idle(b):
		return false
	return await _wait_until(func(): return am.players.get_child_count() == 2 and bm.players.get_child_count() == 2, "joining again after explicit leave")


func _check_game_scene() -> bool:
	var network := root.get_node("Networking")
	network.set_process(true)
	var game: Node = load("res://Main.tscn").instantiate()
	root.add_child(game)
	if not await _wait_until(func(): return network.client_id > 0, "game signaling"):
		return false
	game.get_node("roomSelector")._select_world("floating_island")
	game.get_node("roomSelector/%CreateRoom").pressed.emit()
	var manager: PlayerManager = game.get_node("PlayerManager")
	if not await _wait_until(func(): return manager.local_player != null and manager.local_player.is_on_floor() and not game.get_node("roomSelector").world_loading, "game player landing and world readiness"):
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
	# The app owns game endpoints; loading/leaving worlds only binds their state.
	var session: Node = game.get_node("GameModes/MurderSession")
	if not _check(not network.has_node("MurderSession") and session.rules == null, "Networking owns game state or social world started murder rules"):
		return false
	network.room_networking.create_room("Game lifecycle", "blackthorn_house")
	if not await _wait_until(func(): return session.map != null and manager.local_player != null, "murder map lifecycle binding"):
		return false
	if not _check(session.manager == manager and session.player_manager == manager, "Main scene did not wire the game to its player manager"):
		return false
	session.wants_to_play = true
	session._sync_clock = 0.0
	if not await _wait_until(func(): return session.snapshot.get("self", {}).get("participating", false), "game opt-in"):
		return false
	# Switch directly to a social world without an intervening room-left event.
	network.room_networking.create_room("Social lifecycle", "floating_island")
	if not await _idle(network):
		return false
	if not await _wait_until(func(): return manager.local_player != null and game.get_node("World").has_node("Bounds"), "social world replacement"):
		return false
	if not _check(session.map == null and session.rules == null and session.presentation == null and not session.wants_to_play, "World replacement retained game state"):
		return false
	network.room_networking.create_room("Game lifecycle again", "blackthorn_house")
	if not await _wait_until(func(): return session.map != null, "game rebind after world replacement"):
		return false
	if not _check(not session.snapshot.self.participating, "Re-entering a murder world retained old opt-in"):
		return false
	network.room_networking.leave_room()
	if not await _idle(network):
		return false
	if not _check(session.map == null and session.rules == null and session.presentation == null, "Room leave retained game state"):
		return false
	game.free()
	if not _check(not is_instance_valid(session), "Game endpoint outlived its app scene"):
		return false
	network.ws.close(-1)
	return true
