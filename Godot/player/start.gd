extends Node

@export var desktop_player_scene: PackedScene = preload("res://player/desktop_player.tscn")
@export var vr_player_scene: PackedScene = preload("res://player/vr_player.tscn")

var local_player: Node3D


func _ready() -> void:
	Networking.room_joined.connect(_room_joined)
	Networking.room_left.connect(_room_left)
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)


func _room_joined(_room: roomClass) -> void:
	call_deferred("_spawn_local_player")


func _spawn_local_player() -> void:
	var players := _players_node()
	var spawn_point := get_node_or_null("/root/Main/World/SpawnPoint") as Marker3D
	if players == null or spawn_point == null or Networking.client_id == 0:
		push_error("World is missing Players or SpawnPoint")
		return
	_clear_players()
	var xr_interface := XRServer.find_interface("OpenXR")
	var scene := vr_player_scene if xr_interface and xr_interface.initialize() else desktop_player_scene
	local_player = scene.instantiate()
	local_player.name = str(Networking.client_id)
	local_player.set_multiplayer_authority(Networking.client_id)
	players.add_child(local_player)
	local_player.global_transform = spawn_point.global_transform


func _peer_connected(peer_id: int) -> void:
	if local_player != null:
		announce_player.rpc_id(peer_id, Networking.client_id, local_player.global_transform)


@rpc("any_peer", "call_remote", "reliable")
func announce_player(peer_id: int, initial_transform: Transform3D) -> void:
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	var players := _players_node()
	if players == null or players.get_node_or_null(str(peer_id)) != null:
		return
	var player: Node3D = desktop_player_scene.instantiate()
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	players.add_child(player)
	player.global_transform = initial_transform


func _peer_disconnected(peer_id: int) -> void:
	var players := _players_node()
	if players == null:
		return
	var player := players.get_node_or_null(str(peer_id))
	if player != null:
		player.queue_free()


func _room_left() -> void:
	_clear_players()


func _clear_players() -> void:
	local_player = null
	var players := _players_node()
	if players == null:
		return
	for player in players.get_children():
		player.free()


func _players_node() -> Node:
	return get_node_or_null("/root/Main/Players")
