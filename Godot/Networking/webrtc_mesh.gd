class_name WebRTCMesh
extends RefCounted

const ICE_SERVERS := {"iceServers": [{"urls": ["stun:stun.l.google.com:19302"]}]}
const MAX_QUEUED_CANDIDATES := 64
const MAX_CANDIDATE_LENGTH := 16 * 1024

signal relay_requested(destination_id: int, value: PackedByteArray)
signal connection_error(reason: String)

var multiplayer_peer: WebRTCMultiplayerPeer
var connections: Dictionary[int, WebRTCPeerConnection] = {}
var remote_descriptions: Dictionary[int, bool] = {}
var queued_candidates: Dictionary[int, Array] = {}


func start(local_id: int) -> Error:
	multiplayer_peer = WebRTCMultiplayerPeer.new()
	return multiplayer_peer.create_mesh(local_id)


func close() -> void:
	connections.clear()
	remote_descriptions.clear()
	queued_candidates.clear()
	multiplayer_peer = null


func add_peer(peer_id: int, make_offer: bool) -> void:
	if multiplayer_peer == null or connections.has(peer_id):
		return
	var connection := WebRTCPeerConnection.new()
	if connection.initialize(ICE_SERVERS) != OK:
		connection_error.emit("Could not initialize peer %d" % peer_id)
		return
	connection.session_description_created.connect(_description_created.bind(peer_id))
	connection.ice_candidate_created.connect(_candidate_created.bind(peer_id))
	connections[peer_id] = connection
	queued_candidates[peer_id] = []
	if multiplayer_peer.add_peer(connection, peer_id) != OK:
		connections.erase(peer_id)
		connection_error.emit("Could not add peer %d to mesh" % peer_id)
		return
	if make_offer:
		connection.create_offer()


func remove_peer(peer_id: int) -> void:
	if multiplayer_peer != null:
		multiplayer_peer.remove_peer(peer_id)
	connections.erase(peer_id)
	remote_descriptions.erase(peer_id)
	queued_candidates.erase(peer_id)


func receive_relay(peer_id: int, value: PackedByteArray) -> void:
	var message = JSON.parse_string(value.get_string_from_utf8())
	if typeof(message) != TYPE_DICTIONARY or not message.has("kind"):
		connection_error.emit("Peer %d sent invalid signaling data" % peer_id)
		return
	if not connections.has(peer_id):
		add_peer(peer_id, false)
	var connection: WebRTCPeerConnection = connections.get(peer_id)
	if connection == null:
		return

	match message["kind"]:
		"description":
			if not _has_fields(message, ["type", "sdp"]):
				connection_error.emit("Peer %d sent an incomplete description" % peer_id)
				return
			if connection.set_remote_description(str(message["type"]), str(message["sdp"])) != OK:
				connection_error.emit("Peer %d sent an invalid description" % peer_id)
				return
			remote_descriptions[peer_id] = true
			for candidate in queued_candidates.get(peer_id, []):
				if connection.add_ice_candidate(candidate[0], candidate[1], candidate[2]) != OK:
					connection_error.emit("Could not apply a candidate from peer %d" % peer_id)
			queued_candidates[peer_id] = []
		"candidate":
			if not _has_fields(message, ["media", "index", "candidate"]):
				connection_error.emit("Peer %d sent an incomplete candidate" % peer_id)
				return
			var candidate := [str(message["media"]), int(message["index"]), str(message["candidate"])]
			if candidate[2].length() > MAX_CANDIDATE_LENGTH:
				connection_error.emit("Peer %d sent an oversized candidate" % peer_id)
				return
			if remote_descriptions.has(peer_id):
				if connection.add_ice_candidate(candidate[0], candidate[1], candidate[2]) != OK:
					connection_error.emit("Peer %d sent an invalid candidate" % peer_id)
			else:
				if queued_candidates[peer_id].size() >= MAX_QUEUED_CANDIDATES:
					connection_error.emit("Peer %d sent too many early candidates" % peer_id)
					return
				queued_candidates[peer_id].append(candidate)
		_:
			connection_error.emit("Peer %d sent unknown signaling data" % peer_id)


func _description_created(type: String, sdp: String, peer_id: int) -> void:
	var connection: WebRTCPeerConnection = connections.get(peer_id)
	if connection == null:
		return
	if connection.set_local_description(type, sdp) != OK:
		connection_error.emit("Could not set local description for peer %d" % peer_id)
		return
	_relay(peer_id, {"kind": "description", "type": type, "sdp": sdp})


func _candidate_created(media: String, index: int, candidate: String, peer_id: int) -> void:
	_relay(peer_id, {"kind": "candidate", "media": media, "index": index, "candidate": candidate})


func _relay(peer_id: int, message: Dictionary) -> void:
	relay_requested.emit(peer_id, JSON.stringify(message).to_utf8_buffer())


func _has_fields(message: Dictionary, fields: Array[String]) -> bool:
	for field in fields:
		if not message.has(field):
			return false
	return true
