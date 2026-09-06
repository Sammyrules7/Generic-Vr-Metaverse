class_name PlayerReplication
extends Node

# This RPC endpoint outlives world scenes. Scene-owned managers subscribe to it.
signal player_announced(peer_id: int, use_vr: bool, initial_pose: Transform3D)
signal player_removed(peer_id: int)
signal pose_received(peer_id: int, body_pose: Transform3D, head_pose: Transform3D, left_pose: Transform3D, right_pose: Transform3D)

var local_player: NetworkPlayer


func _ready() -> void:
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(player_removed.emit)


func set_local_player(player: NetworkPlayer) -> void:
	if player == null and local_player != null and not multiplayer.get_peers().is_empty():
		despawn_player.rpc()
	local_player = player
	if local_player != null:
		for peer_id in multiplayer.get_peers():
			_peer_connected(peer_id)


func _peer_connected(peer_id: int) -> void:
	if local_player != null:
		spawn_player.rpc_id(peer_id, local_player.use_vr, local_player.global_transform)
		# Also used after a world reload: the peer may already be connected, so we
		# cannot rely on another peer_connected event to repopulate the new scene.
		request_player.rpc_id(peer_id)


@rpc("any_peer", "call_remote", "reliable")
func request_player() -> void:
	if local_player != null:
		spawn_player.rpc_id(multiplayer.get_remote_sender_id(), local_player.use_vr, local_player.global_transform)


@rpc("any_peer", "call_remote", "reliable")
func despawn_player() -> void:
	player_removed.emit(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func spawn_player(use_vr: bool, initial_pose: Transform3D) -> void:
	# Take identity from the transport, never a claimed ID inside the payload.
	var peer_id := multiplayer.get_remote_sender_id()
	if multiplayer.get_peers().has(peer_id) and initial_pose.is_finite():
		player_announced.emit(peer_id, use_vr, initial_pose)


func _physics_process(_delta: float) -> void:
	if local_player == null or multiplayer.get_peers().is_empty():
		return
	var controls := local_player.controls
	sync_player.rpc(local_player.global_transform, controls.pose(controls.head), controls.pose(controls.left_hand), controls.pose(controls.right_hand))


@rpc("any_peer", "call_remote", "unreliable_ordered")
func sync_player(body_pose: Transform3D, head_pose: Transform3D, left_pose: Transform3D, right_pose: Transform3D) -> void:
	# New poses supersede old ones; retransmitting lost movement would add latency.
	# Reject NaN/Inf before they can contaminate scene transforms.
	if body_pose.is_finite() and head_pose.is_finite() and left_pose.is_finite() and right_pose.is_finite():
		pose_received.emit(multiplayer.get_remote_sender_id(), body_pose, head_pose, left_pose, right_pose)
