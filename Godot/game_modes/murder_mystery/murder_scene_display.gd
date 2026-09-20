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
var _paper: StandardMaterial3D
var _was_alive := false

func setup(player: NetworkPlayer, anchor: Node3D) -> void:
	_player = player
	_ink = _material(Color("283139"))
	_gold = _material(Color("986e39"))
	_paper = _material(Color("d4c29a"))
	ledger = Node3D.new()
	ledger.name = "GuestBook"
	anchor.add_child(ledger)
	_box(ledger, Vector3(0.82, 0.48, 0.035), Vector3.ZERO, _material(Color("382927")))
	_box(ledger, Vector3(0.38, 0.43, 0.02), Vector3(-0.2, 0, 0.027), _paper)
	_box(ledger, Vector3(0.38, 0.43, 0.02), Vector3(0.2, 0, 0.027), _paper)
	_box(ledger, Vector3(0.015, 0.43, 0.006), Vector3(0, 0, 0.041), _gold)
	var title := _label(ledger, "THE EVENING GAME", Vector3(-0.2, 0.165, 0.043), 0.0011, 27)
	title.modulate = Color("704a34")
	_label(ledger, "Sign the guest book\nE / right grip\n\nThree guests to begin\n\nYour private card\nTab / left A or X\n\nVisitors welcome.", Vector3(-0.2, -0.023, 0.043), 0.001, 26)
	ledger_text = _label(ledger, "Awaiting guests", Vector3(0.2, 0.025, 0.043), 0.001, 27)
	# The card is private because it only exists on this client's controls rig.
	card = Node3D.new()
	card.name = "PrivateCaseCard"
	var hand := _player.controls.left_hand
	var anchor_node := hand if is_instance_valid(hand) else _player.controls.head
	anchor_node.add_child(card)
	if is_instance_valid(hand):
		card.position = Vector3(0, 0.075, -0.09)
		card.rotation.x = -0.8
	else:
		card.position = Vector3(-0.12, -0.18, -0.53)
		card.rotation_degrees = Vector3(-8, 6, -4)
	var card_paper := _paper.duplicate() as StandardMaterial3D
	card_paper.emission_enabled = true
	card_paper.emission = Color("776c50")
	card_paper.emission_energy_multiplier = 0.2
	_box(card, Vector3(0.34, 0.25, 0.004), Vector3.ZERO, card_paper)
	_box(card, Vector3(0.30, 0.002, 0.001), Vector3(0, 0.085, 0.004), _gold)
	_box(card, Vector3(0.30, 0.002, 0.001), Vector3(0, -0.08, 0.004), _gold)
	_label(card, "PRIVATE · YOUR PART", Vector3(0, 0.103, 0.004), 0.00055, 24)
	card_text = _label(card, "", Vector3(0, 0.009, 0.004), 0.00062, 27)
	for index in 5:
		var mark := _box(card, Vector3(0.013, 0.009, 0.001), Vector3(-0.042 + index * 0.021, -0.097, 0.004), _gold)
		_pips.append(mark)
	card.visible = false

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
	match phase:
		"countdown": public_text = "The next game\nbegins in %d\n\n%d guests signed" % [seconds, count]
		"active": public_text = "A game is in progress\n%d:%02d remaining\n\nNew guests watch\nuntil the next round" % [seconds / 60, seconds % 60]
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
		lines += "\n%d:%02d" % [seconds / 60, seconds % 60]
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

func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	return mat

func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = mat
	parent.add_child(instance)
	instance.position = at
	return instance

func _label(parent: Node3D, text: String, at: Vector3, pixel: float, font_size: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel
	label.modulate = Color("2c302c")
	label.outline_size = 0
	label.shaded = true
	label.double_sided = false
	label.no_depth_test = false
	parent.add_child(label)
	label.position = at
	return label

func _exit_tree() -> void:
	if is_instance_valid(ledger):
		ledger.queue_free()
	if is_instance_valid(card):
		card.queue_free()
