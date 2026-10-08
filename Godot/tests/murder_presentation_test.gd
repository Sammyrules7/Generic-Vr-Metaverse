extends SceneTree

var failures := 0
var assertions := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var anchor := Marker3D.new()
	anchor.name = "GameDisplay"
	world.add_child(anchor)
	var players := Node3D.new()
	world.add_child(players)
	# Load after autoload setup: the player scene includes the XR Tools globals.
	var player_scene = load("res://player/network_player.tscn")
	var local = player_scene.instantiate()
	local.name = "Local"
	players.add_child(local)
	local.controls.process_mode = Node.PROCESS_MODE_DISABLED
	local.motor.set_physics_process(false)
	var remote = player_scene.instantiate()
	remote.name = "Remote"
	remote.set_multiplayer_authority(2)
	players.add_child(remote)
	remote.set_display_name("Guest")
	var body := remote.get_node("Avatar/Body") as MeshInstance3D
	var original_material := StandardMaterial3D.new()
	original_material.albedo_color = Color.CORAL
	body.material_override = original_material
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	var ghost_details := Node3D.new()
	ghost_details.name = "GhostDetails"
	world.add_child(ghost_details)
	ghost_details.hide()
	var presentation = load("res://game_modes/murder_mystery/murder_presentation.gd").new()
	world.add_child(presentation)
	presentation.setup(players, local, world)
	var display: Node = presentation._scene_display
	var state := {"phase": "active", "remaining": 42.0,
		"self": {"alive": true, "participating": true, "role": "detective", "weapon": "gun", "equipped": false},
		"players": {2: {"alive": true, "participating": true, "weapon": "knife"}},
		"items": {"clue": {"kind": "clue", "position": Vector3(1, 1, 1)}}}
	presentation.apply_snapshot(state)
	check(remote.get_node("Avatar").is_visible_in_tree(), "Living remote avatar visible")
	check(not local.get_node("Avatar").visible, "Local duplicate avatar remains hidden")
	check(not presentation._held.has(1), "Holstered local weapon is absent")
	check(presentation._held.has(2), "Equipped remote weapon rendered")
	check(display.card.visible, "Round start reveals private role card")
	check(display.card_text.text.contains("Shoot an innocent, you die too"), "Gun role explains innocent-fire consequence")
	check(presentation.item_visuals.size() == 1, "Map pickup visual created")
	state.self.equipped = true
	presentation.apply_snapshot(state)
	check(presentation._held.has(1), "Drawing local weapon creates visual")
	check(local.controls.head.get_node_or_null("MurderAim") == null, "Physical presentation needs no aim dot")
	display._process(5.0)
	check(not display.card.visible, "Automatic card reveal expires")
	presentation.toggle_journal()
	check(display.card.visible, "Inspect opens the private card")
	for vr: bool in [true, false]:
		var old_card: Node3D = display.card
		local.set_control_mode(vr)
		local.controls.process_mode = Node.PROCESS_MODE_DISABLED
		check(not is_instance_valid(old_card), "Control switch frees the old rig's card")
		check(is_instance_valid(display.card_text) and display.card.visible, "Control switch rebuilds the inspected private card")
		check(display.card_text.text.contains("THE DETECTIVE"), "Control switch preserves the role")
		check(display.card.get_parent() == (local.controls.left_hand if vr else local.controls.head), "Card attaches to the active controls")
		check(display.card_text.text.contains("R grip:" if vr else "E collect"), "Card instructions follow control mode")
		presentation.apply_snapshot(state)
	presentation.toggle_journal()
	check(not display.card.visible, "Inspect closes the private card")
	local.controls.input_enabled = false
	display.toggle_card()
	check(not display.card.visible, "Room menu suppresses the card")
	local.controls.input_enabled = true
	display._process(0.0)
	check(display.card.visible, "Resuming restores the inspected card")
	state.players[2].alive = false
	presentation.apply_snapshot(state)
	check(not remote.get_node("Avatar").is_visible_in_tree(), "Living viewer cannot see ghost avatar")
	check(not remote.get_node("NameTag").is_visible_in_tree(), "Living viewer cannot see ghost name")
	check(body.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Ghost cannot cast visible body shadow")
	check(not presentation._held.has(2), "Death removes held weapon")
	check(not ghost_details.visible, "Living viewer cannot see ghost-only detail")
	remote.get_node("NameTag").free()
	remote.set_display_name("Arrived late")
	presentation._process(0.01)
	check(not remote.get_node("NameTag").visible, "Asynchronous name tag is hidden for ghost")
	var late_mesh := MeshInstance3D.new()
	late_mesh.mesh = SphereMesh.new()
	remote.get_node("Avatar").add_child(late_mesh)
	presentation._process(0.01)
	check(late_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Asynchronous avatar mesh cannot cast ghost shadow")
	state.self.alive = false
	presentation.apply_snapshot(state)
	check(remote.get_node("Avatar").is_visible_in_tree(), "Ghost viewers see other ghost avatars")
	check(remote.get_node("NameTag").visible, "Ghost viewers see ghost names")
	check(body.material_override.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and body.material_override.albedo_color.a < 0.5, "Ghost avatars are translucent")
	check(ghost_details.visible, "Only ghost viewer sees environmental detail")
	check(not presentation._held.has(1), "Local death clears held weapon")
	check(display.card_text.text.contains("Only ghosts can see you"), "Ghost status is explained quietly")
	state.phase = "results"
	state.result = "innocents"
	presentation.apply_snapshot(state)
	check(display.ledger_text.text.begins_with("Innocents survive"), "Innocent outcome is readable")
	state.result = "murderer"
	presentation.apply_snapshot(state)
	check(display.ledger_text.text.begins_with("The murderer prevails"), "Murderer outcome is readable")
	state.phase = "waiting"
	state.self.participating = false
	state.items.clear()
	presentation.apply_snapshot(state)
	check(not display.card.visible, "Social visitors have no private role card")
	check(presentation.item_visuals.is_empty(), "Removed pickups disappear")
	check(body.material_override == original_material, "Round reset restores avatar material")
	check(body.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED, "Round reset restores shadow setting")
	presentation.toggle_journal()
	check(not display.card.visible, "Visitor cannot inspect a role card")
	check(display.ledger_text.text.contains("Three to begin"), "Guest book explains how to start a round")
	presentation.play_attack(1, Vector3.ZERO, Vector3.FORWARD, "gun")
	presentation.play_attack(1, Vector3.ZERO, Vector3.FORWARD, "knife")
	check(presentation._attack_sounds.size() == 2, "Both attack sounds synthesized and cached")
	state.phase = "active"
	state.self.participating = true
	presentation.apply_snapshot(state)
	var old_book: Node3D = display.ledger
	var old_card: Node3D = display.card
	presentation.clear()
	check(remote.get_node("Avatar").visible and remote.get_node("NameTag").visible, "Leaving game restores avatar and late name visibility")
	check(body.material_override == original_material, "Leaving game restores original material")
	check(body.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED, "Leaving game restores shadows")
	check(not ghost_details.visible, "Leaving game restores original environmental visibility")
	check(old_book.is_queued_for_deletion() and old_card.is_queued_for_deletion(), "Leaving game removes the guest book and private card")
	var map = load("res://game_modes/murder_mystery/murder_map.gd").new()
	world.add_child(map)
	var spawns := Node3D.new()
	spawns.name = "GameSpawns"
	world.add_child(spawns)
	for index in 3:
		spawns.add_child(Marker3D.new())
	var table := Marker3D.new()
	table.name = "GameTable"
	world.add_child(table)
	check(map.valid(), "Physical display anchor satisfies the map contract")
	anchor.free()
	check(not map.valid(), "Missing display anchor rejects an unsupported map")
	world.queue_free()
	await process_frame
	await process_frame
	print("Murder presentation: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
