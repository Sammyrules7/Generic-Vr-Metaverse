extends Node

# The autoload keeps transport alive across world changes. Room state and player
# replication have separate owners so neither depends on the current scene.
const Packets = preload("res://Networking/Generated/Packets.gd")
const SERVER_URL_SETTING := "network/signaling/server_url"
const DEFAULT_SERVER_URL := "wss://api.vr.maio-tech.com/ws"

signal signaling_connected
signal signaling_disconnected
signal network_error(reason: String)

var ws := WebSocketPeer.new()
# Release CI embeds this setting; local servers are selected with the env override.
# Mutable so transport tests can use an isolated endpoint.
var ws_url: String = _configured_server_url()
var client_id := 0
var room_networking: RoomNetworking
var player_replication: PlayerReplication
var voice_chat: VoiceChat
var reconnect_at := 0
var connect_deadline := 0
var connection_message := "Connecting to the room server…"
var last_disconnect_reason := ""


func _configured_server_url() -> String:
	var override_url := OS.get_environment("VR_PLATFORM_SERVER_URL").strip_edges()
	if not override_url.is_empty():
		return override_url
	return ProjectSettings.get_setting(SERVER_URL_SETTING, DEFAULT_SERVER_URL)


func _ready() -> void:
	room_networking = RoomNetworking.new(multiplayer)
	room_networking.packet_created.connect(_send)
	room_networking.network_error.connect(network_error.emit)
	room_networking.client_id_recovered.connect(func(recovered_id: int): client_id = recovered_id)
	player_replication = PlayerReplication.new()
	player_replication.name = "PlayerReplication"
	add_child(player_replication)
	voice_chat = VoiceChat.new()
	voice_chat.name = "VoiceChat"
	# Inject before add_child so _ready keeps it instead of reaching for the parent.
	voice_chat.room_networking = room_networking
	add_child(voice_chat)
	_connect_websocket()


func _process(_delta: float) -> void:
	var disconnect_reason := "Disconnected from signaling server"
	room_networking.poll_recovery()
	if room_networking.request_expired() and not room_networking.finish_expired_refresh():
		# Membership changes may have applied even though their replies are missing.
		# An idempotent TURN refresh instead completes locally and retries on backoff.
		ws.close(-1)
		disconnect_reason = "Room request timed out"
	var previous_state := ws.get_ready_state()
	if client_id == 0 and previous_state != WebSocketPeer.STATE_CLOSED and Time.get_ticks_msec() >= connect_deadline:
		ws.close(-1)
		disconnect_reason = "The server did not respond in time"
	ws.poll()
	while ws.get_available_packet_count() > 0:
		_handle_packet(ws.get_packet())
	# close(-1) can close the socket before poll(); client_id catches that case.
	if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED and (previous_state != WebSocketPeer.STATE_CLOSED or client_id != 0):
		client_id = 0
		last_disconnect_reason = disconnect_reason
		connection_message = "Server offline · Retrying automatically"
		room_networking.signaling_lost(disconnect_reason)
		signaling_disconnected.emit()
		reconnect_at = Time.get_ticks_msec() + 2000
	if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED and Time.get_ticks_msec() >= reconnect_at:
		_connect_websocket()


func _connect_websocket() -> void:
	connect_deadline = Time.get_ticks_msec() + 8000
	reconnect_at = Time.get_ticks_msec() + 2000
	ws = WebSocketPeer.new()
	var result := ws.connect_to_url(ws_url)
	if result != OK:
		connection_message = "Server unavailable · Retrying automatically"
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
			connection_message = "Connected · Rooms update live"
			last_disconnect_reason = ""
			room_networking.connected = true
			signaling_connected.emit()
			if room_networking.detached_session:
				room_networking.recover_room()
		Packets.ServerPacket.PayloadCase.ERROR:
			if packet.get_request_id() != 0:
				room_networking.handle_packet(packet, client_id)
			else:
				network_error.emit(packet.get_error().get_reason())
		_:
			room_networking.handle_packet(packet, client_id)


func _send(packet: Packets.ClientPacket) -> void:
	if packet.get_payload_case() == Packets.ClientPacket.PayloadCase.RELAY and (room_networking.detached_session or not room_networking.connected):
		# Late ICE callbacks cannot revive signaling or terminate healthy data channels.
		return
	if ws.get_ready_state() != WebSocketPeer.STATE_OPEN or client_id == 0:
		room_networking.signaling_lost("Not connected to signaling server")
		signaling_disconnected.emit()
		network_error.emit("Not connected to signaling server")
		return
	var result := ws.send(packet.to_bytes(), WebSocketPeer.WRITE_MODE_BINARY)
	if result != OK:
		# Losing an ordered room/signaling packet requires a fresh session.
		ws.close(-1)
		network_error.emit("Could not send signaling packet: %s" % error_string(result))


func retry_connection(url: String) -> Error:
	url = url.strip_edges()
	if not (url.begins_with("ws://") or url.begins_with("wss://")) or url.length() < 8:
		return ERR_INVALID_PARAMETER
	if room_networking.current_room != null or room_networking.pending_operation != RoomNetworking.Operation.NONE:
		return ERR_BUSY
	ws.close(-1)
	client_id = 0
	room_networking.reset()
	ws_url = url
	connection_message = "Connecting to the room server…"
	signaling_disconnected.emit()
	_connect_websocket()
	return OK
