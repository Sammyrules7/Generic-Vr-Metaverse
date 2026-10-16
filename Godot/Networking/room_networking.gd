class_name RoomNetworking
extends RefCounted

# This is session state, not a scene component. Supplying MultiplayerAPI lets
# the game and isolated tests use it without attaching it to the scene tree.
# Room payloads decode into roomClass (res://UI/room_class.gd), the shared
# UI/network model mirroring the Server Room packet. See its header before
# adding fields.
const Packets = preload("res://Networking/Generated/Packets.gd")
const REQUEST_TIMEOUT_MS := 10000
const RECOVERY_RETRY_MS := 20000
const MAX_RECOVERY_ATTEMPTS := 4
const TURN_REFRESH_RETRY_MS := 2000

enum Operation { NONE, CREATE, JOIN, LEAVE, RECOVER, REFRESH }

signal rooms_replaced(rooms: Array)
signal room_updated(room: roomClass)
signal room_removed(room_id: int)
signal room_joined(room: roomClass)
signal room_left
signal operation_started(operation: Operation)
signal operation_finished(operation: Operation, success: bool, reason: String)
signal network_error(reason: String)
signal packet_created(packet: Packets.ClientPacket)
signal client_id_recovered(client_id: int)
# Transport recovery mirrors the signaling-recovery pattern: a dropped data
# channel whose peer is still a room member triggers a re-offer instead of an
# immediate despawn (e.g. coturn restart). Only when the peer is gone from the
# directory, or repair times out, is peer_departed emitted for avatar teardown.
signal peer_transport_lost(peer_id: int)
signal peer_transport_recovered(peer_id: int)
signal peer_departed(peer_id: int)

var multiplayer: MultiplayerAPI
var connected := false
# A new signaling connection has a new identity. Its directory may be used again,
# but it must never replace or feed signaling into the surviving P2P session.
var detached_session := false
var rooms: Dictionary[int, roomClass] = {}
var current_room: roomClass
var rtc_mesh: WebRTCMesh
var pending_operation := Operation.NONE
# Keep increasing across reconnects so an old reply cannot match a new command.
var _request_id := 0
var _deadline := 0
var _recover_at := 0
var _recover_backoff := 1000
# Server-assigned mesh ID for deterministic re-offer elections. The injected
# MultiplayerAPI reports 1 for every isolated test client, so it cannot elect.
var _mesh_local_id := 0
# Peers with a dropped data channel but intact membership, mapped to the
# millisecond deadline after which the avatar is torn down regardless.
var _recovering_peers: Dictionary[int, int] = {}
# Peers whose data channel completed at least once. Only stable peers get an
# active re-offer on loss: a drop during the initial handshake is left to the
# in-flight exchange instead of being stomped by a competing offer.
var _stable_peers: Dictionary[int, bool] = {}
var _recovery_next_attempt: Dictionary[int, int] = {}
var _recovery_attempts: Dictionary[int, int] = {}
var _turn_expires_at := 0
var _turn_refresh_at := 0
var _turn_refresh_retry_at := 0


func _init(multiplayer_api: MultiplayerAPI) -> void:
	multiplayer = multiplayer_api
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func create_room(room_name := "", world_id := "floating_island") -> Error:
	var packet := Packets.ClientPacket.new()
	var request := packet.new_room_create()
	request.set_name(room_name)
	request.set_world_id(world_id)
	return _request(Operation.CREATE, packet)


func join_room(room_id: int) -> Error:
	var packet := Packets.ClientPacket.new()
	packet.new_room_join().set_room_id(room_id)
	return _request(Operation.JOIN, packet)


func recover_room() -> Error:
	if not connected or not detached_session or current_room == null or rtc_mesh == null:
		return ERR_UNAVAILABLE
	var packet := Packets.ClientPacket.new()
	var recovery = packet.new_room_join()
	recovery.set_room_id(current_room.id)
	var room = recovery.new_recovery_room()
	room.set_id(current_room.id)
	room.set_name(current_room.room_name)
	room.set_world_id(current_room.world_id)
	room.set_recovery_token(current_room.recovery_token)
	recovery.set_client_id(multiplayer.get_unique_id())
	recovery.set_session_id(rtc_mesh.session_id)
	return _request(Operation.RECOVER, packet, true)


func leave_room() -> Error:
	if detached_session and pending_operation == Operation.RECOVER:
		_finish_operation(false, "Recovery cancelled by leave")
	if current_room != null and not connected:
		if pending_operation != Operation.NONE:
			return ERR_BUSY
		pending_operation = Operation.LEAVE
		operation_started.emit(Operation.LEAVE)
		_stop_mesh()
		room_left.emit()
		_finish_operation(true)
		return OK
	var packet := Packets.ClientPacket.new()
	packet.new_room_leave()
	return _request(Operation.LEAVE, packet, true)


func _request(operation: Operation, packet: Packets.ClientPacket, allow_detached := false) -> Error:
	if detached_session and not allow_detached:
		return ERR_UNAVAILABLE
	if not connected:
		return ERR_UNAVAILABLE
	if pending_operation != Operation.NONE:
		# One membership change at a time keeps transitions and UI feedback unambiguous.
		return ERR_BUSY
	_request_id += 1
	packet.set_request_id(_request_id)
	pending_operation = operation
	_deadline = Time.get_ticks_msec() + REQUEST_TIMEOUT_MS
	operation_started.emit(operation)
	# Sending only starts the operation; current_room changes on the server's reply.
	packet_created.emit(packet)
	return OK


func request_expired() -> bool:
	return pending_operation != Operation.NONE and Time.get_ticks_msec() >= _deadline


func _finish_operation(success: bool, reason := "") -> void:
	if pending_operation == Operation.NONE:
		return
	var operation := pending_operation
	# Signal listeners may immediately issue another command.
	pending_operation = Operation.NONE
	_deadline = 0
	if operation == Operation.RECOVER and not success:
		_recover_at = Time.get_ticks_msec() + _recover_backoff
		_recover_backoff = mini(_recover_backoff * 2, 10000)
	operation_finished.emit(operation, success, reason)


func signaling_lost(reason := "Control plane disconnected") -> void:
	connected = false
	detached_session = current_room != null
	rooms.clear()
	rooms_replaced.emit([])
	# Explicit leave remains an explicit leave even if its acknowledgment is lost.
	if pending_operation == Operation.LEAVE:
		_stop_mesh()
		room_left.emit()
		_finish_operation(true)
	else:
		_finish_operation(false, reason)


func reset(reason := "Session reset") -> void:
	# Explicit full teardown, for application shutdown or isolated tests.
	connected = false
	var was_in_room := current_room != null
	_stop_mesh()
	rooms.clear()
	rooms_replaced.emit([])
	if was_in_room:
		room_left.emit()
	_finish_operation(false, reason)


func handle_packet(packet: Packets.ServerPacket, local_id: int) -> void:
	var recovery_reply := (
		detached_session
		and pending_operation in [Operation.RECOVER, Operation.LEAVE]
		and packet.get_request_id() == _request_id
		and packet.get_payload_case() in [Packets.ServerPacket.PayloadCase.ROOM_JOINED, Packets.ServerPacket.PayloadCase.ROOM_LEFT, Packets.ServerPacket.PayloadCase.ERROR]
	)
	if detached_session and not recovery_reply and packet.get_payload_case() not in [Packets.ServerPacket.PayloadCase.ROOM_LIST, Packets.ServerPacket.PayloadCase.ROOM_UPDATED, Packets.ServerPacket.PayloadCase.ROOM_REMOVED]:
		return
	var is_reply := packet.get_request_id() != 0
	if is_reply and (pending_operation == Operation.NONE or packet.get_request_id() != _request_id):
		return
	match packet.get_payload_case():
		Packets.ServerPacket.PayloadCase.ROOM_LIST:
			rooms.clear()
			for room_packet in packet.get_room_list().get_rooms():
				var room := _decode_room(room_packet)
				rooms[room.id] = room
			rooms_replaced.emit(rooms.values())
		Packets.ServerPacket.PayloadCase.ROOM_UPDATED:
			var room := _decode_room(packet.get_room_updated().get_room())
			rooms[room.id] = room
			if not detached_session and current_room != null and current_room.id == room.id and current_room.recovery_token == room.recovery_token:
				current_room = room
			room_updated.emit(room)
		Packets.ServerPacket.PayloadCase.ROOM_REMOVED:
			var room_id := packet.get_room_removed().get_room_id()
			rooms.erase(room_id)
			room_removed.emit(room_id)
		Packets.ServerPacket.PayloadCase.ROOM_JOINED:
			var reason := _enter_room(packet.get_room_joined(), local_id)
			if not reason.is_empty():
				_finish_operation(false, reason)
				leave_room()
				return
		Packets.ServerPacket.PayloadCase.ROOM_LEFT:
			var was_in_room := current_room != null
			_stop_mesh()
			if was_in_room:
				room_left.emit()
				if pending_operation != Operation.LEAVE:
					network_error.emit("The room server ended this session")
		Packets.ServerPacket.PayloadCase.PEER_JOINED:
			if rtc_mesh != null:
				rtc_mesh.add_peer(packet.get_peer_joined().get_peer(), false)
		Packets.ServerPacket.PayloadCase.PEER_LEFT:
			if rtc_mesh != null:
				var departure := packet.get_peer_left()
				if departure.get_signaling_disconnected():
					rtc_mesh.suspend_peer_signaling(departure.get_peer_id())
				else:
					rtc_mesh.remove_peer(departure.get_peer_id())
					_recovering_peers.erase(departure.get_peer_id())
					_recovery_next_attempt.erase(departure.get_peer_id())
					_recovery_attempts.erase(departure.get_peer_id())
					_stable_peers.erase(departure.get_peer_id())
					peer_departed.emit(departure.get_peer_id())
		Packets.ServerPacket.PayloadCase.RELAY:
			if rtc_mesh != null:
				rtc_mesh.receive_relay(packet.get_relay())
		Packets.ServerPacket.PayloadCase.ERROR:
			var reason := packet.get_error().get_reason()
			_finish_operation(false, reason)
			if detached_session and reason not in ["recovered identity is already in use", "recovered peer ID is already in the room", "room is full", "membership mint quota exceeded"]:
				_recover_at = -1
				network_error.emit("Room recovery failed: %s. Leave the room and join again." % reason)
			return
	if is_reply:
		_finish_operation(true)


func _enter_room(joined: Packets.ServerRoomJoined, local_id: int) -> String:
	# A duplicate join acknowledges the existing session; don't respawn players
	# or renegotiate connections that are already working.
	if rtc_mesh != null and current_room != null and current_room.id == joined.get_room().get_id() and current_room.recovery_token == joined.get_room().get_recovery_token() and rtc_mesh.session_id == joined.get_session_id():
		current_room = _decode_room(joined.get_room())
		_mesh_local_id = local_id
		detached_session = false
		rtc_mesh.resume_signaling()
		_recover_backoff = 1000
		_apply_turn_credentials(joined)
		var present := {}
		for peer in joined.get_peers():
			present[peer.get_id()] = true
			rtc_mesh.add_peer(peer, true)
		for peer_id in rtc_mesh.peer_sessions.keys():
			if not present.has(peer_id):
				# The directory can lag surviving P2P memberships after restart.
				rtc_mesh.suspend_peer_signaling(peer_id)
				if not multiplayer.get_peers().has(peer_id):
					_on_peer_disconnected(peer_id)
		if pending_operation != Operation.REFRESH:
			client_id_recovered.emit(multiplayer.get_unique_id())
		room_updated.emit(current_room)
		return ""
	_stop_mesh()
	_recovering_peers.clear()
	current_room = _decode_room(joined.get_room())
	_mesh_local_id = local_id
	rtc_mesh = WebRTCMesh.new()
	rtc_mesh.packet_created.connect(packet_created.emit)
	rtc_mesh.connection_error.connect(network_error.emit)
	_apply_turn_credentials(joined)
	var result := rtc_mesh.start(local_id, joined.get_session_id())
	if result != OK:
		_stop_mesh()
		room_left.emit()
		return "Could not create WebRTC mesh: %s" % error_string(result)
	multiplayer.multiplayer_peer = rtc_mesh.multiplayer_peer
	# Only the newcomer offers. Existing members wait, avoiding simultaneous offers.
	for peer in joined.get_peers():
		rtc_mesh.add_peer(peer, true)
	room_joined.emit(current_room)
	return ""


func _stop_mesh() -> void:
	detached_session = false
	_recover_at = 0
	_recover_backoff = 1000
	_recovering_peers.clear()
	_recovery_next_attempt.clear()
	_recovery_attempts.clear()
	_turn_expires_at = 0
	_turn_refresh_at = 0
	_turn_refresh_retry_at = 0
	_stable_peers.clear()
	if rtc_mesh != null:
		rtc_mesh.close()
		rtc_mesh = null
	if not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	current_room = null


func _apply_turn_credentials(joined: Packets.ServerRoomJoined) -> void:
	_turn_expires_at = 0
	_turn_refresh_at = 0
	_turn_refresh_retry_at = 0
	if rtc_mesh == null:
		return
	if not joined.has_turn():
		rtc_mesh.set_turn_servers([], "", "")
		return
	var turn := joined.get_turn()
	rtc_mesh.set_turn_servers(turn.get_urls(), turn.get_username(), turn.get_password())
	var ttl_ms: int = turn.get_ttl() * 1000
	var now := Time.get_ticks_msec()
	_turn_expires_at = now + ttl_ms
	# Refresh early enough for a command round trip; scale down for short TTLs.
	@warning_ignore("integer_division")
	_turn_refresh_at = now + maxi(1, ttl_ms - mini(60000, ttl_ms / 5))


func _refresh_turn_if_due(now: int) -> bool:
	if _turn_expires_at == 0 or now < _turn_refresh_at:
		return true
	# Keep established channels alive, but do not allocate with aging credentials.
	if connected and not detached_session and current_room != null and pending_operation == Operation.NONE and now >= _turn_refresh_retry_at:
		var packet := Packets.ClientPacket.new()
		packet.new_room_join().set_room_id(current_room.id)
		_turn_refresh_retry_at = now + TURN_REFRESH_RETRY_MS
		_request(Operation.REFRESH, packet)
	return false


func _on_peer_connected(peer_id: int) -> void:
	_stable_peers[peer_id] = true
	_recovery_next_attempt.erase(peer_id)
	_recovery_attempts.erase(peer_id)
	if _recovering_peers.erase(peer_id):
		peer_transport_recovered.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	# A data channel can drop while membership persists (coturn restart, NAT
	# rebinding). Repair with a re-offer instead of tearing down the avatar,
	# mirroring how signaling loss preserves the P2P session. Explicit leaves
	# already removed the peer from the mesh, so they never reach this branch.
	if rtc_mesh == null or not rtc_mesh.peer_sessions.has(peer_id):
		return
	if current_room == null:
		return
	if _recovering_peers.has(peer_id):
		return
	_recovering_peers[peer_id] = Time.get_ticks_msec() + WebRTCMesh.TRANSPORT_RECOVERY_MS
	_recovery_next_attempt[peer_id] = 0
	_recovery_attempts[peer_id] = 0
	peer_transport_lost.emit(peer_id)


func transport_repairing() -> bool:
	return not _recovering_peers.is_empty()


func poll_recovery() -> void:
	var now := Time.get_ticks_msec()
	if connected and detached_session and pending_operation == Operation.NONE and _recover_at >= 0 and now >= _recover_at:
		recover_room()
	# Runs even without transport loss, keeping long-lived room credentials fresh.
	var credentials_ready := _refresh_turn_if_due(now)
	for peer_id in _recovering_peers.keys():
		if multiplayer.get_peers().has(peer_id):
			_on_peer_connected(peer_id)
			continue
		if now >= _recovering_peers[peer_id]:
			_recovering_peers.erase(peer_id)
			_recovery_next_attempt.erase(peer_id)
			_recovery_attempts.erase(peer_id)
			_stable_peers.erase(peer_id)
			if rtc_mesh != null:
				rtc_mesh.remove_peer(peer_id)
			peer_departed.emit(peer_id)
			continue
		if not credentials_ready or not connected or detached_session or pending_operation != Operation.NONE or rtc_mesh.signaling_unavailable.has(peer_id):
			continue
		# Only the lower ID offers; allow each attempt time for ICE and pod startup.
		if not _stable_peers.has(peer_id) or _mesh_local_id == 0 or _mesh_local_id >= peer_id:
			continue
		if now < _recovery_next_attempt.get(peer_id, 0) or _recovery_attempts.get(peer_id, 0) >= MAX_RECOVERY_ATTEMPTS:
			continue
		_recovery_next_attempt[peer_id] = now + RECOVERY_RETRY_MS
		_recovery_attempts[peer_id] = _recovery_attempts.get(peer_id, 0) + 1
		if rtc_mesh != null:
			rtc_mesh.reconnect_peer(peer_id)


func _decode_room(packet: Packets.Room) -> roomClass:
	return roomClass.new(packet.get_id(), packet.get_name(), packet.get_player_count(), packet.get_world_id(), packet.get_recovery_token())
