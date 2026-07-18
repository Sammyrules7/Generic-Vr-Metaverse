extends Node

const SIGNALING_URL = "ws://127.0.0.1:8080/ws"

var ws: WebSocketPeer = WebSocketPeer.new()
var rtc_peer: WebRTCMultiplayerPeer = WebRTCMultiplayerPeer.new()

var my_id: int = 0
var peers: Dictionary = {} # Format: { remote_id (int) : WebRTCPeerConnection }

func _input(event: InputEvent) -> void:
	if Input.is_action_pressed("JoinPublic"):
		print("JOINNMNNNN")

func _ready():
	ws.connect_to_url(SIGNALING_URL)
	print("Connecting to signaling server...")

func _process(_delta):
	ws.poll()
	var state = ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		while ws.get_available_packet_count() > 0:
			var packet = ws.get_packet()
			_on_signaling_message(packet.get_string_from_utf8())
	elif state == WebSocketPeer.STATE_CLOSED:
		print("WebSocket disconnected. Retrying...")
		ws.connect_to_url(SIGNALING_URL)


func _on_signaling_message(text: String):
	var json = JSON.parse_string(text)
	if not json:
		return

	var type = json.get("type", "")
	var sender_id = int(json.get("sender_id", 0))
	var data = json.get("data", null)

	match type:
		"id":
			my_id = sender_id
			print("Connected! Assigned Peer ID: ", my_id)

			# Initialize high-level mesh peer
			rtc_peer.create_mesh(my_id)
			multiplayer.multiplayer_peer = rtc_peer

			# Connect engine-level multiplayer signals
			multiplayer.peer_connected.connect(_on_multiplayer_peer_connected)
			multiplayer.peer_disconnected.connect(_on_multiplayer_peer_disconnected)

			# Setup connections for all existing peers already in lobby
			if data is Array:
				for peer_id in data:
					_setup_connection(int(peer_id))

		"peer_joined":
			print("New peer joined lobby: ", sender_id)
			_setup_connection(sender_id)

		"peer_left":
			print("Peer left lobby: ", sender_id)
			_disconnect_peer(sender_id)

		"offer":
			if peers.has(sender_id):
				peers[sender_id].set_remote_description("offer", data)

		"answer":
			if peers.has(sender_id):
				peers[sender_id].set_remote_description("answer", data)

		"candidate":
			if peers.has(sender_id):
				peers[sender_id].add_ice_candidate(data.get("media"), data.get("index"), data.get("name"))

func _setup_connection(remote_id: int):
	if peers.has(remote_id):
		return

	var peer_conn = WebRTCPeerConnection.new()

	# Pass STUN/TURN configurations here.
	# stun.l.google.com is great for local testing over different home LANs.
	peer_conn.initialize({
		"iceServers": [
			{ "urls": ["stun:stun.l.google.com:19302"] }
		]
	})

	# Bind signaling events with the target peer's ID attached
	peer_conn.session_description_created.connect(_on_sdp_created.bind(remote_id))
	peer_conn.ice_candidate_created.connect(_on_ice_candidate_created.bind(remote_id))

	# Feed the connection raw interface to Godot's High-Level wrapper
	rtc_peer.add_peer(peer_conn, remote_id)
	peers[remote_id] = peer_conn

	# The lower ID initiates the connection. If we have the lower ID, we create the offer.
	if my_id < remote_id:
		peer_conn.create_offer()

func _on_sdp_created(type: String, sdp: String, remote_id: int):
	if peers.has(remote_id):
		peers[remote_id].set_local_description(type, sdp)
		_send_signaling_packet(type, remote_id, sdp)

func _on_ice_candidate_created(media: String, index: int, name: String, remote_id: int):
	var candidate_payload = {
		"media": media,
		"index": index,
		"name": name
	}
	_send_signaling_packet("candidate", remote_id, candidate_payload)

func _send_signaling_packet(type: String, target_id: int, data):
	var payload = {
		"type": type,
		"sender_id": my_id,
		"target_id": target_id,
		"data": data
	}
	ws.send_text(JSON.stringify(payload))

func _disconnect_peer(remote_id: int):
	if peers.has(remote_id):
		rtc_peer.remove_peer(remote_id)
		peers[remote_id].close()
		peers.erase(remote_id)

# --- Godot High-Level Multiplayer Signals ---
func _on_multiplayer_peer_connected(peer_id: int):
	print("SUCCESS: WebRTC handshake complete. Connected to game peer: ", peer_id)
	# Spawn player avatars here!

func _on_multiplayer_peer_disconnected(peer_id: int):
	print("Game peer disconnected: ", peer_id)
	_disconnect_peer(peer_id)
