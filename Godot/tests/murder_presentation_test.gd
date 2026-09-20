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
	var state := {"phase": "active", "remaining": 42.0,
		"self": {"alive": true, "participating": true, "role": "detective", "weapon": "gun", "equipped": false},
		"players": {2: {"alive": true, "participating": true, "weapon": "knife"}},
		"items": {"clue": {"kind": "clue", "position": Vector3(1, 1, 1)}}}
	presentation.apply_snapshot(state)
	check(remote.get_node("Avatar").is_visible_in_tree(), "Living remote avatar visible")
	check(not local.get_node("Avatar").visible, "Local duplicate avatar remains hidden")
	check(not presentation._held.has(1), "Holstered local weapon is absent")
	check(presentation._held.has(2), "Equipped remote weapon rendered")
	check(not presentation._crosshair.visible, "Holstered weapon has no crosshair")
	check(presentation._hud.text.contains("Innocent hits kill you too"), "Gun role explains innocent-fire consequence")
	check(presentation.item_visuals.size() == 1, "Map pickup visual created")
	state.self.equipped = true
	presentation.apply_snapshot(state)
	check(presentation._held.has(1), "Drawing local weapon creates visual")
	check(presentation._crosshair.visible, "Drawing weapon shows desktop aim dot")
	local.use_vr = true
	presentation.apply_snapshot(state)
	check(not presentation._crosshair.visible, "VR has no head-locked aim dot")
	local.use_vr = false
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
	check(not presentation._held.has(1) and not presentation._crosshair.visible, "Local death clears held weapon and aim dot")
	check(presentation._hud.text.contains("Only ghosts can see you"), "Ghost status is explained quietly")
	state.phase = "results"
	state.result = "innocents"
	presentation.apply_snapshot(state)
	check(presentation._hud.text == "Innocents win", "Innocent outcome is readable")
	state.result = "murderer"
	presentation.apply_snapshot(state)
	check(presentation._hud.text == "Murderer wins", "Murderer outcome is readable")
	state.phase = "waiting"
	state.self.participating = false
	state.items.clear()
	presentation.apply_snapshot(state)
	check(not presentation._hud.visible, "Social visitors have no persistent HUD")
	check(presentation.item_visuals.is_empty(), "Removed pickups disappear")
	check(body.material_override == original_material, "Round reset restores avatar material")
	check(body.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED, "Round reset restores shadow setting")
	presentation.set_hint("E · Join next game")
	check(presentation._hud.visible and presentation._hud.text == "E · Join next game", "Visitor sees nearby join hint only")
	presentation.set_hint("")
	check(not presentation._hud.visible, "Leaving join board hides visitor HUD")
	presentation.show_feedback("Miss")
	check(presentation._hud.text == "Miss", "Feedback appears unobtrusively in status")
	presentation._process(1.3)
	check(not presentation._hud.visible, "Feedback expires")
	presentation.play_attack(1, Vector3.ZERO, Vector3.FORWARD, "gun")
	presentation.play_attack(1, Vector3.ZERO, Vector3.FORWARD, "knife")
	check(presentation._attack_sounds.size() == 2, "Both attack sounds synthesized and cached")
	state.phase = "active"
	state.self.participating = true
	presentation.apply_snapshot(state)
	var old_hud: Label3D = presentation._hud
	var old_crosshair: Label3D = presentation._crosshair
	presentation.clear()
	check(remote.get_node("Avatar").visible and remote.get_node("NameTag").visible, "Leaving game restores avatar and late name visibility")
	check(body.material_override == original_material, "Leaving game restores original material")
	check(body.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED, "Leaving game restores shadows")
	check(not ghost_details.visible, "Leaving game restores original environmental visibility")
	check(old_hud.is_queued_for_deletion() and old_crosshair.is_queued_for_deletion(), "Leaving game removes HUD and crosshair")
	world.queue_free()
	await process_frame
	await process_frame
	print("Murder presentation: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
