extends Node3D
## The normal room flow owns player creation. This world only handles recovery.

func _physics_process(_delta: float) -> void:
	var players := get_node_or_null("../Players")
	if players == null:
		return
	for player in players.get_children():
		if player is CharacterBody3D and player.is_multiplayer_authority():
			var local_position := to_local(player.global_position)
			if local_position.y < -4 or absf(local_position.x) > 15 or absf(local_position.z) > 22:
				player.global_transform = $SpawnPoint.global_transform
				player.velocity = Vector3.ZERO


func _exit_tree() -> void:
	# Release the looping playback explicitly when switching worlds.
	var ambience := get_node_or_null("Waterfall ambience") as AudioStreamPlayer3D
	if ambience:
		ambience.stop()
		ambience.stream = null
