extends SceneTree
## Integration checks: scene contract, actual walking, and world-space recovery.
var failed := false
func _initialize() -> void:
	call_deferred("verify")
func check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failed = true
func verify() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var world: Node3D = load("res://worlds/moonlit_grotto/moonlit_grotto.tscn").instantiate()
	scene.add_child(world)
	var players := Node3D.new()
	players.name = "Players"
	scene.add_child(players)
	var player = load("res://player/network_player.tscn").instantiate()
	players.add_child(player)
	player.global_transform = world.get_node("SpawnPoint").global_transform
	check(world.has_node("Waterfall curtain"),"The separate grotto scene must contain the waterfall")
	for i in range(20):
		await physics_frame
	check(player.is_on_floor(),"Spawn must settle on the landing")
	check(world.get_node("Stillwater").cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"Clipped water must not cast a rectangular shadow outside the island")
	var moon := world.get_node("Moon") as MeshInstance3D
	check(moon.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"The moon disc must not eclipse its own light")
	var moonlight := world.get_node("Moonlight") as DirectionalLight3D
	check(moonlight.basis.z.dot(moon.position.normalized()) > .9999,"Moonlight must originate from the visible moon direction")
	var quartz := world.get_node("Moon quartz") as MeshInstance3D
	var arrays := quartz.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in range(vertices.size()):
		check(normals[i].dot(Vector3(vertices[i].x,0,vertices[i].z)) >= -.0001,"Crystal normals must face outward")
	for emitter in world.find_children("*","GPUParticles3D",true,false):
		var process := emitter.process_material as ParticleProcessMaterial
		check(process.color_ramp.gradient.sample(0).a == 0 and process.color_ramp.gradient.sample(1).a == 0,"Particles must fade at both lifetime endpoints")
		check(process.scale_curve.curve.sample(0) == 0 and process.scale_curve.curve.sample(1) == 0,"Particles must shrink to zero at both lifetime endpoints")
	check(world.has_node("Falling waterfall droplets"),"Waterfall must have a dedicated falling droplet emitter")
	# The visible perimeter must also be physical, even though the sky stays open.
	var space := world.get_world_3d().direct_space_state
	for i in range(44):
		var angle := float(i)*TAU/44.0
		var point := Vector3(12*cos(angle),0,-2+16.2*sin(angle))
		var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*20,point-Vector3.UP*5)
		var hit := space.intersect_ray(query)
		check(not hit.is_empty() and hit.position.y > .1,"Lagoon rim must contain the playable pool")
	Input.action_press("move_forward")
	for i in range(230):
		await physics_frame
	Input.action_release("move_forward")
	print("Walk endpoint: ",player.position)
	check(player.position.z < -4.0,"Stepping-stone route must be walkable without jumping")
	player.global_position = Vector3(0,-10,0)
	for i in range(4):
		await physics_frame
	check(player.position.y > 0 and player.position.z > 8,"Recovery must return the player to SpawnPoint")
	scene.queue_free()
	await process_frame
	print("Grotto verification: ","FAILED" if failed else "PASS")
	quit(1 if failed else 0)
