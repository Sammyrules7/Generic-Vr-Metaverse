class_name PlayerManager
extends Node

signal local_player_spawned
## Scene/game components release avatar references before players are destroyed.
signal players_clearing

# The world owns player instances and spawn locations. The persistent replication
# endpoint owns RPCs, so packets can still arrive safely after this scene is freed.
const PLAYER_SCENE = preload("res://player/network_player.tscn")

@export var players: Node3D
@export var spawn_point: Marker3D

# Can be supplied by the scene or tests; the application uses its shared services.
var room_networking: RoomNetworking
var replication: PlayerReplication
var voice_chat: VoiceChat
var local_player: NetworkPlayer
var _spawn_generation := 0
var _peer_cache: Dictionary = {}


func get_player(peer_id: int) -> NetworkPlayer:
	var cached = _peer_cache.get(peer_id)
	if is_instance_valid(cached):
		return cached
	var player := players.get_node_or_null(str(peer_id)) as NetworkPlayer if is_instance_valid(players) else null
	if player != null:
		_peer_cache[peer_id] = player
	else:
		_peer_cache.erase(peer_id)
	return player


func _ready() -> void:
	if room_networking == null:
		room_networking = Networking.room_networking
	if replication == null:
		replication = Networking.player_replication
	if voice_chat == null:
		voice_chat = Networking.voice_chat
	room_networking.room_joined.connect(_room_joined)
	room_networking.room_left.connect(_clear_players)
	room_networking.peer_departed.connect(_remove_remote)
	replication.player_announced.connect(_spawn_remote)
	replication.name_received.connect(_set_player_name)
	replication.player_removed.connect(_remove_remote)
	replication.pose_received.connect(_apply_pose)
	if room_networking.current_room != null:
		_room_joined(room_networking.current_room)


func _exit_tree() -> void:
	# Unlike the networking autoload, this node exits during world changes.
	# Unregister the local avatar before freeing it so replication stops using it.
	_clear_players()


func _room_joined(_room: roomClass) -> void:
	_clear_players()
	var generation := _spawn_generation
	var point := spawn_point
	if get_parent().has_method("load_world"):
		point = await get_parent().load_world(_room.world_id)
	# A leave or a newer join can arrive while the scene is loading.
	if generation != _spawn_generation or not is_inside_tree():
		return
	if point == null:
		room_networking.network_error.emit("Could not load the room's world")
		return
	spawn_point = point
	var xr := XRServer.primary_interface
	var use_vr: bool = xr != null and xr.is_initialized()
	local_player = _spawn(multiplayer.get_unique_id(), use_vr, spawn_point.global_transform)
	replication.set_local_player(local_player)
	local_player_spawned.emit()


func _spawn(peer_id: int, use_vr: bool, initial_pose: Transform3D) -> NetworkPlayer:
	var player: NetworkPlayer = PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.use_vr = use_vr
	# Authority must be set before _ready() chooses whether to create local controls.
	player.set_multiplayer_authority(peer_id)
	players.add_child(player)
	player.global_transform = initial_pose
	_peer_cache[peer_id] = player
	if peer_id != multiplayer.get_unique_id():
		voice_chat.set_peer_anchor(peer_id, player.get_node("Avatar/Head"))
	return player


func _spawn_remote(peer_id: int, use_vr: bool, initial_pose: Transform3D) -> void:
	if local_player == null:
		return
	var existing := get_player(peer_id)
	if existing != null and existing.use_vr != use_vr:
		existing.free()
		_peer_cache.erase(peer_id)
		existing = null
	if existing == null:
		_spawn(peer_id, use_vr, initial_pose)


func _apply_pose(peer_id: int, body_pose: Transform3D, head_pose: Transform3D, left_pose: Transform3D, right_pose: Transform3D) -> void:
	var player := get_player(peer_id)
	# Unreliable poses can precede the reliable spawn message.
	if player != null and player != local_player:
		player.apply_pose(body_pose, head_pose, left_pose, right_pose)


func _remove_remote(peer_id: int) -> void:
	voice_chat.remove_peer_anchor(peer_id)
	_peer_cache.erase(peer_id)
	var player := players.get_node_or_null(str(peer_id))
	if player != null:
		player.free()


func _clear_players() -> void:
	_spawn_generation += 1
	players_clearing.emit()
	_peer_cache.clear()
	# An outgoing scene must not unregister a player installed by its replacement.
	if is_instance_valid(replication) and replication.local_player == local_player:
		replication.set_local_player(null)
	local_player = null
	if is_instance_valid(players):
		for player in players.get_children():
			voice_chat.remove_peer_anchor(int(player.name))
			player.free()


func _set_player_name(peer_id: int, display_name: String) -> void:
	var player := get_player(peer_id)
	if player != null:
		player.set_display_name(display_name)
