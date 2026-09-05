extends Node3D
## Shared recovery for the offline preview and the platform's network players.


func _physics_process(_delta: float) -> void:
	var players := get_parent().get_node_or_null("Players")
	if players == null:
		return
	for player in players.get_children():
		if player is CharacterBody3D and player.is_multiplayer_authority():
			if to_local(player.global_position).y < -8:
				player.global_transform = $SpawnPoint.global_transform
				player.velocity = Vector3.ZERO
