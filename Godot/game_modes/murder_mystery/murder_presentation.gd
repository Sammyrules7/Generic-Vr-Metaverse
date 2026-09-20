class_name MurderPresentation
extends Node
## Per-viewer presentation only. Rules, interaction and authority live elsewhere.

const ItemVisual = preload("res://game_modes/murder_mystery/murder_item_visual.gd")

var item_visuals: Dictionary = {}
var _players_root: Node3D
var _local_player: NetworkPlayer
var _map: Node3D
var _snapshot: Dictionary = {}
var _hint := ""
var _hud: Label3D
var _crosshair: Label3D
var _feedback := ""
var _feedback_remaining := 0.0
var _items_root: Node3D
var _effects_root: Node3D
var _attack_sounds: Dictionary = {}
var _ghost_details: Node3D
var _ghost_details_visible := false
var _originals: Dictionary = {}
var _held: Dictionary = {}
var _ghost_material: StandardMaterial3D
var _scene_display: Node
var _focused_item := ""


func setup(players_root: Node3D, local_player: NetworkPlayer, map: Node3D) -> void:
	clear()
	_players_root = players_root
	_local_player = local_player
	_map = map
	var display_anchor := map.get_node_or_null("GameDisplay") as Node3D
	if display_anchor != null:
		_scene_display = preload("res://game_modes/murder_mystery/murder_scene_display.gd").new()
		add_child(_scene_display)
		_scene_display.setup(local_player, display_anchor)
	_items_root = Node3D.new()
	_items_root.name = "MurderPickups"
	map.add_child(_items_root)
	_effects_root = Node3D.new()
	_effects_root.name = "MurderEffects"
	map.add_child(_effects_root)
	_ghost_details = map.find_child("GhostDetails", true, false) as Node3D
	if _ghost_details != null:
		_ghost_details_visible = _ghost_details.visible
		_ghost_details.hide()
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.albedo_color = Color(0.55, 0.76, 0.79, 0.27)
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	set_process(true)


func apply_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_refresh_items()
	_refresh_players()
	_refresh_hud()


func set_hint(text: String) -> void:
	if text == _hint:
		return
	_hint = text
	_refresh_hud()


func show_feedback(text: String) -> void:
	if is_instance_valid(_scene_display):
		# The book/card carries state. No floating hit messages in immersive maps.
		return
	_feedback = text
	_feedback_remaining = 1.2
	_refresh_hud()


func toggle_journal() -> void:
	if is_instance_valid(_scene_display):
		_scene_display.toggle_card()


func focus_item(id: String) -> void:
	if id == _focused_item:
		return
	if item_visuals.has(_focused_item):
		item_visuals[_focused_item].set_highlighted(false)
	_focused_item = id
	if item_visuals.has(id):
		item_visuals[id].set_highlighted(true)


func play_attack(_peer_id: int, origin: Vector3, direction: Vector3, weapon: String) -> void:
	if not is_instance_valid(_effects_root) or weapon not in ["gun", "knife"]:
		return
	if not _attack_sounds.has(weapon):
		_attack_sounds[weapon] = _make_attack_sound(weapon)
	var sound := AudioStreamPlayer3D.new()
	sound.stream = _attack_sounds[weapon]
	sound.volume_db = -14.0 if weapon == "gun" else -22.0
	sound.max_distance = 26.0 if weapon == "gun" else 5.0
	_effects_root.add_child(sound)
	sound.global_position = origin
	sound.finished.connect(sound.queue_free)
	sound.play()
	if weapon == "gun":
		var flash := OmniLight3D.new()
		flash.light_color = Color(1.0, 0.75, 0.4)
		flash.light_energy = 1.5
		flash.omni_range = 1.6
		_effects_root.add_child(flash)
		flash.global_position = origin + direction.normalized() * 0.4
		var fade := flash.create_tween()
		fade.tween_property(flash, "light_energy", 0.0, 0.07)
		fade.tween_callback(flash.queue_free)


func _make_attack_sound(weapon: String) -> AudioStreamWAV:
	# A short synthesized report; cached once, with no runtime asset loading.
	var rate := 22050
	var duration := 0.16 if weapon == "gun" else 0.12
	var frames := int(rate * duration)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 418
	var smooth := 0.0
	for frame in frames:
		var progress := float(frame) / frames
		var noise := random.randf_range(-1.0, 1.0)
		smooth = lerpf(smooth, noise, 0.3)
		var sample: float
		if weapon == "gun":
			sample = (noise * 0.65 + sin(float(frame) / rate * TAU * 95.0) * 0.35) * exp(-progress * 8.0)
		else:
			sample = smooth * sin(progress * PI) * 0.7
		data.encode_s16(frame * 2, int(clampf(sample, -1.0, 1.0) * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	return stream


func _process(delta: float) -> void:
	# Names and avatars can arrive after a snapshot, or change asynchronously.
	_feedback_remaining = maxf(0.0, _feedback_remaining - delta)
	if _feedback_remaining == 0.0:
		_feedback = ""
	_refresh_players()
	_refresh_hud()


func _self_state() -> Dictionary:
	return _snapshot.get("self", {})


func _is_ghost(state: Dictionary) -> bool:
	return _snapshot.get("phase", "waiting") in ["active", "results"] and (not state.get("alive", false) or not state.get("participating", false))


func _remember(node: Node3D) -> Dictionary:
	var id := node.get_instance_id()
	if not _originals.has(id):
		var record := {"node": node, "visible": node.visible}
		if node is GeometryInstance3D:
			record["material"] = node.material_override
			record["shadow"] = node.cast_shadow
		_originals[id] = record
	return _originals[id]


func _refresh_players() -> void:
	if not is_instance_valid(_players_root):
		return
	var viewer_ghost := _is_ghost(_self_state())
	if is_instance_valid(_ghost_details):
		_ghost_details.visible = viewer_ghost
	var states: Dictionary = _snapshot.get("players", {})
	var present: Dictionary = {}
	for player in _players_root.get_children():
		if not player is NetworkPlayer:
			continue
		var peer_id: int = player.get_multiplayer_authority()
		var state: Dictionary = states.get(str(peer_id), states.get(peer_id, {}))
		var local: bool = player == _local_player
		if local:
			state = _self_state()
		var ghost := _is_ghost(state)
		var visible_to_viewer := not ghost or viewer_ghost
		var avatar := player.get_node_or_null("Avatar") as Node3D
		if avatar != null:
			_remember(avatar)
			avatar.visible = not local and visible_to_viewer
			for mesh in avatar.find_children("*", "GeometryInstance3D", true, false):
				var original := _remember(mesh)
				mesh.material_override = _ghost_material if ghost else original["material"]
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if ghost else original["shadow"]
		var name_tag := player.get_node_or_null("NameTag") as Label3D
		if name_tag != null:
			var original := _remember(name_tag)
			name_tag.visible = not local and visible_to_viewer
			name_tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if ghost else original["shadow"]
		var weapon: String = str(state.get("weapon", ""))
		if local and not state.get("equipped", false):
			weapon = ""
		if ghost or not state.get("participating", false) or _snapshot.get("phase", "") != "active":
			weapon = ""
		present[peer_id] = true
		_refresh_held(player, peer_id, weapon, local)
	for peer_id in _held.keys():
		if not present.has(peer_id):
			_remove_held(peer_id)
	for id in _originals.keys():
		if not is_instance_valid(_originals[id]["node"]):
			_originals.erase(id)


func _refresh_held(player: NetworkPlayer, peer_id: int, weapon: String, local: bool) -> void:
	if weapon not in ["knife", "gun"]:
		_remove_held(peer_id)
		return
	var anchor: Node3D
	var hand := false
	if local and player.controls != null:
		hand = is_instance_valid(player.controls.right_hand)
		anchor = player.controls.right_hand if hand else player.controls.head
	else:
		hand = player.use_vr
		anchor = player.get_node_or_null("Avatar/RightHand" if hand else "Avatar/Head") as Node3D
	if not is_instance_valid(anchor):
		return
	var prop: Node3D = _held.get(peer_id)
	if not is_instance_valid(prop) or prop.get_parent() != anchor or prop.kind != weapon:
		_remove_held(peer_id)
		prop = ItemVisual.new()
		prop.name = "HeldMurderItem"
		anchor.add_child(prop)
		prop.configure(weapon)
		_held[peer_id] = prop
		prop.position = Vector3(0, 0, -0.065) if hand else Vector3(0.22, -0.23, -0.35)
		if local and not hand and weapon == "gun" and is_instance_valid(_scene_display):
			prop.position = Vector3(0, -0.078, -0.38)


func _remove_held(peer_id: int) -> void:
	var prop: Node3D = _held.get(peer_id)
	if is_instance_valid(prop):
		prop.get_parent().remove_child(prop)
		prop.queue_free()
	_held.erase(peer_id)


func _refresh_items() -> void:
	if not is_instance_valid(_items_root):
		return
	var items: Dictionary = _snapshot.get("items", {})
	for id in item_visuals.keys():
		if not items.has(id):
			var old: Node3D = item_visuals[id]
			_items_root.remove_child(old)
			old.queue_free()
			item_visuals.erase(id)
	for id in items:
		var item: Dictionary = items[id]
		var prop: Node3D = item_visuals.get(id)
		if not is_instance_valid(prop):
			prop = ItemVisual.new()
			_items_root.add_child(prop)
			item_visuals[id] = prop
		if prop.kind != str(item.get("kind", "")):
			prop.configure(str(item.get("kind", "")))
		prop.global_position = item.get("position", Vector3.ZERO)
	_items_root.visible = bool(_self_state().get("participating", false)) and _snapshot.get("phase", "") == "active"


func _refresh_hud() -> void:
	if is_instance_valid(_scene_display):
		_scene_display.update_state(_snapshot)
		return
	if not is_instance_valid(_local_player) or _local_player.controls == null:
		return
	var camera := _local_player.controls.head
	if not is_instance_valid(camera):
		return
	if not is_instance_valid(_hud):
		_hud = Label3D.new()
		_hud.name = "MurderStatus"
		_hud.font_size = 24
		_hud.pixel_size = 0.0011
		_hud.position = Vector3(0, -0.34, -1.25)
		_hud.no_depth_test = true
		_hud.modulate = Color(0.88, 0.91, 0.91, 0.9)
		_hud.outline_modulate = Color(0.04, 0.05, 0.06, 0.85)
		_hud.outline_size = 5
		camera.add_child(_hud)
	if not is_instance_valid(_crosshair):
		_crosshair = Label3D.new()
		_crosshair.name = "MurderAim"
		_crosshair.text = "·"
		_crosshair.font_size = 24
		_crosshair.pixel_size = 0.0006
		_crosshair.position = Vector3(0, 0, -1.0)
		_crosshair.no_depth_test = true
		_crosshair.modulate = Color(0.9, 0.93, 0.93, 0.65)
		camera.add_child(_crosshair)
	var state := _self_state()
	_crosshair.visible = not _local_player.use_vr and _snapshot.get("phase", "") == "active" and bool(state.get("alive", false)) and bool(state.get("participating", false)) and bool(state.get("equipped", false)) and str(state.get("weapon", "")) in ["knife", "gun"]
	var lines: PackedStringArray = []
	if state.get("participating", false):
		var phase: String = _snapshot.get("phase", "waiting")
		match phase:
			"active":
				if _is_ghost(state):
					lines.append("Ghost · Only ghosts can see you")
				else:
					var role: String = str(state.get("role", "bystander")).capitalize()
					var seconds := maxi(0, int(ceil(float(_snapshot.get("remaining", 0.0)))))
					lines.append("%s · %d:%02d" % [role, seconds / 60, seconds % 60])
					match str(state.get("role", "")):
						"murderer": lines.append("Eliminate the others")
						"detective": lines.append("Find the murderer · Innocent hits kill you too")
						"bystander":
							if str(state.get("weapon", "")) == "gun":
								lines.append("Find the murderer · Innocent hits kill you too")
							else:
								lines.append("Clues %d/5 · Find five or recover a gun" % int(state.get("clues", 0)))
			"countdown":
				lines.append("Round starts in %d" % maxi(0, int(ceil(float(_snapshot.get("remaining", 0))))))
			"results":
				var result: String = str(_snapshot.get("result", "Round finished"))
				lines.append({"innocents": "Innocents win", "murderer": "Murderer wins"}.get(result, result.replace("_", " ").capitalize()))
			"waiting":
				lines.append("Joined · Waiting for players")
	if not _hint.is_empty():
		lines.append(_hint)
	if not _feedback.is_empty():
		lines.append(_feedback)
	_hud.text = "\n".join(lines)
	_hud.visible = not lines.is_empty()


func clear() -> void:
	set_process(false)
	if is_instance_valid(_scene_display):
		_scene_display.free()
	_scene_display = null
	_focused_item = ""
	for peer_id in _held.keys():
		_remove_held(peer_id)
	for record in _originals.values():
		var node: Node3D = record["node"]
		if not is_instance_valid(node):
			continue
		node.visible = record["visible"]
		if node is GeometryInstance3D:
			node.material_override = record["material"]
			node.cast_shadow = record["shadow"]
	_originals.clear()
	if is_instance_valid(_ghost_details):
		_ghost_details.visible = _ghost_details_visible
	if is_instance_valid(_items_root):
		_items_root.queue_free()
	if is_instance_valid(_effects_root):
		_effects_root.queue_free()
	if is_instance_valid(_hud):
		_hud.queue_free()
	if is_instance_valid(_crosshair):
		_crosshair.queue_free()
	_items_root = null
	_effects_root = null
	_hud = null
	_crosshair = null
	_players_root = null
	_local_player = null
	_map = null
	_ghost_details = null
	item_visuals.clear()
	_snapshot.clear()
	_hint = ""
	_feedback = ""
	_feedback_remaining = 0.0


func _exit_tree() -> void:
	clear()
