extends Node3D
## Shared recovery for the offline preview and the platform's network players.

var last_moon_direction := Vector3.ZERO
var _players_cache: Node3D
var _sea_material: ShaderMaterial


func _ready() -> void:
	_sea_material = $SeaOfClouds.material_override as ShaderMaterial


func _process(_delta: float) -> void:
	# Keep cloud highlights aligned too when the moon is rotated in the inspector.
	var direction: Vector3 = $Moonlight.global_basis.z.normalized()
	if not direction.is_equal_approx(last_moon_direction):
		if _sea_material == null or not is_instance_valid(_sea_material):
			_sea_material = $SeaOfClouds.material_override as ShaderMaterial
		if _sea_material != null:
			_sea_material.set_shader_parameter("moon_direction", direction)
		last_moon_direction = direction


func _physics_process(_delta: float) -> void:
	if _players_cache == null or not is_instance_valid(_players_cache):
		_players_cache = get_parent().get_node_or_null("Players") as Node3D
		if _players_cache == null:
			return
	for player in _players_cache.get_children():
		if player is CharacterBody3D and player.is_multiplayer_authority():
			if to_local(player.global_position).y < -8:
				player.global_transform = $SpawnPoint.global_transform
				player.velocity = Vector3.ZERO
