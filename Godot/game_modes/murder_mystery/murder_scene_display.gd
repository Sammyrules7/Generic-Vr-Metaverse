extends Node
## A physical guest book and a local-only hand card. No screen overlay or aim dot.
var ledger: Node3D
var card: Node3D
var ledger_text: Label3D
var card_text: Label3D
var _player: NetworkPlayer
var _snapshot: Dictionary = {}
var _last_round := -1
var _card_seconds := 0.0
var _inspect := false
var _pips: Array[MeshInstance3D] = []
var _ink: StandardMaterial3D
var _gold: StandardMaterial3D
var _was_alive := false

const GUEST_BOOK := preload("res://game_modes/murder_mystery/guest_book.tscn")
const PRIVATE_CARD := preload("res://game_modes/murder_mystery/private_card.tscn")

func setup(player: NetworkPlayer, anchor: Node3D) -> void:
	_player = player
	_ink = StandardMaterial3D.new()
	_ink.albedo_color = Color("283139")
	_ink.roughness = 0.95
	ledger = GUEST_BOOK.instantiate()
	anchor.add_child(ledger)
	ledger_text = ledger.get_node("Status")
	_player.controls_changed.connect(_attach_card)
	_attach_card()

func _attach_card() -> void:
	# Switching control modes replaces the rig and frees its old private card.
	card = PRIVATE_CARD.instantiate()
	var hand := _player.controls.left_hand
	var anchor := hand if is_instance_valid(hand) else _player.controls.head
	anchor.add_child(card)
	if is_instance_valid(hand):
		card.position = Vector3(0, 0.075, -0.09)
		card.rotation = Vector3(-0.8, 0, 0)
	card_text = card.get_node("Status")
	_pips.clear()
	for index in 5:
		_pips.append(card.get_node("Pip%d" % index))
	_gold = _pips[0].material_override
	update_state(_snapshot)

func update_state(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	var state: Dictionary = snapshot.get("self", {})
	var phase: String = snapshot.get("phase", "waiting")
	if snapshot.is_empty():
		_last_round = -1
	var count := 0
	for member: Dictionary in snapshot.get("players", {}).values():
		if member.get("participating", false):
			count += 1
	var public_text := "Awaiting guests\n%d signed\n\nThree to begin" % count
	var seconds := maxi(0, ceili(float(snapshot.get("remaining", 0))))
	@warning_ignore("integer_division")
	var minutes := seconds / 60
	match phase:
		"countdown": public_text = "The next game\nbegins in %d\n\n%d guests signed" % [seconds, count]
		"active": public_text = "A game is in progress\n%d:%02d remaining\n\nNew guests watch\nuntil the next round" % [minutes, seconds % 60]
		"results": public_text = "Innocents survive" if snapshot.get("result", "") == "innocents" else "The murderer prevails"
	if state.get("participating", false):
		public_text += "\n\nYour name is signed\nE / right grip to leave"
	ledger_text.text = public_text
	var role: String = state.get("role", "spectator")
	var lines := "Waiting for the next game"
	if phase in ["active", "results"]:
		if not state.get("alive", false):
			lines = "A GHOST\nOnly ghosts can see you\nWatch until the next game"
		elif role == "murderer":
			lines = "THE MURDERER\nLeave no witnesses\nKeep your blade concealed"
		elif role == "detective" or state.get("weapon", "") == "gun":
			lines = ("THE DETECTIVE" if role == "detective" else "A BYSTANDER") + "\nStop the murderer\nShoot an innocent, you die too"
		else:
			lines = "A BYSTANDER\nSurvive. Find five clues\nOr recover a fallen gun"
		lines += "\n%d:%02d" % [minutes, seconds % 60]
	var controls := "R grip: collect · L grip: draw\nR trigger: use · L trigger: drop" if _player.use_vr else "E collect · R draw\nClick use · Q drop"
	card_text.text = lines + "\n\n" + controls
	for index in _pips.size():
		_pips[index].material_override = _ink if index < int(state.get("clues", 0)) else _gold
	if phase == "active" and int(snapshot.get("round_id", 0)) != _last_round:
		_last_round = int(snapshot.get("round_id", 0))
		if state.get("participating", false):
			_card_seconds = 4.5
	if _was_alive and not state.get("alive", false) and state.get("participating", false):
		_card_seconds = 3.5
	_was_alive = bool(state.get("alive", false))
	if not state.get("participating", false):
		_inspect = false
		_card_seconds = 0.0
	_update_visibility()

func toggle_card() -> void:
	if _snapshot.get("self", {}).get("participating", false):
		_inspect = not _inspect
		_card_seconds = 0.0
		_update_visibility()

func _process(delta: float) -> void:
	_card_seconds = maxf(0, _card_seconds - delta)
	_update_visibility()

func _update_visibility() -> void:
	if is_instance_valid(card):
		card.visible = (_inspect or _card_seconds > 0) and is_instance_valid(_player) and _player.controls.input_enabled

func _exit_tree() -> void:
	if is_instance_valid(_player) and _player.controls_changed.is_connected(_attach_card):
		_player.controls_changed.disconnect(_attach_card)
	if is_instance_valid(ledger):
		ledger.queue_free()
	if is_instance_valid(card):
		card.queue_free()
