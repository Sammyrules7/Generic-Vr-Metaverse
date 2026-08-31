class_name WebRTCMesh
extends RefCounted

const Packets = preload("res://Networking/Generated/Packets.gd")
const ICE_SERVERS := {"iceServers": [{"urls": ["stun:stun.l.google.com:19302"]}]}
const MAX_QUEUED_CANDIDATES := 64

signal packet_created(packet: Packets.ClientPacket)
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


func receive_relay(relay: Packets.ServerRelay) -> void:
	var peer_id: int = relay.get_sender_id()
	if not connections.has(peer_id):
		add_peer(peer_id, false)
	var connection: WebRTCPeerConnection = connections.get(peer_id)
	if connection == null:
		return

	match relay.get_signal_case():
		Packets.ServerRelay.SignalCase.DESCRIPTION:
			var description = relay.get_description()
			if connection.set_remote_description(description.get_type(), description.get_sdp()) != OK:
				connection_error.emit("Peer %d sent an invalid description" % peer_id)
				return
			remote_descriptions[peer_id] = true
			for candidate in queued_candidates.get(peer_id, []):
				if connection.add_ice_candidate(candidate[0], candidate[1], candidate[2]) != OK:
					connection_error.emit("Could not apply a candidate from peer %d" % peer_id)
			queued_candidates[peer_id] = []
		Packets.ServerRelay.SignalCase.CANDIDATE:
			var message = relay.get_candidate()
			var candidate := [message.get_media(), message.get_index(), message.get_candidate()]
			if remote_descriptions.has(peer_id):
				if connection.add_ice_candidate(candidate[0], candidate[1], candidate[2]) != OK:
					connection_error.emit("Peer %d sent an invalid candidate" % peer_id)
			else:
				if queued_candidates[peer_id].size() >= MAX_QUEUED_CANDIDATES:
					connection_error.emit("Peer %d sent too many early candidates" % peer_id)
					return
				queued_candidates[peer_id].append(candidate)
		_:
			connection_error.emit("Peer %d sent empty signaling data" % peer_id)


func _description_created(type: String, sdp: String, peer_id: int) -> void:
	var connection: WebRTCPeerConnection = connections.get(peer_id)
	if connection == null:
		return
	if connection.set_local_description(type, sdp) != OK:
		connection_error.emit("Could not set local description for peer %d" % peer_id)
		return
	var packet := Packets.ClientPacket.new()
	var relay = packet.new_relay()
	relay.set_destination_id(peer_id)
	var description = relay.new_description()
	description.set_type(type)
	description.set_sdp(sdp)
	packet_created.emit(packet)


func _candidate_created(media: String, index: int, candidate: String, peer_id: int) -> void:
	var packet := Packets.ClientPacket.new()
	var relay = packet.new_relay()
	relay.set_destination_id(peer_id)
	var message = relay.new_candidate()
	message.set_media(media)
	message.set_index(index)
	message.set_candidate(candidate)
	packet_created.emit(packet)
