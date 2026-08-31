extends Node

const Packets = preload("res://Networking/Generated/Packets.gd")
const WebRTCMeshService = preload("res://Networking/webrtc_mesh.gd")

signal signaling_connected
signal signaling_disconnected
signal rooms_replaced(rooms: Array)
signal room_updated(room: roomClass)
signal room_removed(room_id: int)
signal room_joined(room: roomClass)
signal room_left
signal network_error(reason: String)

var ws := WebSocketPeer.new()
var ws_url := "ws://localhost:8080/ws"
var client_id := 0
var current_room: roomClass
var rooms: Dictionary[int, roomClass] = {}
var rtc_mesh: WebRTCMesh
var reconnect_at := 0


func _ready() -> void:
	_connect_websocket()


func _process(_delta: float) -> void:
	ws.poll()
	while ws.get_available_packet_count() > 0:
		_handle_packet(ws.get_packet())
	if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED and Time.get_ticks_msec() >= reconnect_at:
		reconnect_at = Time.get_ticks_msec() + 2000
		_connect_websocket()


func _connect_websocket() -> void:
	if current_room != null:
		_stop_mesh()
		room_left.emit()
	ws = WebSocketPeer.new()
	var result := ws.connect_to_url(ws_url)
	if result != OK:
		network_error.emit("Could not connect to signaling server: %s" % error_string(result))
		return
	while ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		ws.poll()
		await get_tree().process_frame
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		signaling_connected.emit()
	else:
		signaling_disconnected.emit()


func _handle_packet(bytes: PackedByteArray) -> void:
	var packet := Packets.ServerPacket.new()
	if packet.from_bytes(bytes) != Packets.PB_ERR.NO_ERRORS:
		network_error.emit("Could not decode signaling packet")
		return

	match packet.get_payload_case():
		Packets.ServerPacket.PayloadCase.CONNECTED:
			client_id = packet.get_connected().get_client_id()
		Packets.ServerPacket.PayloadCase.ROOM_LIST:
			rooms.clear()
			for room_packet in packet.get_room_list().get_rooms():
				var room := _decode_room(room_packet)
				rooms[room.id] = room
			rooms_replaced.emit(rooms.values())
		Packets.ServerPacket.PayloadCase.ROOM_UPDATED:
			var room := _decode_room(packet.get_room_updated().get_room())
			rooms[room.id] = room
			room_updated.emit(room)
		Packets.ServerPacket.PayloadCase.ROOM_REMOVED:
			var room_id := packet.get_room_removed().get_room_id()
			rooms.erase(room_id)
			room_removed.emit(room_id)
		Packets.ServerPacket.PayloadCase.ROOM_JOINED:
			var joined := packet.get_room_joined()
			_stop_mesh()
			current_room = _decode_room(joined.get_room())
			_start_mesh()
			if rtc_mesh != null:
				for peer_id in joined.get_peer_ids():
					rtc_mesh.add_peer(peer_id, true)
				room_joined.emit(current_room)
		Packets.ServerPacket.PayloadCase.ROOM_LEFT:
			_stop_mesh()
			room_left.emit()
		Packets.ServerPacket.PayloadCase.PEER_JOINED:
			if rtc_mesh != null:
				rtc_mesh.add_peer(packet.get_peer_joined().get_peer_id(), false)
		Packets.ServerPacket.PayloadCase.PEER_LEFT:
			if rtc_mesh != null:
				rtc_mesh.remove_peer(packet.get_peer_left().get_peer_id())
		Packets.ServerPacket.PayloadCase.RELAY:
			if rtc_mesh != null:
				rtc_mesh.receive_relay(packet.get_relay())
		Packets.ServerPacket.PayloadCase.ERROR:
			network_error.emit(packet.get_error().get_reason())


func _decode_room(packet: Packets.Room) -> roomClass:
	return roomClass.new(packet.get_id(), packet.get_name(), packet.get_player_count())


func _send(packet: Packets.ClientPacket) -> Error:
	if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNAVAILABLE
	return ws.send(packet.to_bytes(), WebSocketPeer.WRITE_MODE_BINARY)


func create_room(name := "") -> void:
	var packet := Packets.ClientPacket.new()
	packet.new_room_create().set_name(name)
	_send(packet)


func join_room(room_id: int) -> void:
	var packet := Packets.ClientPacket.new()
	packet.new_room_join().set_room_id(room_id)
	_send(packet)


func leave_room() -> void:
	var packet := Packets.ClientPacket.new()
	packet.new_room_leave()
	_send(packet)


func _start_mesh() -> void:
	rtc_mesh = WebRTCMeshService.new()
	rtc_mesh.packet_created.connect(_send)
	rtc_mesh.connection_error.connect(network_error.emit)
	var result := rtc_mesh.start(client_id)
	if result != OK:
		network_error.emit("Could not create WebRTC mesh: %s" % error_string(result))
		rtc_mesh = null
		return
	multiplayer.multiplayer_peer = rtc_mesh.multiplayer_peer


func _stop_mesh() -> void:
	if rtc_mesh != null:
		rtc_mesh.close()
		rtc_mesh = null
	if not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	current_room = null
