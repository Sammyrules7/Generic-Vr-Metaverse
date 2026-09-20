extends SceneTree
## Headless movement and collision checks for the compact bench overlook.
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func walk_toward(player: CharacterBody3D, target: Vector3, frames: int) -> void:
	for frame in frames:
		var direction := target - player.global_position
		direction.y = 0
		direction = direction.normalized() if direction.length() > 0.15 else Vector3.ZERO
		player.velocity.x = direction.x * 5.0
		player.velocity.z = direction.z * 5.0
		player.velocity.y = -1.0 if player.is_on_floor() else player.velocity.y - 9.8 / 60.0
		player.move_and_slide()
		await physics_frame

func place_player(player: CharacterBody3D, world: Node3D, x: float, z: float) -> void:
	player.global_position = world.to_global(world.ground(x, z, 0.2))
	player.velocity = Vector3.ZERO
	await walk_toward(player, player.global_position, 30)

func run() -> void:
	var scene := load("res://worlds/prairie_crossing/preview.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	var world := scene.get_node("World") as Node3D
	var player := scene.get_node("Players/PreviewPlayer") as CharacterBody3D
	var spawn := world.get_node("SpawnPoint") as Marker3D
	var catalog = load("res://worlds/world_catalog.gd")
	check(catalog.WORLDS.has("prairie_crossing"), "Prairie Crossing must be selectable in the world catalog")
	if catalog.WORLDS.has("prairie_crossing"):
		check(catalog.WORLDS["prairie_crossing"].scene.resource_path == "res://worlds/prairie_crossing/prairie_crossing.tscn", "Catalog must load the Prairie Crossing scene")
	for i in 60:
		await physics_frame
	check(player.is_on_floor(), "Arrival must settle on meadow terrain")
	check(player.global_position.distance_to(spawn.global_position) < 0.5, "Arrival must use the transformed spawn marker")
	check(player.global_basis.get_scale().is_equal_approx(Vector3.ONE), "Scenery scaling must preserve the player's physical scale")
	player.set_physics_process(false)
	# Approach the open side of the nearby bench from arrival.
	var bench_approach: Vector3 = world.to_global(world.ground(-1.2, 10, 0.1))
	await walk_toward(player, bench_approach, 240)
	var approach_delta := player.global_position - bench_approach
	approach_delta.y = 0
	check(approach_delta.length() < 0.35, "Player must be able to walk from arrival to the bench")
	check(player.is_on_floor(), "Player must remain grounded beside the bench")
	# Disable recovery so a reset cannot disguise a missing boundary collider.
	world.set_physics_process(false)
	var boundaries := [
		["west", Vector2(-4, 0), Vector2(-14, 0), Vector2(-8, 0)],
		["east", Vector2(18, 0), Vector2(28, 0), Vector2(22, 0)],
		["north", Vector2(7, -14), Vector2(7, -24), Vector2(7, -18)],
		["south", Vector2(7, 14), Vector2(7, 24), Vector2(7, 18)],
	]
	for boundary in boundaries:
		var start: Vector2 = boundary[1]
		var destination: Vector2 = boundary[2]
		var edge: Vector2 = boundary[3]
		await place_player(player, world, start.x, start.y)
		await walk_toward(player, world.to_global(world.ground(destination.x, destination.y)), 180)
		var local := world.to_local(player.global_position)
		check(local.x >= -8.1 and local.x <= 22.1 and local.z >= -18.1 and local.z <= 18.1, "The " + boundary[0] + " boundary must block the character")
		check(Vector2(local.x, local.z).distance_to(edge) < 1.5, "Character must reach the " + boundary[0] + " perimeter without an interior obstruction")
		check(player.is_on_wall(), "The " + boundary[0] + " perimeter must physically stop movement")
	world.set_physics_process(true)
	for outside in [Vector3(-12, 0, 0), Vector3(26, 0, 0), Vector3(7, 0, -22), Vector3(7, 0, 22), Vector3(7, -40, 0)]:
		player.global_position = world.to_global(outside)
		player.velocity = Vector3(1, -2, 3)
		await physics_frame
		await physics_frame
		check(player.global_position.distance_to(spawn.global_position) < 0.1, "Out-of-area recovery must return to the transformed arrival: " + str(outside))
		check(player.velocity.is_zero_approx(), "Recovery must clear player velocity")
	print("PRAIRIE CHECKS: ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
