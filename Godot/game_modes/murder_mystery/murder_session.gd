class_name MurderSession
extends Node

## Main/GameModes owns this endpoint. It outlives loaded worlds so in-flight RPCs
## can be rejected safely, but no game state belongs to the networking autoload.
@export var player_manager: PlayerManager

var rules: MurderRules
var map: MurderMap
var manager: PlayerManager
var presentation: MurderPresentation
var room_id := 0
var authority_id := 0
var snapshot: Dictionary = {}
var wants_to_play := false
var equipped: Dictionary = {}
var cooldowns: Dictionary = {}
var _sync_clock := 0.0
var _last_tick_usec: int = -1
var _last_spawn_round := -1
var _spawn_assignments: Dictionary = {}
var _sequence := 0
var _received_sequence := -1
var _target_item := ""
var _at_table := false
var _controller_connections: Array[Dictionary] = []
var _interact_accum := 0.0
const INTERACT_HZ := 12.0
var _excluded_rids: Array[RID] = []
var _excluded_dirty := true
var _excluded_count := -1


func _ready() -> void:
	multiplayer.peer_connected.connect(_peer_changed)
	multiplayer.peer_disconnected.connect(_peer_left)
	if player_manager != null:
		player_manager.local_player_spawned.connect(_bind_player_world)
		player_manager.players_clearing.connect(clear)
		# Also support a game component added after the local avatar is ready.
		if player_manager.local_player != null:
			_bind_player_world()


func _bind_player_world() -> void:
	var room := player_manager.room_networking.current_room
	if room != null and is_instance_valid(player_manager.spawn_point):
		bind_world(player_manager.spawn_point.get_parent(), player_manager, room.id)
	else:
		clear()


func _exit_tree() -> void:
	clear()


func bind_world(world: Node3D, in_manager: PlayerManager, id: int) -> void:
	clear()
	map = world.get_node_or_null("MurderMap") as MurderMap
	if map == null or not map.valid():
		map = null
		return
	manager = in_manager
	room_id = id
	presentation = MurderPresentation.new()
	add_child(presentation)
	presentation.setup(manager.players, manager.local_player, world)
	manager.local_player.controls_changed.connect(_bind_controls)
	_bind_controls()
	_elect_authority()


func _bind_controls() -> void:
	for connection: Dictionary in _controller_connections:
		if is_instance_valid(connection.node):
			connection.node.button_pressed.disconnect(connection.callback)
	_controller_connections.clear()
	var controls := manager.local_player.controls
	if manager.local_player.use_vr:
		for hand: String in ["left_hand", "right_hand"]:
			var controller: XRController3D = controls.get(hand) as XRController3D
			if controller != null:
				var callback := _vr_button.bind(hand == "right_hand")
				controller.button_pressed.connect(callback)
				_controller_connections.append({"node": controller, "callback": callback})


func clear() -> void:
	if is_instance_valid(manager) and is_instance_valid(manager.voice_chat):
		manager.voice_chat.set_audience_policy(Callable())
	if is_instance_valid(manager) and is_instance_valid(manager.local_player) and manager.local_player.controls_changed.is_connected(_bind_controls):
		manager.local_player.controls_changed.disconnect(_bind_controls)
	for connection: Dictionary in _controller_connections:
		if is_instance_valid(connection.node):
			connection.node.button_pressed.disconnect(connection.callback)
	_controller_connections.clear()
	if is_instance_valid(presentation):
		presentation.clear()
		presentation.queue_free()
	presentation = null
	rules = null
	map = null
	manager = null
	room_id = 0
	authority_id = 0
	snapshot = {}
	wants_to_play = false
	equipped.clear()
	cooldowns.clear()
	_spawn_assignments.clear()
	_last_spawn_round = -1
	_received_sequence = -1
	_sequence = 0
	_last_tick_usec = -1


func _peer_changed(_id: int) -> void:
	_sync_clock = 0.0
	_excluded_dirty = true
	_elect_authority()


func _peer_left(id: int) -> void:
	if rules != null:
		rules.remove_player(id)
	equipped.erase(id)
	cooldowns.erase(id)
	_sync_clock = 0.0
	_excluded_dirty = true
	_elect_authority()


func _elect_authority() -> void:
	if not is_instance_valid(map) or not _transport_ready():
		return
	var elected := multiplayer.get_unique_id()
	for id: int in multiplayer.get_peers():
		elected = mini(elected, id)
	if elected == authority_id:
		return
	authority_id = elected
	_received_sequence = -1
	_last_spawn_round = -1
	_spawn_assignments.clear()
	equipped.clear()
	cooldowns.clear()
	snapshot = {}
	if is_instance_valid(presentation):
		presentation.apply_snapshot({})
	rules = null
	# Authority changes deliberately abandon the old round, including its secrets.
	if authority_id == multiplayer.get_unique_id():
		rules = MurderRules.new()
		rules.configure_items(map.item_layout())
		rules.changed.connect(_broadcast)
		rules.set_participating(multiplayer.get_unique_id(), wants_to_play)
		_broadcast()
	_sync_clock = 0.0


func _process(_delta: float) -> void:
	if not is_instance_valid(map) or not is_instance_valid(manager) or not is_instance_valid(manager.local_player):
		_last_tick_usec = -1
		return
	if not _transport_ready():
		_last_tick_usec = -1
		return
	# Godot can clamp frame delta when rendering stalls. Round deadlines and
	# snapshot cadence must follow real seconds, even on a slow VR client.
	# Monotonic time is unaffected by changes to the system clock.
	var now_usec := Time.get_ticks_usec()
	var elapsed := 0.0 if _last_tick_usec < 0 else float(now_usec - _last_tick_usec) / 1_000_000.0
	_last_tick_usec = now_usec
	# Election itself is a cheap peer-minimum loop; it must react within a
	# frame to authority loss (tests and gameplay depend on fast failover).
	_elect_authority()
	if rules != null:
		for player: Node3D in manager.players.get_children():
			# Authority is the peer ID; no string alloc/parse on the hot path.
			rules.set_position(player.get_multiplayer_authority(), player.global_position)
		rules.tick(elapsed)
	_sync_clock -= elapsed
	if _sync_clock <= 0.0:
		_sync_clock = 1.0
		if rules != null:
			rules.set_participating(multiplayer.get_unique_id(), wants_to_play)
		else:
			request_sync.rpc_id(authority_id, room_id, wants_to_play)
	_interact_accum += elapsed
	if _interact_accum >= 1.0 / INTERACT_HZ:
		_interact_accum = 0.0
		_update_interaction()


@rpc("any_peer", "call_remote", "reliable")
func request_sync(in_room: int, participating: bool) -> void:
	if rules == null or in_room != room_id:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.get_peers().has(sender):
		return
	rules.set_participating(sender, participating)
	_send_snapshot(sender)


func _broadcast() -> void:
	if rules == null or not is_instance_valid(map) or not _transport_ready():
		return
	if rules.phase == "active" and _last_spawn_round != rules.round_id:
		_last_spawn_round = rules.round_id
		equipped.clear()
		_spawn_assignments.clear()
		var points := map.spawn_positions()
		points.shuffle()
		var index := 0
		for id: int in rules.players:
			if rules.players[id].alive and rules.players[id].participating:
				_spawn_assignments[id] = points[index % points.size()]
				index += 1
	_sequence += 1
	for id: int in multiplayer.get_peers():
		_send_snapshot(id)
	_send_snapshot(multiplayer.get_unique_id())


func _send_snapshot(id: int) -> void:
	var view := rules.snapshot_for(id)
	for peer_id: int in view.players:
		if not equipped.get(peer_id, false):
			view.players[peer_id].weapon = ""
	view.self["equipped"] = equipped.get(id, false)
	view["sequence"] = _sequence
	if rules.phase == "active" and _spawn_assignments.has(id):
		view["spawn"] = _spawn_assignments[id]
	if id == multiplayer.get_unique_id():
		_apply_snapshot(view)
	else:
		receive_snapshot.rpc_id(id, room_id, view)


@rpc("any_peer", "call_remote", "reliable")
func receive_snapshot(in_room: int, view: Dictionary) -> void:
	if in_room == room_id and room_id != 0 and multiplayer.get_remote_sender_id() == authority_id:
		_apply_snapshot(view)


func _apply_snapshot(view: Dictionary) -> void:
	if int(view.get("sequence", -1)) < _received_sequence:
		return
	_received_sequence = int(view.get("sequence", -1))
	var new_round: bool = int(view.get("round_id", 0)) != int(snapshot.get("round_id", -1)) or snapshot.get("phase", "") != "active"
	snapshot = view
	if is_instance_valid(manager) and is_instance_valid(manager.local_player) and view.get("phase", "") == "active" and new_round and view.has("spawn"):
		manager.local_player.global_position = view.spawn
		manager.local_player.velocity = Vector3.ZERO
	if is_instance_valid(presentation):
		presentation.apply_snapshot(view)
	if is_instance_valid(manager) and is_instance_valid(manager.voice_chat):
		manager.voice_chat.set_audience_policy(_voice_allowed)


func _voice_allowed(sender_id: int, listener_id: int) -> bool:
	if snapshot.get("phase", "") != "active":
		return true
	var players: Dictionary = snapshot.get("players", {})
	var sender: Dictionary = players.get(sender_id, {})
	var listener: Dictionary = players.get(listener_id, {})
	var sender_living: bool = sender.get("participating", false) and sender.get("alive", false)
	var listener_living: bool = listener.get("participating", false) and listener.get("alive", false)
	# Spectators may listen to the round; only living players can speak to living players.
	return sender_living or not listener_living


func _update_interaction() -> void:
	var player := manager.local_player
	var controls := player.controls
	_at_table = player.global_position.distance_to(map.table_position()) < 2.6
	var next_target := ""
	if not _at_table and snapshot.get("self", {}).get("participating", false):
		var state: Dictionary = snapshot.get("self", {})
		if state.get("alive", false) and snapshot.get("phase", "") == "active":
			var head_pos: Vector3 = controls.head.global_position
			# Distance-sort first, then raycast ONLY the nearest candidate.
			# Previously every item got its own intersect_ray per frame.
			var best_id := ""
			var best_dist := 2.0
			var items: Dictionary = snapshot.get("items", {})
			for id: String in items:
				var item_pos: Vector3 = (items[id] as Dictionary).position
				var distance := head_pos.distance_to(item_pos)
				if distance < best_dist:
					best_dist = distance
					best_id = id
			if not best_id.is_empty() and _line_clear(head_pos, (items[best_id] as Dictionary).position):
				next_target = best_id
	_target_item = next_target
	presentation.focus_item(_target_item if controls.input_enabled else "")


func _unhandled_input(event: InputEvent) -> void:
	if not _can_input() or manager.local_player.use_vr:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_TAB: presentation.toggle_journal()
			KEY_E: _interact()
			KEY_R: _command("equip")
			KEY_Q: _command("drop")
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_command("attack")


func _vr_button(button: String, right: bool) -> void:
	if not _can_input():
		return
	if button == "ax_button" and not right:
		presentation.toggle_journal()
		return
	if button == "grip_click":
		if right:
			_interact()
		else:
			_command("equip")
	elif button == "trigger_click":
		_command("attack" if right else "drop")


func _can_input() -> bool:
	return _transport_ready() and is_instance_valid(map) and is_instance_valid(manager) and is_instance_valid(manager.local_player) and manager.local_player.controls.input_enabled


func _transport_ready() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _interact() -> void:
	if _at_table:
		wants_to_play = not wants_to_play
		_sync_clock = 0.0
	elif not _target_item.is_empty():
		_command("pickup", _target_item)


func _command(action: String, item := "") -> void:
	var controls := manager.local_player.controls
	var aim := controls.right_hand if manager.local_player.use_vr else controls.head
	var origin := aim.global_position
	var direction := -aim.global_basis.z.normalized()
	var round_number := int(snapshot.get("round_id", -1))
	if rules != null:
		_handle_command(multiplayer.get_unique_id(), round_number, action, item, origin, direction)
	else:
		request_action.rpc_id(authority_id, room_id, round_number, action, item, origin, direction)


@rpc("any_peer", "call_remote", "reliable")
func request_action(in_room: int, round_number: int, action: String, item: String, origin: Vector3, direction: Vector3) -> void:
	if in_room == room_id and rules != null:
		var sender := multiplayer.get_remote_sender_id()
		if multiplayer.get_peers().has(sender):
			_handle_command(sender, round_number, action, item, origin, direction)


func _handle_command(id: int, round_number: int, action: String, item: String, origin: Vector3, direction: Vector3) -> void:
	if rules == null or rules.phase != "active" or round_number != rules.round_id or not rules.players.has(id):
		return
	var state: Dictionary = rules.players[id]
	if not state.alive or not state.participating:
		return
	var player := manager.get_player(id) as Node3D
	if player == null or not origin.is_finite() or not direction.is_finite() or origin.distance_to(player.global_position + Vector3.UP * 1.3) > 1.8:
		return
	var now := Time.get_ticks_msec()
	if now < int(cooldowns.get(id, 0)):
		return
	cooldowns[id] = now + 150
	match action:
		"equip":
			if not str(state.weapon).is_empty():
				equipped[id] = not equipped.get(id, false)
				_broadcast()
		"drop":
			equipped[id] = false
			rules.drop_weapon(id)
		"pickup":
			if rules.items.has(item):
				var position: Vector3 = rules.items[item].position
				if origin.distance_to(position) <= 2.2 and _line_clear(origin, position):
					rules.take_item(id, item)
		"attack":
			if not equipped.get(id, false) or direction.length_squared() < 0.9 or direction.length_squared() > 1.1:
				return
			var weapon: String = state.weapon
			if weapon not in ["knife", "gun"]:
				return
			cooldowns[id] = now + (900 if weapon == "gun" else 650)
			_attack_effect(id, origin, direction, weapon)
			var reach := 30.0 if weapon == "gun" else 1.8
			var target := _hit_player(id, origin, direction.normalized(), reach, weapon == "knife")
			if target != 0:
				rules.attack(id, target, weapon)


func _attack_effect(id: int, origin: Vector3, direction: Vector3, weapon: String) -> void:
	if is_instance_valid(presentation):
		presentation.play_attack(id, origin, direction, weapon)
	for peer_id: int in multiplayer.get_peers():
		receive_attack.rpc_id(peer_id, room_id, id, origin, direction, weapon)


@rpc("any_peer", "call_remote", "reliable")
func receive_attack(in_room: int, id: int, origin: Vector3, direction: Vector3, weapon: String) -> void:
	if in_room == room_id and multiplayer.get_remote_sender_id() == authority_id and is_instance_valid(presentation):
		presentation.play_attack(id, origin, direction, weapon)


func _hit_player(attacker: int, origin: Vector3, direction: Vector3, reach: float, knife: bool) -> int:
	var nearest := reach
	var target := 0
	# Remote lookups are cached by PlayerManager; the capsule test below is
	# pure math and _line_clear runs only for samples that pass it.
	for id: int in rules.players:
		if id == attacker or not rules.players[id].alive or not rules.players[id].participating:
			continue
		var player := manager.get_player(id) as Node3D
		if player == null:
			continue
		# Intersect a standing capsule approximation; remote colliders are disabled
		# by avatar replication, so hits cannot depend on their physics bodies.
		for height: float in [0.45, 0.9, 1.35, 1.7]:
			var center := player.global_position + Vector3.UP * height
			var along := (center - origin).dot(direction)
			var radius := 0.48 if knife else 0.32
			var closest := origin + direction * clampf(along, 0.0, reach)
			if along >= 0.0 and along <= nearest and center.distance_to(closest) <= radius and _line_clear(origin, closest):
				nearest = along
				target = id
	return target


func _line_clear(from: Vector3, to: Vector3) -> bool:
	if not is_instance_valid(map):
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var count := manager.players.get_child_count() if is_instance_valid(manager) and is_instance_valid(manager.players) else -1
	if _excluded_dirty or count != _excluded_count:
		_excluded_dirty = false
		_excluded_count = count
		_excluded_rids.clear()
		if is_instance_valid(manager) and is_instance_valid(manager.players):
			for player: CollisionObject3D in manager.players.get_children():
				_excluded_rids.append(player.get_rid())
	query.exclude = _excluded_rids
	return (map.get_parent() as Node3D).get_world_3d().direct_space_state.intersect_ray(query).is_empty()
