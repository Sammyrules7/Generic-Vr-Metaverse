extends Node

signal room_opend
signal room_closed

const SIGNALING_URL = "ws://127.0.0.1:8080/ws"

var ws: WebSocketPeer = WebSocketPeer.new()
var ws_last: WebSocketPeer.State
var webrtc_conn: WebRTCPeerConnection = WebRTCPeerConnection.new()
var rtc_peer: WebRTCMultiplayerPeer = WebRTCMultiplayerPeer.new()

var my_id: int = 0
var peers: Dictionary = {}

func _input(_event: InputEvent) -> void:
	if Input.is_action_pressed("JoinPublic"):
		print("JOINNMNNNN")
		ws.send_text("Hi")

func _ready() -> void:
	ws.connect_to_url(SIGNALING_URL)
	print("Connecting to signaling server...")

func _process(_delta: float) -> void:
	ws.poll()

	if ws.State.STATE_OPEN:
		while ws.get_available_packet_count() > 0:
			_process_packet()

	if ws_last != ws.get_ready_state():

		ws_last = ws.get_ready_state()

		if ws_last == WebSocketPeer.STATE_OPEN:
			print("Connected to signalling server.")
			send_test_packet()

		if ws_last == WebSocketPeer.STATE_CLOSED:
			print("WebSocket disconnected. Retrying...")
			ws.connect_to_url(SIGNALING_URL)

func _process_packet() -> void:
	var packet: PackedByteArray = ws.get_packet()
	print("PACKETTTT")

	if !ws.was_string_packet():
		printerr("Packet recived was not text.")
		return

	var json_packet: Dictionary = JSON.parse_string(packet.get_string_from_utf8())
	if json_packet == null:
		printerr("Packet failed to parse")
		return
	print(json_packet)

	match json_packet["type"]:
		"Init":
			my_id = json_packet["data"]
			print("My id %d" % my_id)
		"test":
			print("TESTTTTT")

func _on_offer_received(offer: String) -> void:
	webrtc_conn.set_remote_description(offer, offer)

func listen_lobbies() -> void:
	pass

func silence_lobbies() -> void:
	pass

func join_room(_id: int) -> void:
	pass

func create_room() -> void:

	print("Creating room!")

	var packet: Dictionary = {
    	"type": "create_room",
    	"payload": "AWAWAWAWA",
    	"sender": 1,
    	"target": 2,
	}

	ws.send_text(JSON.stringify(packet))



func send_test_packet() -> void:
	var packet: Dictionary = {
    	"type": "generic",
    	"payload": "AWAWAWAWA",
    	"sender": 1,
    	"target": 2,
	}

	ws.send_text(JSON.stringify(packet))
