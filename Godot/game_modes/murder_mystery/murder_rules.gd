class_name MurderRules
extends RefCounted
## Scene-independent authority state. Callers validate identity, range, line of sight,
## and attack cooldown before submitting an action. Snapshots never expose live roles.

signal changed

var min_players: int = 3
var countdown_duration: float = 10.0
var round_duration: float = 240.0
var results_duration: float = 8.0
var clues_for_gun: int = 5
var phase: String = "waiting"
var remaining: float = 0.0
var players: Dictionary = {}
var items: Dictionary = {}
var round_id: int = 0
var result: String = ""
var _item_template: Dictionary = {}
var _positions: Dictionary = {}
var _drop_serial: int = 0


func configure_items(map_items: Dictionary) -> void:
	_item_template = map_items.duplicate(true)
	if phase == "waiting" or phase == "countdown":
		items = _item_template.duplicate(true)
		changed.emit()


func set_position(id: int, world_position: Vector3) -> void:
	_positions[id] = world_position


func set_participating(id: int, enabled: bool) -> void:
	if not players.has(id):
		players[id] = _new_player()
	var player: Dictionary = players[id]
	if player.participating == enabled:
		return
	player.participating = enabled
	if phase == "active":
		if not enabled:
			_kill(id)
		_check_win()
	elif phase != "results":
		player.alive = enabled
	_update_countdown()
	changed.emit()


func remove_player(id: int) -> void:
	if not players.has(id):
		return
	if phase == "active":
		_kill(id)
	players.erase(id)
	_positions.erase(id)
	if phase == "active":
		_check_win()
	_update_countdown()
	changed.emit()


func tick(delta: float) -> void:
	if delta <= 0.0 or not is_finite(delta):
		return
	if phase == "waiting":
		_update_countdown()
		return
	var before: int = ceili(remaining)
	remaining = maxf(0.0, remaining - delta)
	if remaining <= 0.0:
		match phase:
			"countdown": start_round()
			"active": _finish("innocents")
			"results": reset()
	elif ceili(remaining) != before:
		changed.emit()


func start_round() -> bool:
	if phase != "waiting" and phase != "countdown":
		return false
	var entrants: Array = []
	for id in players:
		if players[id].participating:
			entrants.append(id)
	if entrants.size() < maxi(3, min_players):
		_update_countdown()
		return false
	entrants.shuffle()
	round_id += 1
	phase = "active"
	remaining = round_duration
	result = ""
	items = _item_template.duplicate(true)
	for id in players:
		var joined: bool = players[id].participating
		players[id] = _new_player()
		players[id].participating = joined
		players[id].alive = joined
		if joined:
			players[id].role = "bystander"
	players[entrants[0]].role = "murderer"
	players[entrants[0]].weapon = "knife"
	players[entrants[1]].role = "detective"
	players[entrants[1]].weapon = "gun"
	changed.emit()
	return true


func reset() -> void:
	phase = "waiting"
	remaining = 0.0
	result = ""
	items = _item_template.duplicate(true)
	for id in players:
		var joined: bool = players[id].participating
		players[id] = _new_player()
		players[id].participating = joined
		players[id].alive = joined
	_update_countdown()
	changed.emit()


func take_item(id: int, item_id: String) -> bool:
	if not _can_act(id) or not items.has(item_id):
		return false
	var player: Dictionary = players[id]
	var kind: String = items[item_id].get("kind", "")
	match kind:
		"clue":
			if player.role == "murderer" or player.weapon == "gun":
				return false
			player.clues += 1
			if player.clues >= clues_for_gun:
				player.weapon = "gun"
				player.clues = 0
		"gun":
			if player.role == "murderer" or player.weapon != "":
				return false
			player.weapon = "gun"
		"knife":
			if player.role != "murderer" or player.weapon != "":
				return false
			player.weapon = "knife"
		_:
			return false
	items.erase(item_id)
	changed.emit()
	return true


func attack(attacker: int, target: int, weapon: String) -> bool:
	if attacker == target or not _can_act(attacker) or not _can_act(target):
		return false
	var player: Dictionary = players[attacker]
	if player.weapon != weapon:
		return false
	if weapon == "knife":
		if player.role != "murderer":
			return false
		_kill(target)
	elif weapon == "gun":
		if player.role == "murderer":
			return false
		var innocent_hit: bool = players[target].role != "murderer"
		_kill(target)
		if innocent_hit:
			_kill(attacker)
	else:
		return false
	_check_win()
	changed.emit()
	return true


func drop_weapon(id: int) -> bool:
	if not _can_act(id) or players[id].weapon == "":
		return false
	_spawn_drop(id, players[id].weapon)
	players[id].weapon = ""
	changed.emit()
	return true


func snapshot_for(id: int) -> Dictionary:
	var public_players: Dictionary = {}
	for peer_id in players:
		var player: Dictionary = players[peer_id]
		public_players[peer_id] = {
			"alive": player.alive,
			"participating": player.participating,
			"weapon": player.weapon,
		}
		if phase == "results":
			public_players[peer_id]["role"] = player.role
	var own: Dictionary = players.get(id, _new_player()).duplicate(true)
	return {
		"phase": phase, "remaining": remaining, "round_id": round_id,
		"result": result, "players": public_players, "self": own,
		"items": items.duplicate(true),
	}


func _new_player() -> Dictionary:
	return {"role": "spectator", "alive": false, "participating": false,
		"clues": 0, "weapon": ""}


func _can_act(id: int) -> bool:
	return phase == "active" and players.has(id) and players[id].alive \
		and players[id].participating


func _update_countdown() -> void:
	if phase != "waiting" and phase != "countdown":
		return
	var count: int = 0
	for player in players.values():
		if player.participating:
			count += 1
	if count >= maxi(3, min_players) and phase == "waiting":
		phase = "countdown"
		remaining = countdown_duration
		changed.emit()
	elif count < maxi(3, min_players) and phase == "countdown":
		phase = "waiting"
		remaining = 0.0
		changed.emit()


func _kill(id: int) -> void:
	var player: Dictionary = players[id]
	if not player.alive:
		return
	player.alive = false
	if player.weapon == "gun":
		_spawn_drop(id, "gun")
	player.weapon = ""


func _spawn_drop(id: int, kind: String) -> void:
	_drop_serial += 1
	items["dropped_%s_%d_%d" % [kind, round_id, _drop_serial]] = {
		"kind": kind, "position": _positions.get(id, Vector3.ZERO) + Vector3(0, 0.5, 0),
	}


func _check_win() -> void:
	var murderer_alive: bool = false
	var innocents_alive: bool = false
	for player in players.values():
		if player.alive and player.participating:
			if player.role == "murderer":
				murderer_alive = true
			elif player.role != "spectator":
				innocents_alive = true
	if not murderer_alive:
		_finish("innocents")
	elif not innocents_alive:
		_finish("murderer")


func _finish(winner: String) -> void:
	phase = "results"
	remaining = results_duration
	result = winner
	changed.emit()
