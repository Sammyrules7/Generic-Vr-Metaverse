extends SceneTree
## Real physics validation: 16 unobstructed spawns, connected rooms, reachable pickups.
var _failed := false
var _space: PhysicsDirectSpaceState3D
var _body: CapsuleShape3D
var _reachable: Dictionary = {}

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var scene: Node3D = load("res://worlds/blackthorn_house/blackthorn_house.tscn").instantiate()
	root.add_child(scene)
	await physics_frame
	await physics_frame
	_space = scene.get_world_3d().direct_space_state
	_body = CapsuleShape3D.new()
	_body.radius = 0.5
	_body.height = 1.8
	var map: Node = scene.get_node("MurderMap")
	_check(map.valid(), "Map contract")
	_check(map.spawn_positions().size() == 16, "16 unique player starts")
	for spawn: Vector3 in map.spawn_positions():
		_check(_clear(spawn + Vector3(0, 0.9, 0)), "Player spawn clear: " + str(spawn))
	# A half-metre grid flood verifies that every room connects for a metre-wide avatar.
	var frontier: Array[Vector2i] = [Vector2i(0, 14)]
	_reachable[frontier[0]] = true
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := cell + offset
			if _reachable.has(next) or abs(next.x) > 27 or abs(next.y) > 23:
				continue
			if _clear(Vector3(next.x * 0.5, 1, next.y * 0.5)):
				_reachable[next] = true
				frontier.append(next)
	for spawn: Vector3 in map.spawn_positions():
		_check(_reachable.has(Vector2i(roundi(spawn.x * 2), roundi(spawn.z * 2))), "Spawn connects to foyer: " + str(spawn))
	var probe := SphereShape3D.new()
	probe.radius = 0.045
	for id: String in map.item_layout():
		var position: Vector3 = map.item_layout()[id].position
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = probe
		query.transform.origin = position
		_check(_space.intersect_shape(query, 1).is_empty(), "Pickup outside collision: " + id)
		var accessible := false
		for cell: Vector2i in _reachable:
			var eye := Vector3(cell.x * 0.5, 1.5, cell.y * 0.5)
			if eye.distance_to(position) <= 2.0:
				var ray := PhysicsRayQueryParameters3D.create(eye, position)
				if _space.intersect_ray(ray).is_empty():
					accessible = true
					break
		_check(accessible, "Pickup reachable from walkable floor: " + id)
	# The adapter uses world coordinates, including a translated and rotated map root.
	var original_spawns: Array[Vector3] = map.spawn_positions()
	var original_items: Dictionary = map.item_layout()
	var original_table: Vector3 = map.table_position()
	scene.position = Vector3(7, 3, -11)
	scene.rotation.y = PI / 3
	_check(map.spawn_positions()[0].is_equal_approx(scene.to_global(original_spawns[0])), "Transformed spawn coordinates")
	_check(map.item_layout()["clue:Point01"].position.is_equal_approx(scene.to_global(original_items["clue:Point01"].position)), "Transformed pickup coordinates")
	_check(map.table_position().is_equal_approx(scene.to_global(original_table)), "Transformed table coordinates")
	var table_path: NodePath = map.table_path
	map.table_path = ^"../Environment"
	_check(not map.valid(), "Reject non-Node3D game table")
	map.table_path = table_path
	var spawns_path: NodePath = map.spawns_path
	var malformed := Node.new()
	malformed.name = "MalformedStarts"
	scene.add_child(malformed)
	for index in range(4):
		malformed.add_child(Node.new())
	map.spawns_path = ^"../MalformedStarts"
	_check(not map.valid(), "Reject non-spatial spawn nodes")
	map.spawns_path = spawns_path
	_check(map.valid(), "Restore valid map contract")
	print("Blackthorn map validation: ", "FAILED" if _failed else "PASS", " · ", _reachable.size(), " connected floor samples, 16 spawns, ", map.item_layout().size(), " pickups")
	quit(1 if _failed else 0)

func _clear(position: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _body
	query.transform.origin = position
	return _space.intersect_shape(query, 1).is_empty()

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failed = true
		push_error(label)
