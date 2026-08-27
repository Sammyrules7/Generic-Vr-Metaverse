extends Node

var ws: WebSocketPeer = WebSocketPeer.new()
var ws_url: String =  "ws://localhost:8080/ws"
var ws_last: WebSocketPeer.State


func _ready() -> void:
	print("WebSocket connecting to: ", ws_url)
	ws.connect_to_url(ws_url)

func _process(_delta: float) -> void:
	ws.poll()

	# ===== Event based WebSocket stuff =====

	var ws_state: WebSocketPeer.State = ws.get_ready_state()

	if ws_state == WebSocketPeer.State.STATE_CLOSED:
		ws.connect_to_url(ws_url)

	if ws_last != ws_state:
		ws_last = ws_state

		match  ws_state:
			WebSocketPeer.State.STATE_CLOSED:
				print("WebSocket closed with code: %i, Reason: %s" % ws.get_close_code(), ws.get_close_reason())
				print("Retrying WebSocket connection to: ", ws_url)
			WebSocketPeer.State.STATE_OPEN:
				print("WebSocket Connected!")
				sendtestpacket()
			WebSocketPeer.State.STATE_CLOSING:
				pass
			WebSocketPeer.State.STATE_CONNECTING:
				pass

	# ===== Packet Handler =====

	while ws.get_available_packet_count():
		_handle_packet()

func _handle_packet() -> void:
	var packet: PackedByteArray = ws.get_packet()
	print("Packet recived: ", packet.get_string_from_utf8())

func sendtestpacket() -> void:
	ws.send_text(JSON.stringify({
		"Sender": 1,
		"type": ServerPacket.Type.PacketDirect
	}))
