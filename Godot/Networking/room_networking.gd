class_name RoomNetworking
extends RefCounted

# This is session state, not a scene component. Supplying MultiplayerAPI lets
# the game and isolated tests use it without attaching it to the scene tree.
const Packets = preload("res://Networking/Generated/Packets.gd")
const REQUEST_TIMEOUT_MS := 10000

enum Operation { NONE, CREATE, JOIN, LEAVE, RECOVER }

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


func _init(multiplayer_api: MultiplayerAPI) -> void:
	multiplayer = multiplayer_api


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
	if current_room != null and (not connected or detached_session):
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
	return _request(Operation.LEAVE, packet)


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
		and pending_operation == Operation.RECOVER
		and packet.get_request_id() == _request_id
		and packet.get_payload_case() in [Packets.ServerPacket.PayloadCase.ROOM_JOINED, Packets.ServerPacket.PayloadCase.ERROR]
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
		Packets.ServerPacket.PayloadCase.RELAY:
			if rtc_mesh != null:
				rtc_mesh.receive_relay(packet.get_relay())
		Packets.ServerPacket.PayloadCase.ERROR:
			_finish_operation(false, packet.get_error().get_reason())
			return
	if is_reply:
		_finish_operation(true)


func _enter_room(joined: Packets.ServerRoomJoined, local_id: int) -> String:
	# A duplicate join acknowledges the existing session; don't respawn players
	# or renegotiate connections that are already working.
	if rtc_mesh != null and current_room != null and current_room.id == joined.get_room().get_id() and current_room.recovery_token == joined.get_room().get_recovery_token() and rtc_mesh.session_id == joined.get_session_id():
		current_room = _decode_room(joined.get_room())
		detached_session = false
		rtc_mesh.resume_signaling()
		for peer in joined.get_peers():
			rtc_mesh.add_peer(peer, true)
		client_id_recovered.emit(multiplayer.get_unique_id())
		room_updated.emit(current_room)
		return ""
	_stop_mesh()
	current_room = _decode_room(joined.get_room())
	rtc_mesh = WebRTCMesh.new()
	rtc_mesh.packet_created.connect(packet_created.emit)
	rtc_mesh.connection_error.connect(network_error.emit)
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
	if rtc_mesh != null:
		rtc_mesh.close()
		rtc_mesh = null
	if not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	current_room = null


func _decode_room(packet: Packets.Room) -> roomClass:
	return roomClass.new(packet.get_id(), packet.get_name(), packet.get_player_count(), packet.get_world_id(), packet.get_recovery_token())
