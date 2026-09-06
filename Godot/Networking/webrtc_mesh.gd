class_name WebRTCMesh
extends RefCounted

const Packets = preload("res://Networking/Generated/Packets.gd")
const ICE_SERVERS := {"iceServers": [{"urls": ["stun:stun.l.google.com:19302"]}]}
const MAX_QUEUED_CANDIDATES := 64

signal packet_created(packet: Packets.ClientPacket)
signal connection_error(reason: String)

var multiplayer_peer: WebRTCMultiplayerPeer
var session_id: int
# Peer IDs survive room changes; session IDs identify a particular membership.
var peer_sessions: Dictionary[int, int] = {}
# ICE callbacks can precede SDP processing. Keep candidates until the remote
# description is applied; removing the entry also marks that peer as ready.
var queued_candidates: Dictionary[int, Array] = {}


func start(local_id: int, in_session: int) -> Error:
	session_id = in_session
	multiplayer_peer = WebRTCMultiplayerPeer.new()
	return multiplayer_peer.create_mesh(local_id)


func close() -> void:
	if multiplayer_peer != null:
		multiplayer_peer.close()
	queued_candidates.clear()
	peer_sessions.clear()
	multiplayer_peer = null


func add_peer(peer: Packets.Peer, make_offer: bool) -> void:
	var peer_id := peer.get_id()
	if multiplayer_peer == null:
		return
	if peer_sessions.get(peer_id) == peer.get_session_id() and multiplayer_peer.has_peer(peer_id):
		return
	remove_peer(peer_id)
	var connection := WebRTCPeerConnection.new()
	if connection.initialize(ICE_SERVERS) != OK:
		connection_error.emit("Could not initialize peer %d" % peer_id)
		return
	connection.session_description_created.connect(_description_created.bind(peer_id, peer.get_session_id()))
	connection.ice_candidate_created.connect(_candidate_created.bind(peer_id, peer.get_session_id()))
	if multiplayer_peer.add_peer(connection, peer_id) != OK:
		connection.close()
		connection_error.emit("Could not add peer %d to mesh" % peer_id)
		return
	peer_sessions[peer_id] = peer.get_session_id()
	queued_candidates[peer_id] = []
	if make_offer:
		if connection.create_offer() != OK:
			remove_peer(peer_id)
			connection_error.emit("Could not create offer for peer %d" % peer_id)


func remove_peer(peer_id: int) -> void:
	var connection := _get_connection(peer_id)
	if connection != null:
		connection.close()
	if multiplayer_peer != null and multiplayer_peer.has_peer(peer_id):
		multiplayer_peer.remove_peer(peer_id)
	queued_candidates.erase(peer_id)
	peer_sessions.erase(peer_id)


func _get_connection(peer_id: int) -> WebRTCPeerConnection:
	# Godot owns the connection registry and can remove failed peers while polling.
	# A second registry here would retain connections no longer in the mesh.
	if multiplayer_peer == null or not multiplayer_peer.has_peer(peer_id):
		return null
	return multiplayer_peer.get_peer(peer_id)["connection"]


func receive_relay(relay: Packets.ServerRelay) -> void:
	if relay.get_destination_session_id() != session_id or relay.get_sender_session_id() != peer_sessions.get(relay.get_sender_id(), 0):
		return
	var peer_id: int = relay.get_sender_id()
	# Membership notifications precede relays on the ordered signaling socket.
	var connection := _get_connection(peer_id)
	if connection == null:
		return

	match relay.get_signal_case():
		Packets.ServerRelay.SignalCase.DESCRIPTION:
			var description = relay.get_description()
			if connection.set_remote_description(description.get_type(), description.get_sdp()) != OK:
				connection_error.emit("Peer %d sent an invalid description" % peer_id)
				return
			for candidate in queued_candidates.get(peer_id, []):
				if connection.add_ice_candidate(candidate[0], candidate[1], candidate[2]) != OK:
					connection_error.emit("Could not apply a candidate from peer %d" % peer_id)
			queued_candidates.erase(peer_id)
		Packets.ServerRelay.SignalCase.CANDIDATE:
			var message = relay.get_candidate()
			var candidate := [message.get_media(), message.get_index(), message.get_candidate()]
			if not queued_candidates.has(peer_id):
				if connection.add_ice_candidate(candidate[0], candidate[1], candidate[2]) != OK:
					connection_error.emit("Peer %d sent an invalid candidate" % peer_id)
			else:
				if queued_candidates[peer_id].size() >= MAX_QUEUED_CANDIDATES:
					connection_error.emit("Peer %d sent too many early candidates" % peer_id)
					return
				queued_candidates[peer_id].append(candidate)
		_:
			connection_error.emit("Peer %d sent empty signaling data" % peer_id)


func _description_created(type: String, sdp: String, peer_id: int, peer_session: int) -> void:
	# A callback from an old connection must not signal the replacement for that ID.
	if peer_sessions.get(peer_id) != peer_session:
		return
	var connection := _get_connection(peer_id)
	if connection == null:
		return
	if connection.set_local_description(type, sdp) != OK:
		connection_error.emit("Could not set local description for peer %d" % peer_id)
		return
	var packet := Packets.ClientPacket.new()
	var relay = packet.new_relay()
	relay.set_destination_id(peer_id)
	relay.set_sender_session_id(session_id)
	relay.set_destination_session_id(peer_session)
	var description = relay.new_description()
	description.set_type(type)
	description.set_sdp(sdp)
	packet_created.emit(packet)


func _candidate_created(media: String, index: int, candidate: String, peer_id: int, peer_session: int) -> void:
	if peer_sessions.get(peer_id) != peer_session or _get_connection(peer_id) == null:
		return
	var packet := Packets.ClientPacket.new()
	var relay = packet.new_relay()
	relay.set_destination_id(peer_id)
	relay.set_sender_session_id(session_id)
	relay.set_destination_session_id(peer_session)
	var message = relay.new_candidate()
	message.set_media(media)
	message.set_index(index)
	message.set_candidate(candidate)
	packet_created.emit(packet)
