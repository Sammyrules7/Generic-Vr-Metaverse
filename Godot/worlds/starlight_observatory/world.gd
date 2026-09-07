extends Node3D
## Shared recovery for the offline preview and the platform's network players.

var last_moon_direction := Vector3.ZERO


func _process(_delta: float) -> void:
	# Keep cloud highlights aligned too when the moon is rotated in the inspector.
	var direction: Vector3 = $Moonlight.global_basis.z.normalized()
	if not direction.is_equal_approx(last_moon_direction):
		($SeaOfClouds.material_override as ShaderMaterial).set_shader_parameter("moon_direction", direction)
		last_moon_direction = direction


func _physics_process(_delta: float) -> void:
	var players := get_parent().get_node_or_null("Players")
	if players == null:
		return
	for player in players.get_children():
		if player is CharacterBody3D and player.is_multiplayer_authority():
			if to_local(player.global_position).y < -8:
				player.global_transform = $SpawnPoint.global_transform
				player.velocity = Vector3.ZERO
