extends Node

const SIGNALING_URL = "ws://127.0.0.1:8080/ws"

var ws: WebSocketPeer = WebSocketPeer.new()
var ws_last: WebSocketPeer.State
var rtc_peer: WebRTCMultiplayerPeer = WebRTCMultiplayerPeer.new()

var my_id: int = 0
var peers: Dictionary = {}

func _input(event: InputEvent) -> void:
	if Input.is_action_pressed("JoinPublic"):
		print("JOINNMNNNN")
		ws.send_text("Hi")

func _ready():
	ws.connect_to_url(SIGNALING_URL)
	print("Connecting to signaling server...")

func _process(_delta):
	ws.poll()

	if ws_last != ws.get_ready_state():

		ws_last = ws.get_ready_state()

		if ws_last == WebSocketPeer.STATE_OPEN:
			print("Connected to signalling server.")

		if ws_last == WebSocketPeer.STATE_CLOSED:
			print("WebSocket disconnected. Retrying...")
			ws.connect_to_url(SIGNALING_URL)
