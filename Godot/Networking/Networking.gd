extends Node

# The autoload keeps transport alive across world changes. Room state and player
# replication have separate owners so neither depends on the current scene.
const Packets = preload("res://Networking/Generated/Packets.gd")

signal signaling_connected
signal signaling_disconnected
signal network_error(reason: String)

var ws := WebSocketPeer.new()
var ws_url := "ws://localhost:8080/ws"
var client_id := 0
var room_networking: RoomNetworking
var player_replication: PlayerReplication
var reconnect_at := 0


func _ready() -> void:
	room_networking = RoomNetworking.new(multiplayer)
	room_networking.packet_created.connect(_send)
	room_networking.network_error.connect(network_error.emit)
	player_replication = PlayerReplication.new()
	player_replication.name = "PlayerReplication"
	add_child(player_replication)
	_connect_websocket()


func _process(_delta: float) -> void:
	var disconnect_reason := "Disconnected from signaling server"
	if room_networking.request_expired():
		# The server may have applied the command even though its reply is missing.
		# Reconnect to discard ambiguous membership instead of retrying the command.
		ws.close(-1)
		disconnect_reason = "Room request timed out"
	var previous_state := ws.get_ready_state()
	ws.poll()
	while ws.get_available_packet_count() > 0:
		_handle_packet(ws.get_packet())
	# close(-1) can close the socket before poll(); client_id catches that case.
	if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED and (previous_state != WebSocketPeer.STATE_CLOSED or client_id != 0):
		client_id = 0
		room_networking.reset(disconnect_reason)
		signaling_disconnected.emit()
		reconnect_at = Time.get_ticks_msec() + 2000
	if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED and Time.get_ticks_msec() >= reconnect_at:
		_connect_websocket()


func _connect_websocket() -> void:
	reconnect_at = Time.get_ticks_msec() + 2000
	ws = WebSocketPeer.new()
	var result := ws.connect_to_url(ws_url)
	if result != OK:
		network_error.emit("Could not connect to signaling server: %s" % error_string(result))
		signaling_disconnected.emit()


func _handle_packet(bytes: PackedByteArray) -> void:
	var packet := Packets.ServerPacket.new()
	if packet.from_bytes(bytes) != Packets.PB_ERR.NO_ERRORS:
		network_error.emit("Could not decode signaling packet")
		return
	match packet.get_payload_case():
		Packets.ServerPacket.PayloadCase.CONNECTED:
			# An open socket alone is not ready: WebRTC needs the server-assigned ID.
			client_id = packet.get_connected().get_client_id()
			room_networking.connected = true
			signaling_connected.emit()
		Packets.ServerPacket.PayloadCase.ERROR:
			if packet.get_request_id() != 0:
				room_networking.handle_packet(packet, client_id)
			else:
				network_error.emit(packet.get_error().get_reason())
		_:
			room_networking.handle_packet(packet, client_id)


func _send(packet: Packets.ClientPacket) -> void:
	if ws.get_ready_state() != WebSocketPeer.STATE_OPEN or client_id == 0:
		room_networking.reset("Not connected to signaling server")
		network_error.emit("Not connected to signaling server")
		return
	var result := ws.send(packet.to_bytes(), WebSocketPeer.WRITE_MODE_BINARY)
	if result != OK:
		# Losing an ordered room/signaling packet requires a fresh session.
		ws.close(-1)
		network_error.emit("Could not send signaling packet: %s" % error_string(result))
