extends SceneTree
## Production RPC and presentation integration over loopback ENet. Each peer has
## an isolated multiplayer root and physics world; only transport/avatars are fixtures.
const PLAYER_PATH = "res://player/network_player.tscn"
var assertions := 0
var failures := 0
var peers: Array[Dictionary] = []
var port := 0


func _initialize() -> void:
	_run.call_deferred()
	# A script runtime error must fail CI rather than leave the SceneTree running.
	_watchdog.call_deferred()


func _watchdog() -> void:
	await create_timer(30.0).timeout
	push_error("Murder session integration test exceeded 30 seconds")
	quit(1)


func check(value: bool, description: String) -> bool:
	assertions += 1
	if not value:
		failures += 1
		push_error(description)
	return value


func until(condition: Callable, description: String) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return check(false, "Timed out: " + description)
		await process_frame
	return check(true, description)


func settle(seconds := 0.20) -> void:
	await create_timer(seconds).timeout


func make_peer(server: bool) -> Dictionary:
	var transport := ENetMultiplayerPeer.new()
	var error := OK
	if server:
		# A kernel-selected port avoids conflicting with another concurrent test.
		error = transport.create_server(0)
		if error == OK:
			port = transport.host.get_local_port()
	else:
		error = transport.create_client("127.0.0.1", port)
	check(error == OK, "ENet transport opens")
	var branch := SubViewport.new()
	branch.name = "Peer%d" % peers.size()
	branch.own_world_3d = true
	root.add_child(branch)
	var api := SceneMultiplayer.new()
	api.root_path = branch.get_path()
	set_multiplayer(api, branch.get_path())
	api.multiplayer_peer = transport
	var world := Node3D.new()
	world.name = "World"
	branch.add_child(world)
	for group_name: String in ["GameSpawns", "ClueSpawns", "KnifeSpawns"]:
		var group := Node3D.new()
		group.name = group_name
		world.add_child(group)
		for index in range(5 if group_name == "ClueSpawns" else 3):
			var marker := Marker3D.new()
			marker.name = "Point%d" % index
			marker.position = Vector3(index * 3, 1.3 if group_name != "GameSpawns" else 0, -4)
			group.add_child(marker)
	var table := Marker3D.new()
	table.name = "GameTable"
	table.position = Vector3(50, 0, 50)
	world.add_child(table)
	var details := Node3D.new()
	details.name = "GhostDetails"
	details.visible = false
	world.add_child(details)
	var map: Node = load("res://game_modes/murder_mystery/murder_map.gd").new()
	map.name = "MurderMap"
	world.add_child(map)
	var players := Node3D.new()
	players.name = "Players"
	world.add_child(players)
	var manager: Node = load("res://player/player_manager.gd").new()
	manager.players = players
	manager.room_networking = RoomNetworking.new(api)
	manager.room_networking.current_room = roomClass.new(47, "Test", 3, "test_map")
	var spawn := Marker3D.new()
	spawn.name = "SpawnPoint"
	world.add_child(spawn)
	manager.spawn_point = spawn
	var game_modes := Node.new()
	game_modes.name = "GameModes"
	branch.add_child(game_modes)
	var session: Node = load("res://game_modes/murder_mystery/murder_session.gd").new()
	session.name = "MurderSession"
	session.player_manager = manager
	game_modes.add_child(session)
	var record := {"branch": branch, "api": api, "transport": transport,
		"world": world, "manager": manager, "session": session, "id": transport.get_unique_id()}
	peers.append(record)
	return record


func spawn_avatars() -> void:
	for viewer: Dictionary in peers:
		for owner: Dictionary in peers:
			var manager: Node = viewer.manager
			if manager.players.has_node(str(owner.id)):
				continue
			var player: CharacterBody3D = load(PLAYER_PATH).instantiate()
			player.name = str(owner.id)
			player.set_multiplayer_authority(owner.id)
			manager.players.add_child(player)
			player.motor.set_physics_process(false)
			player.set_display_name("Guest %d" % owner.id)
			if viewer.id == owner.id:
				manager.local_player = player
				player.controls.input_enabled = false


func by_id(id: int) -> Dictionary:
	for peer: Dictionary in peers:
		if peer.id == id:
			return peer
	return {}


func move_player(id: int, position: Vector3) -> void:
	# The replication layer is outside this test; provide the same replicated pose
	# to each peer while production MurderSession still validates all commands.
	for peer: Dictionary in peers:
		peer.manager.players.get_node(str(id)).global_position = position


func send_action(peer: Dictionary, action: String, item := "", origin := Vector3(0, 1.3, 0), direction := Vector3.FORWARD, room := 47, round_number := -1) -> void:
	var session: Node = peer.session
	var round_id := int(session.snapshot.get("round_id", 0)) if round_number < 0 else round_number
	if peer.id == 1:
		session._handle_command(peer.id, round_id, action, item, origin, direction)
	else:
		session.request_action.rpc_id(1, room, round_id, action, item, origin, direction)
	await settle(0.18)


func _run() -> void:
	var host := make_peer(true)
	var client_a := make_peer(false)
	var client_b := make_peer(false)
	if not await until(func(): return host.api.get_peers().size() == 2 and client_a.api.get_peers().size() == 2 and client_b.api.get_peers().size() == 2, "Three real peers connect"):
		await finish()
		return
	spawn_avatars()
	for peer: Dictionary in peers:
		peer.manager.local_player_spawned.emit()
	if not await until(func(): return not client_a.session.snapshot.is_empty() and not client_b.session.snapshot.is_empty(), "Clients receive initial snapshots"):
		await finish()
		return
	check(host.session.rules != null and client_a.session.rules == null and client_b.session.rules == null, "Only elected authority owns secret rules")
	check(host.session.rules.phase == "waiting", "World entry does not opt players into the game")
	for peer: Dictionary in peers:
		check(not peer.session.snapshot.self.participating, "Opt-in defaults off")
		check(not peer.manager.local_player.controls.head.get_node("MurderStatus").visible, "Unjoined guest has no game HUD away from table")
		host.session.rules.countdown_duration = 30.0
		peer.session.wants_to_play = true
		peer.session._sync_clock = 0.0
	if not await until(func(): return host.session.rules.phase == "countdown", "Opt-in messages start countdown"):
		await finish()
		return
	# Repeat randomized round assignment until the attacker is a remote client so
	# combat checks always exercise received RPCs, irrespective of RNG order.
	var murderer := 1
	var detective := 0
	var bystander := 0
	var attempts := 0
	while murderer == 1 and attempts < 32:
		attempts += 1
		host.session.rules.start_round()
		for id: int in host.session.rules.players:
			match host.session.rules.players[id].role:
				"murderer": murderer = id
				"detective": detective = id
				"bystander": bystander = id
		if murderer == 1:
			host.session.rules.reset()
	if not check(murderer != 1, "Randomized fixture selected a remote attacker"):
		await finish()
		return
	await until(func(): return client_a.session.snapshot.get("round_id", -1) == host.session.rules.round_id and client_b.session.snapshot.get("round_id", -1) == host.session.rules.round_id and client_a.session.snapshot.get("phase", "") == "active" and client_b.session.snapshot.get("phase", "") == "active", "Private active snapshots arrive")
	for peer: Dictionary in peers:
		check(peer.session.snapshot.self.role == host.session.rules.players[peer.id].role, "Recipient receives own secret role")
		for state: Dictionary in peer.session.snapshot.players.values():
			check(not state.has("role") and not state.has("clues"), "Network public view excludes roles and clue counts")
			check(state.weapon == "", "Holstered weapon is hidden from public view")
	var attacker := by_id(murderer)
	var victim := by_id(detective)
	var living := by_id(bystander)
	move_player(murderer, Vector3.ZERO)
	move_player(detective, Vector3(0, 0, -1.2))
	move_player(bystander, Vector3(8, 0, 0))
	# Unauthorized snapshots and wrong-room/stale commands must not change state.
	attacker.session.receive_snapshot.rpc_id(1, 47, {"sequence": 99999, "phase": "results"})
	var other_client := client_a if client_a.id != murderer else client_b
	attacker.session.receive_snapshot.rpc_id(other_client.id, 47, {"sequence": 99999, "phase": "results"})
	await send_action(attacker, "equip", "", Vector3(0, 1.3, 0), Vector3.FORWARD, 999)
	check(host.session.snapshot.phase == "active" and not host.session.equipped.get(murderer, false), "Forged snapshots and wrong-room commands rejected")
	check(other_client.session.snapshot.phase == "active", "Clients reject snapshots from non-authority peers")
	await send_action(attacker, "equip", "", Vector3(0, 1.3, 0), Vector3.FORWARD, 47, 0)
	check(not host.session.equipped.get(murderer, false), "Stale round command rejected")
	await send_action(attacker, "attack")
	check(host.session.rules.players[detective].alive, "Holstered weapon cannot kill")
	await send_action(attacker, "equip")
	check(host.session.equipped.get(murderer, false), "Remote equip reaches authority")
	await send_action(attacker, "attack", "", Vector3(99, 1.3, 0))
	check(host.session.rules.players[detective].alive, "Forged distant attack origin rejected")
	await send_action(attacker, "attack", "", Vector3(0, 1.3, 0), Vector3(0, 0, -10))
	check(host.session.rules.players[detective].alive, "Non-unit attack direction rejected")
	move_player(detective, Vector3(0, 0, -5))
	await send_action(attacker, "attack")
	check(host.session.rules.players[detective].alive, "Knife cannot hit beyond reach")
	await settle(0.7)
	move_player(detective, Vector3(0, 0, -1.2))
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 3, 0.15)
	shape.shape = box
	wall.add_child(shape)
	host.world.add_child(wall)
	wall.position = Vector3(0, 1.3, -0.6)
	await physics_frame
	await physics_frame
	await send_action(attacker, "attack")
	check(host.session.rules.players[detective].alive, "Wall blocks otherwise in-range knife attack")
	wall.queue_free()
	await settle(0.7)
	await send_action(attacker, "attack")
	check(not host.session.rules.players[detective].alive, "Valid remote knife attack kills")
	await until(func(): return not victim.session.snapshot.self.alive, "Death replicated to victim")
	var hidden_avatar: Node3D = living.manager.players.get_node(str(detective) + "/Avatar")
	var hidden_name: Label3D = living.manager.players.get_node(str(detective) + "/NameTag")
	check(not hidden_avatar.visible and not hidden_name.visible, "Living viewer cannot see dead avatar or name")
	check(hidden_avatar.get_node("Body").cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Dead avatar cannot cast shadows")
	check(victim.world.get_node("GhostDetails").visible and not living.world.get_node("GhostDetails").visible, "Optional spectral details appear only to ghost viewer")
	check(victim.session.presentation._held.is_empty() or not victim.session.presentation._held.has(detective), "Dead player's held weapon removed")
	var gun_id := ""
	for item_id: String in host.session.rules.items:
		if host.session.rules.items[item_id].kind == "gun":
			gun_id = item_id
	check(not gun_id.is_empty(), "Detective death drops recoverable gun")
	var gun_position: Vector3 = host.session.rules.items[gun_id].position
	await send_action(victim, "pickup", gun_id, gun_position)
	check(host.session.rules.items.has(gun_id), "Ghost pickup rejected through command boundary")
	await send_action(victim, "attack", "", Vector3(0, 1.3, -1.2), Vector3.BACK)
	check(host.session.rules.players[murderer].alive, "Ghost attack cannot harm living player")
	# A genuinely new transport joins the ongoing round as a spectator.
	var late := make_peer(false)
	await until(func(): return late.api.get_peers().size() == 3, "Late peer joins actual transport")
	spawn_avatars()
	late.manager.local_player_spawned.emit()
	late.session.wants_to_play = true
	late.session._sync_clock = 0.0
	await until(func(): return late.session.snapshot.get("phase", "") == "active" and late.session.snapshot.get("self", {}).get("participating", false), "Late opt-in receives active round")
	check(not late.session.snapshot.self.alive and late.session.snapshot.self.role == "spectator", "Late joiner cannot enter alive mid-round")
	var ghost_avatar: Node3D = late.manager.players.get_node(str(detective) + "/Avatar")
	check(ghost_avatar.visible and late.manager.players.get_node(str(detective) + "/NameTag").visible, "Ghosts see one another including names")
	check(ghost_avatar.get_node("Body").material_override.albedo_color.a < 1.0, "Ghost avatar uses translucent material")
	check(not living.manager.players.get_node(str(late.id) + "/Avatar").visible, "Living viewer cannot see late spectator")
	late.manager.players_clearing.emit()
	await process_frame
	check(ghost_avatar.visible and ghost_avatar.get_node("Body").material_override == null, "Leaving mid-round restores a currently translucent ghost avatar")
	check(ghost_avatar.get_node("Body").cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "Leaving mid-round restores ghost shadows")
	check(late.manager.local_player.controls.head.get_node_or_null("MurderStatus") == null and late.world.get_node_or_null("MurderPickups") == null, "Leaving mid-round removes HUD and item visuals")
	late.manager.local_player_spawned.emit()
	late.session.wants_to_play = true
	await until(func(): return late.session.snapshot.get("phase", "") == "active", "Same scene can rebind after clear")
	# Living bystander can recover and use the gun; no inventory is granted by test.
	move_player(bystander, Vector3(0, 0, -1.2))
	await send_action(living, "pickup", gun_id, gun_position)
	check(host.session.rules.players[bystander].weapon == "gun", "Living player recovers dropped gun")
	await send_action(living, "equip", "", Vector3(0, 1.3, -1.2), Vector3.BACK)
	await send_action(living, "attack", "", Vector3(0, 1.3, -1.2), Vector3.BACK)
	await until(func(): return host.session.rules.phase == "results", "Recovered gun resolves round")
	check(host.session.rules.result == "innocents", "Stopping murderer awards innocents")
	# ENet's star cannot preserve client links when its server disappears. Model
	# the surviving mesh transport with the same peer identity and no remaining
	# links. This tests production election/cancellation, not WebRTC reconnection.
	host.session.rules.reset()
	host.session.rules.start_round()
	await until(func(): return late.session.snapshot.get("phase", "") == "active", "New round is active before authority loss")
	var old_authority: int = late.session.authority_id
	host.session.clear()
	host.transport.close()
	for peer: Dictionary in peers:
		if peer.id == 1:
			continue
		var replacement := ENetMultiplayerPeer.new()
		check(replacement.create_mesh(peer.id) == OK, "Surviving peer retains mesh identity")
		peer.api.multiplayer_peer = replacement
		peer.transport = replacement
	await settle()
	check(late.session.authority_id != old_authority and late.session.authority_id == late.id, "Authority loss elects replacement")
	check(late.session.rules != null and late.session.rules.phase == "waiting" and late.session.snapshot.get("result", "") == "", "Authority change abandons old active round and secrets")
	for peer: Dictionary in peers:
		peer.manager.players_clearing.emit()
	await process_frame
	check(ghost_avatar.visible and ghost_avatar.get_node("Body").material_override == null, "Clear restores remote avatar and original material")
	check(ghost_avatar.get_node("Body").cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "Clear restores normal shadows")
	for peer: Dictionary in peers:
		check(peer.manager.local_player.controls.head.get_node_or_null("MurderStatus") == null, "Clear removes mode HUD")
		check(peer.world.get_node_or_null("MurderPickups") == null and not peer.world.get_node("GhostDetails").visible, "Clear removes pickups and restores lore visibility")
	await finish()


func finish() -> void:
	for peer: Dictionary in peers:
		peer.session.clear()
		peer.transport.close()
		peer.manager.free()
		peer.branch.queue_free()
	await process_frame
	print("Murder session: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
