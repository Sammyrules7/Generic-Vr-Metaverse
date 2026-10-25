class_name PlayerReplication
extends Node

# This RPC endpoint outlives world scenes. Scene-owned managers subscribe to it.
signal player_announced(peer_id: int, use_vr: bool, initial_pose: Transform3D)
signal name_received(peer_id: int, display_name: String)
signal avatar_received(peer_id: int, avatar_id: String)
signal player_removed(peer_id: int)
signal pose_received(peer_id: int, body_pose: Transform3D, head_pose: Transform3D, left_pose: Transform3D, right_pose: Transform3D)

var local_player: NetworkPlayer
var _avatar_by_peer: Dictionary = {}
var _desired_avatar_by_peer: Dictionary = {}
var avatar_transfer: AvatarTransfer
var _local_avatar_id := "default"

const REPLICATION_HZ := 15.0
const POSITION_EPSILON := 0.002
const ANGLE_EPSILON := 0.002
# A single-tick jump this large is a teleport/respawn, not locomotion: the
# body's Motor keeps simulating between 15Hz gates, so a teleported exact pose
# would otherwise never be sampled. Send it immediately instead of letting the
# rate gate smear it into fallen/interpolated poses.
const TELEPORT_DISTANCE := 0.5
var _send_accum := 0.0
var _last_body := Transform3D.IDENTITY
var _last_head := Transform3D.IDENTITY
var _last_left := Transform3D.IDENTITY
var _last_right := Transform3D.IDENTITY
var _have_last := false
var _cached_transport: WebRTCMultiplayerPeer


func _ready() -> void:
	_local_avatar_id = PlayerProfile.avatar_id
	avatar_transfer = AvatarTransfer.new()
	avatar_transfer.name = "AvatarTransfer"
	avatar_transfer.equipped_id = func(): return _local_avatar_id
	avatar_transfer.avatar_ready.connect(_custom_avatar_ready)
	avatar_transfer.avatar_failed.connect(func(peer: int, id: String, reason: String): AvatarService.record_event(id, "remote avatar failed", "peer %d: %s" % [peer, reason]))
	add_child(avatar_transfer)
	multiplayer.peer_connected.connect(_peer_connected)
	# Despawn is owned by room membership (explicit leave, despawn RPC, or an
	# expired transport recovery), never by the raw data-channel signal: a
	# dropped channel whose peer is still in the room must repair, not vanish.


func set_local_player(player: NetworkPlayer) -> void:
	if player == null and local_player != null and not multiplayer.get_peers().is_empty():
		despawn_player.rpc()
	local_player = player
	if local_player != null:
		_local_avatar_id = PlayerProfile.avatar_id
		for peer_id in multiplayer.get_peers():
			_peer_connected(peer_id)


func _peer_connected(peer_id: int) -> void:
	if _desired_avatar_by_peer.has(peer_id):
		_receive_avatar(peer_id, _desired_avatar_by_peer[peer_id])
	if local_player != null:
		spawn_player.rpc_id(peer_id, local_player.use_vr, local_player.global_transform, PlayerProfile.display_name, AvatarCatalog.replication_id(_local_avatar_id))
		# Also used after a world reload: the peer may already be connected, so we
		# cannot rely on another peer_connected event to repopulate the new scene.
		request_player.rpc_id(peer_id)


@rpc("any_peer", "call_remote", "reliable")
func request_player() -> void:
	if local_player != null:
		spawn_player.rpc_id(multiplayer.get_remote_sender_id(), local_player.use_vr, local_player.global_transform, PlayerProfile.display_name, AvatarCatalog.replication_id(_local_avatar_id))


@rpc("any_peer", "call_remote", "reliable")
func despawn_player() -> void:
	forget_avatar(multiplayer.get_remote_sender_id())
	player_removed.emit(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func spawn_player(use_vr: bool, initial_pose: Transform3D, display_name := "Explorer", avatar_id := "default") -> void:
	# Take identity from the transport, never a claimed ID inside the payload.
	var peer_id := multiplayer.get_remote_sender_id()
	if multiplayer.get_peers().has(peer_id) and initial_pose.is_finite():
		player_announced.emit(peer_id, use_vr, initial_pose)
		name_received.emit(peer_id, display_name.strip_edges().left(24))
		_receive_avatar(peer_id, avatar_id)


func broadcast_avatar(id: String) -> void:
	_local_avatar_id = AvatarCatalog.replication_id(id)
	if local_player != null and AvatarCatalog.has_avatar(id) and not multiplayer.get_peers().is_empty():
		announce_avatar.rpc(AvatarCatalog.replication_id(id))


@rpc("any_peer", "call_remote", "reliable")
func announce_avatar(id: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if multiplayer.get_peers().has(sender):
		_receive_avatar(sender, id)


func _receive_avatar(peer_id: int, id: String) -> void:
	_desired_avatar_by_peer[peer_id] = id.left(64)
	if AvatarLocalLibrary.valid_id(id):
		AvatarService.record_event(id, "remote custom announcement", "peer %d | available %s" % [peer_id, AvatarService.remote_available(id)])
		if AvatarService.remote_available(id):
			if avatar_transfer != null:
				avatar_transfer.cancel_receive(peer_id)
			_avatar_by_peer[peer_id] = id
			avatar_received.emit(peer_id, id)
		elif avatar_transfer != null:
			_avatar_by_peer[peer_id] = "default"
			avatar_received.emit(peer_id, "default")
			avatar_transfer.ensure(peer_id, id)
		return
	if avatar_transfer != null:
		avatar_transfer.cancel_receive(peer_id)
	var valid_id := AvatarCatalog.replication_id(id)
	AvatarService.record_event(id, "remote announcement", "Peer %d: %s" % [peer_id, "Unknown ID; using Explorer" if id != valid_id else "accepted"])
	_avatar_by_peer[peer_id] = valid_id
	avatar_received.emit(peer_id, valid_id)


func _custom_avatar_ready(peer_id: int, id: String) -> void:
	if _desired_avatar_by_peer.get(peer_id, "") == id and multiplayer.get_peers().has(peer_id):
		_avatar_by_peer[peer_id] = id
		avatar_received.emit(peer_id, id)


func forget_avatar(peer_id: int) -> void:
	_avatar_by_peer.erase(peer_id)
	_desired_avatar_by_peer.erase(peer_id)
	if avatar_transfer != null:
		avatar_transfer.cancel_receive(peer_id)


func _physics_process(delta: float) -> void:
	if local_player == null:
		_have_last = false
		return
	_send_accum += delta
	var early_body := local_player.global_transform
	var teleported := _have_last and early_body.origin.distance_to(_last_body.origin) > TELEPORT_DISTANCE
	if not teleported and _send_accum < 1.0 / REPLICATION_HZ:
		return
	# get_peers() allocates; a single call per tick at 15Hz instead of 60Hz.
	var peers := multiplayer.get_peers()
	if peers.is_empty():
		_send_accum = 0.0
		return
	var controls := local_player.controls
	if controls == null:
		return
	var body_pose := local_player.global_transform
	var inv_body := body_pose.affine_inverse()
	var head_pose := inv_body * controls.head.global_transform if controls.head != null else Transform3D.IDENTITY
	var left_pose := controls.hand_pose("left") if controls.left_hand != null else Transform3D.IDENTITY
	var right_pose := controls.hand_pose("right") if controls.right_hand != null else Transform3D.IDENTITY
	if _have_last and not _pose_changed(body_pose, head_pose, left_pose, right_pose):
		_send_accum = 0.0
		return
	_send_accum = 0.0
	_last_body = body_pose
	_last_head = head_pose
	_last_left = left_pose
	_last_right = right_pose
	_have_last = true
	for peer_id in peers:
		# A data channel can close just before the next peer_disconnected event.
		# Skip that peer without interrupting pose delivery to the rest of the room.
		if _channels_open(peer_id):
			sync_player.rpc_id(peer_id, body_pose, head_pose, left_pose, right_pose)


func _pose_changed(body_pose: Transform3D, head_pose: Transform3D, left_pose: Transform3D, right_pose: Transform3D) -> bool:
	return not _transform_similar(_last_body, body_pose) or not _transform_similar(_last_head, head_pose) or not _transform_similar(_last_left, left_pose) or not _transform_similar(_last_right, right_pose)


func _transform_similar(a: Transform3D, b: Transform3D) -> bool:
	if a.origin.distance_squared_to(b.origin) > POSITION_EPSILON * POSITION_EPSILON:
		return false
	# Basis column comparison avoids quat allocation on the hot path.
	for i in 3:
		if a.basis[i].distance_squared_to(b.basis[i]) > ANGLE_EPSILON * ANGLE_EPSILON:
			return false
	return true


func _channels_open(peer_id: int) -> bool:
	# The mesh is replaced on every rejoin while the old RefCounted object stays
	# alive via this cache. Refresh whenever the active peer object changes.
	var current := multiplayer.multiplayer_peer
	if current != _cached_transport:
		_cached_transport = current as WebRTCMultiplayerPeer
	var transport := _cached_transport
	if transport == null:
		return true
	# Only gate on peer membership, not per-channel state: extra channels can
	# flap or renegotiate (SCTP resets in the wild) while the pose channel is
	# healthy. Gating on every channel turned a flapping extra channel into a
	# permanent pose blackout. A send to a stale peer just fails that RPC.
	return transport.has_peer(peer_id)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func sync_player(body_pose: Transform3D, head_pose: Transform3D, left_pose: Transform3D, right_pose: Transform3D) -> void:
	# New poses supersede old ones; retransmitting lost movement would add latency.
	# Reject NaN/Inf before they can contaminate scene transforms.
	if body_pose.is_finite() and head_pose.is_finite() and left_pose.is_finite() and right_pose.is_finite():
		pose_received.emit(multiplayer.get_remote_sender_id(), body_pose, head_pose, left_pose, right_pose)


func replay_avatar(peer_id: int) -> void:
	if _avatar_by_peer.has(peer_id):
		avatar_received.emit(peer_id, _avatar_by_peer[peer_id])


func avatar_progress(peer_id: int) -> Dictionary:
	var transfer := avatar_transfer.progress(peer_id) if avatar_transfer != null else {}
	if not transfer.is_empty():
		return transfer
	var id: String = _desired_avatar_by_peer.get(peer_id, "")
	var loading := AvatarService.download_progress(id)
	if not loading.is_empty():
		loading["active"] = true
	return loading


func clear_remote_avatars() -> void:
	for peer_id in _desired_avatar_by_peer.keys():
		forget_avatar(peer_id)
