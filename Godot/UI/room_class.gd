class_name roomClass extends RefCounted

# Shared room model used by both UI and Networking (RoomNetworking, VoiceChat).
# Fields mirror Server Room packet (Protocol/packets.proto): id, name,
# player_count, world_id, recovery_token. Adding a field requires updating
# _decode_room(), the proto, and the Go server together. Kept here (not under
# Networking/) for history reasons; do not move without updating all users.

var id: int
var room_name: String
var player_count: int
var world_id: String
var recovery_token: String

func _init(init_id: int, init_name: String, init_player_count: int, init_world_id := "floating_island", init_recovery_token := "") -> void:
	id = init_id
	room_name = init_name
	player_count = init_player_count
	world_id = init_world_id if not init_world_id.is_empty() else "floating_island"
	recovery_token = init_recovery_token
