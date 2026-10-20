extends Area3D

@export var spawn_point: Marker3D


func _ready() -> void:
	body_exited.connect(_on_body_exited)


func _on_body_exited(body: Node3D) -> void:
	var player := body as NetworkPlayer
	if player == null or not player.is_multiplayer_authority():
		return
	await get_tree().create_timer(2.5).timeout
	# Leaving a room may have removed this player while the timer was running.
	if not is_instance_valid(player) or not player.is_inside_tree():
		return
	player.global_transform = spawn_point.global_transform
	player.velocity = Vector3.ZERO
