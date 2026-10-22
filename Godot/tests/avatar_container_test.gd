extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func run() -> void:
	# Load after autoload globals register, rather than resolving NetworkPlayer
	# while the standalone SceneTree script is being compiled.
	var player = load("res://player/network_player.tscn").instantiate()
	root.add_child(player)
	player.motor.set_physics_process(false)
	var avatar = player.get_node("Avatar")
	var anchor: Node = avatar.get_node("Head")
	check(avatar.visible and avatar.get_node("Body").visible, "Local fallback body must be visible")
	check(not avatar.get_node("Head").visible, "Local fallback head must not obstruct the camera")
	player.set_avatar("godette")
	var deadline := Time.get_ticks_msec() + 15000
	while avatar.model == null and Time.get_ticks_msec() < deadline:
		await process_frame
	check(avatar.model != null, "Player's runtime avatar failed to load")
	if avatar.model != null:
		check(avatar.get_node("Head") == anchor, "Loading must preserve voice/pose anchor identity")
		check(not avatar.get_node("Body").visible, "Loaded avatar must replace the fallback geometry")
		check(not avatar._springs.is_empty(), "Godette's spring chains must use native simulators")
		root.get_node("AvatarService").springs_changed.emit(false)
		for simulator in avatar._springs:
			check(not simulator.active, "Spring preference must disable the native solver")
		root.get_node("AvatarService").springs_changed.emit(true)
		for simulator in avatar._springs:
			check(simulator.active, "Spring preference must reenable the native solver")
		player.controls.head.position = Vector3(0.15, 1.6, 0.1)
		await process_frame
		await process_frame
		check(avatar.get_node("Head").position.is_equal_approx(player.controls.head.position), "Local body must consume tracking without a replication tick")
		player.position += Vector3(2, 0, 0)
		await process_frame
		await process_frame
		for simulator in avatar._springs:
			check(simulator.transform.is_finite(), "Teleport reset must preserve finite spring transforms")
	player.set_avatar("default")
	check(avatar.model == null and avatar.get_node("Body").visible, "Reset must restore the fallback immediately")
	check(avatar.get_node("Head") == anchor, "Reset must preserve voice/pose anchor identity")
	# Supersede a queued network request before it starts; no download required.
	var remote_id: String = AvatarCatalog.entries()[2].id
	player.set_avatar(remote_id)
	player.set_avatar("default")
	await process_frame
	check(avatar.avatar_id == "default" and avatar.model == null, "A superseded selection must never replace the newest avatar")
	player.free()
	await process_frame
	print("Avatar container: %d failures" % failures)
	quit(1 if failures > 0 else 0)
