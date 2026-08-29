extends Node

const Packets = preload("res://Networking/Generated/Packets.gd")

var ws: WebSocketPeer = WebSocketPeer.new()
var ws_url: String =  "ws://localhost:8080/ws"
var ws_last: WebSocketPeer.State
var client_id: int = 0


func _ready() -> void:
	print("WebSocket connecting to: ", ws_url)
	ws.connect_to_url(ws_url)

func _process(_delta: float) -> void:
	ws.poll()
	_poll_ws_events(ws)

	while ws.get_available_packet_count():
		_handle_packet()

func _poll_ws_events(ws_conn: WebSocketPeer) -> void:

	var ws_state: WebSocketPeer.State = ws_conn.get_ready_state()

	if ws_state == WebSocketPeer.State.STATE_CLOSED:
		ws_conn.connect_to_url(ws_url)

	if ws_last != ws_state:
		ws_last = ws_state

		match  ws_state:
			WebSocketPeer.State.STATE_CLOSED:
				print("WebSocket closed with code: %i, Reason: %s" % ws_conn.get_close_code(), ws_conn.get_close_reason())
				print("Retrying WebSocket connection to: ", ws_url)
			WebSocketPeer.State.STATE_OPEN:
				print("WebSocket Connected!")
				send_test_packet()
			WebSocketPeer.State.STATE_CLOSING:
				pass
			WebSocketPeer.State.STATE_CONNECTING:
				pass

func _handle_packet() -> void:
	var packet := Packets.ServerPacket.new()
	var result: int = packet.from_bytes(ws.get_packet())
	if result != Packets.PB_ERR.NO_ERRORS:
		push_error("Failed to decode server packet: %d" % result)
		return

	match packet.get_payload_case():
		Packets.ServerPacket.PayloadCase.CONNECTED:
			client_id = packet.get_connected().get_client_id()
			print("Connected as client %d" % client_id)
		Packets.ServerPacket.PayloadCase.DATA:
			var data := packet.get_data()
			print("Packet from %d: %s" % [
				data.get_sender_id(),
				data.get_value().get_string_from_utf8(),
			])
		_:
			push_warning("Server packet did not contain a payload")

func send_data(value: PackedByteArray) -> Error:
	if ws.get_ready_state() != WebSocketPeer.State.STATE_OPEN:
		return ERR_UNAVAILABLE

	var packet := Packets.ClientPacket.new()
	packet.new_data().set_value(value)
	return ws.send(packet.to_bytes(), WebSocketPeer.WRITE_MODE_BINARY)

func send_test_packet() -> void:
	var result: Error = send_data("Hello from Godot".to_utf8_buffer())
	if result != OK:
		push_error("Failed to send test packet: %s" % error_string(result))
