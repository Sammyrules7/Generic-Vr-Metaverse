class_name MurderPresentation
extends Node
## Per-viewer presentation only. Rules, interaction and authority live elsewhere.

const ItemVisual = preload("res://game_modes/murder_mystery/murder_item_visual.gd")

var item_visuals: Dictionary = {}
var _players_root: Node3D
var _local_player: NetworkPlayer
var _snapshot: Dictionary = {}
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
var _avatar_meshes: Dictionary = {}
var _avatar_mesh_counts: Dictionary = {}
var _avatar_refs: Dictionary = {}
var _nametag_refs: Dictionary = {}
var _player_style: Dictionary = {}
var _mesh_watch: Dictionary = {}


func setup(players_root: Node3D, local_player: NetworkPlayer, map: Node3D) -> void:
	clear()
	_players_root = players_root
	_local_player = local_player
	_scene_display = preload("res://game_modes/murder_mystery/murder_scene_display.gd").new()
	add_child(_scene_display)
	_scene_display.setup(local_player, map.get_node("GameDisplay"))
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
	_scene_display.update_state(_snapshot)


func toggle_journal() -> void:
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


func _process(_delta: float) -> void:
	# Names and avatars can arrive after a snapshot, or change asynchronously.
	# The mesh lists below are cached per player, so the steady-state frame
	# only restyles players whose ghost/visibility/weapon state actually changed.
	_refresh_players()


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


func _avatar_meshes_cached(player: NetworkPlayer, avatar: Node3D) -> Array:
	var id := player.get_instance_id()
	var cached: Variant = _avatar_meshes.get(id)
	var fresh_needed := true
	if cached != null and cached is Array:
		var list := cached as Array
		if list.size() == int(_avatar_mesh_counts.get(id, -1)) and (list.is_empty() or is_instance_valid(list[0])):
			fresh_needed = false
			return list
	if fresh_needed:
		var fresh := avatar.find_children("*", "GeometryInstance3D", true, false)
		_avatar_meshes[id] = fresh
		_avatar_mesh_counts[id] = fresh.size()
		return fresh
	return []


func _avatar_cached(player: NetworkPlayer) -> Node3D:
	var id := player.get_instance_id()
	# is_instance_valid is the only freed-safe check; `is`/`as` error on
	# freed instances, so guard with it before touching the cached ref.
	var cached: Variant = _avatar_refs.get(id)
	if cached != null and is_instance_valid(cached):
		return cached as Node3D
	var avatar := player.get_node_or_null("Avatar") as Node3D
	if avatar != null:
		_avatar_refs[id] = avatar
	return avatar


func _nametag_cached(player: NetworkPlayer) -> Label3D:
	var id := player.get_instance_id()
	var cached: Variant = _nametag_refs.get(id)
	if cached != null and is_instance_valid(cached):
		return cached as Label3D
	var tag := player.get_node_or_null("NameTag") as Label3D
	if tag != null:
		_nametag_refs[id] = tag
	return tag


func _watch_avatar(player_id: int, avatar: Node3D) -> void:
	var aid := avatar.get_instance_id()
	if _mesh_watch.has(aid):
		return
	_mesh_watch[aid] = player_id
	avatar.child_entered_tree.connect(_on_avatar_child_changed.bind(player_id))
	avatar.child_exiting_tree.connect(_on_avatar_child_changed.bind(player_id))


func _on_avatar_child_changed(_node: Node, player_id: int) -> void:
	_avatar_meshes.erase(player_id)
	_avatar_mesh_counts.erase(player_id)
	_player_style.erase(player_id)


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
		var weapon: String = str(state.get("weapon", ""))
		if local and not state.get("equipped", false):
			weapon = ""
		if ghost or not state.get("participating", false) or _snapshot.get("phase", "") != "active":
			weapon = ""
		var avatar := _avatar_cached(player)
		var name_tag := _nametag_cached(player)
		if avatar != null:
			_watch_avatar(player.get_instance_id(), avatar)
		# Steady-state frames skip engine writes entirely. Node identity is
		# part of the style so freed/recreated tags and late meshes restyle
		# on arrival; any ghost/visibility/weapon change restyles immediately.
		var style := [ghost, visible_to_viewer, weapon, avatar.get_instance_id() if avatar != null else 0, name_tag.get_instance_id() if name_tag != null else 0]
		var meshes: Array = []
		if avatar != null:
			meshes = _avatar_meshes_cached(player, avatar)
			style.append(meshes.size())
		var last: Variant = _player_style.get(player.get_instance_id())
		if last != null and last is Array and (last as Array) == style:
			present[peer_id] = true
			_refresh_held(player, peer_id, weapon, local)
			continue
		_player_style[player.get_instance_id()] = style
		if avatar != null:
			_remember(avatar)
			# The avatar container owns first-person head/hand visibility. Keep the
			# local body visible too; game rules still hide ghosts from living peers.
			avatar.visible = visible_to_viewer
			for mesh in meshes:
				var original := _remember(mesh)
				mesh.material_override = _ghost_material if ghost else original["material"]
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if ghost else original["shadow"]
		if name_tag != null:
			var original := _remember(name_tag)
			name_tag.visible = not local and visible_to_viewer
			name_tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if ghost else original["shadow"]
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
	# A control-mode switch frees props attached to the previous rig.
	var prop = _held.get(peer_id)
	if not is_instance_valid(prop) or prop.get_parent() != anchor or prop.kind != weapon:
		_remove_held(peer_id)
		prop = ItemVisual.new()
		prop.name = "HeldMurderItem"
		anchor.add_child(prop)
		prop.configure(weapon)
		_held[peer_id] = prop
		prop.position = Vector3(0, 0, -0.065) if hand else Vector3(0.22, -0.23, -0.35)
		if local and not hand and weapon == "gun":
			prop.position = Vector3(0, -0.078, -0.38)


func _remove_held(peer_id: int) -> void:
	var prop = _held.get(peer_id)
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
	_avatar_meshes.clear()
	_avatar_mesh_counts.clear()
	_avatar_refs.clear()
	_nametag_refs.clear()
	_player_style.clear()
	_mesh_watch.clear()
	if is_instance_valid(_ghost_details):
		_ghost_details.visible = _ghost_details_visible
	if is_instance_valid(_items_root):
		_items_root.queue_free()
	if is_instance_valid(_effects_root):
		_effects_root.queue_free()
	_items_root = null
	_effects_root = null
	_players_root = null
	_local_player = null
	_ghost_details = null
	item_visuals.clear()
	_snapshot.clear()


func _exit_tree() -> void:
	clear()
