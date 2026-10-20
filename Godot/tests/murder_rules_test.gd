extends SceneTree

const Rules = preload("res://game_modes/murder_mystery/murder_rules.gd")
var failures: int = 0
var assertions: int = 0


func _initialize() -> void:
	_lifecycle()
	_secrets_and_items()
	_combat_and_disconnects()
	print("Murder rules: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(message)


func game(count: int = 4) -> RefCounted:
	var rules = Rules.new()
	for id in range(1, count + 1):
		rules.set_participating(id, true)
	return rules


func role_id(rules: RefCounted, role: String) -> int:
	for id in rules.players:
		if rules.players[id].role == role:
			return id
	return -1


func _lifecycle() -> void:
	var rules = game(2)
	check(rules.phase == "waiting", "Two players wait")
	check(not rules.start_round(), "Cannot force a round below minimum")
	check(not rules.drop_weapon(1), "Waiting player cannot drop weapons")
	rules.set_participating(3, true)
	check(rules.phase == "countdown", "Three opted-in players trigger countdown")
	rules.set_participating(3, false)
	check(rules.phase == "waiting", "Opting out cancels countdown")
	rules.set_participating(3, true)
	rules.tick(rules.countdown_duration)
	check(rules.phase == "active" and rules.round_id == 1, "Countdown starts round")
	check(not rules.start_round(), "Active round cannot be restarted")
	check(role_id(rules, "murderer") > 0 and role_id(rules, "detective") > 0,
		"Both unique special roles assigned")
	rules.set_participating(4, true)
	check(not rules.players[4].alive and rules.players[4].role == "spectator",
		"Late joins are ghosts")
	rules.tick(rules.round_duration)
	check(rules.phase == "results" and rules.result == "innocents", "Time limit awards survival")
	rules.tick(rules.results_duration)
	check(rules.phase == "countdown" and rules.players.size() == 4, "Reset retains opt-ins")
	rules.tick(rules.countdown_duration)
	check(rules.round_id == 2 and rules.players[4].alive, "Late join plays next round")


func _secrets_and_items() -> void:
	var rules = game()
	var map_items: Dictionary = {}
	for index in 5:
		map_items["clue_%d" % index] = {"kind": "clue", "position": Vector3(index, 0, 0)}
	rules.configure_items(map_items)
	rules.start_round()
	var bystander: int = role_id(rules, "bystander")
	var murderer: int = role_id(rules, "murderer")
	var state: Dictionary = rules.snapshot_for(bystander)
	for player in state.players.values():
		check(not player.has("role") and not player.has("clues"), "Public player data hides role and clues")
	check(state.self.role == "bystander", "Private snapshot contains recipient's role")
	state.self.weapon = "gun"
	state.items.clear()
	check(rules.players[bystander].weapon == "" and rules.items.size() == 5,
		"Snapshots cannot mutate authority data")
	check(not rules.take_item(murderer, "clue_0"), "Murderer cannot collect clue guns")
	check(rules.take_item(bystander, "clue_0"), "Living bystander collects clue")
	check(not rules.take_item(bystander, "clue_0"), "Same clue cannot count twice")
	for index in range(1, 5):
		check(rules.take_item(bystander, "clue_%d" % index), "Remaining unique clues collect")
	check(rules.players[bystander].weapon == "gun", "Five unique clues earn defensive gun")
	check(rules.players[bystander].clues == 0, "Clues are spent when earning a gun")
	rules.tick(rules.round_duration)
	check(rules.snapshot_for(bystander).players[murderer].role == "murderer",
		"Results reveal roles")
	rules.reset()
	check(rules.items.size() == 5 and rules.players[bystander].clues == 0,
		"Reset restores map clues and clears progress")


func _combat_and_disconnects() -> void:
	var rules = game()
	rules.start_round()
	var murderer: int = role_id(rules, "murderer")
	var detective: int = role_id(rules, "detective")
	var bystander: int = role_id(rules, "bystander")
	check(not rules.attack(bystander, murderer, "gun"), "Cannot attack with unowned weapon")
	check(not rules.attack(murderer, murderer, "knife"), "Cannot attack self")
	check(not rules.attack(999, murderer, "knife"), "Unknown attacker rejected")
	check(not rules.attack(murderer, 999, "knife"), "Unknown target rejected")
	check(rules.drop_weapon(murderer), "Living murderer can put knife down")
	var knife_id: String = rules.items.keys()[0]
	check(not rules.take_item(bystander, knife_id), "Innocent cannot use knife")
	check(not rules.attack(murderer, detective, "knife"), "Dropped knife cannot attack")
	check(rules.take_item(murderer, knife_id), "Murderer can recover knife")
	var drop_position := Vector3(4, 0, 2)
	rules.set_position(detective, drop_position)
	check(rules.attack(murderer, detective, "knife"), "Murderer knife kills")
	check(not rules.players[detective].alive, "Killed player becomes ghost")
	check(not rules.attack(detective, murderer, "gun"), "Ghost cannot attack")
	check(not rules.drop_weapon(detective), "Ghost cannot drop weapons")
	var gun_id: String = rules.items.keys()[0]
	check(rules.items[gun_id].position == drop_position + Vector3(0, 0.5, 0), "Gun drops at victim position")
	check(not rules.take_item(detective, gun_id), "Ghost cannot pick up gun")
	check(rules.take_item(bystander, gun_id), "Living bystander recovers gun")
	check(rules.attack(bystander, murderer, "gun"), "Recovered gun can stop murderer")
	check(rules.result == "innocents", "Murderer death ends round")
	check(not rules.attack(bystander, detective, "gun"), "Results disallow attacks")
	rules = game()
	rules.start_round()
	murderer = role_id(rules, "murderer")
	detective = role_id(rules, "detective")
	bystander = role_id(rules, "bystander")
	check(rules.attack(detective, bystander, "gun"), "Innocent gun hit resolves")
	check(not rules.players[detective].alive and not rules.players[bystander].alive,
		"Shooting innocent also kills shooter")
	rules.remove_player(murderer)
	check(rules.phase == "results" and rules.result == "innocents", "Murderer disconnect awards innocents")
	rules = game(3)
	rules.start_round()
	murderer = role_id(rules, "murderer")
	for id in rules.players.keys():
		if id != murderer:
			rules.remove_player(id)
	check(rules.result == "murderer", "Last innocent disconnect awards murderer")
	rules = game(3)
	rules.start_round()
	murderer = role_id(rules, "murderer")
	detective = role_id(rules, "detective")
	rules.set_participating(detective, false)
	rules.set_participating(detective, true)
	check(not rules.players[detective].alive, "Rejoining cannot revive during round")
	rules.set_participating(murderer, false)
	check(rules.result == "innocents", "Murderer opting out resolves round")
