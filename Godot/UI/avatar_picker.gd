extends PanelContainer
## Avatar picker card. One instance lives inside the room selector and serves
## both the lobby ("Avatar settings") and the in-room session menu exactly like
## the voice settings submenu: owning cards hide while it is open, Escape and
## "Done" close it, and focus returns to the button that opened it.
##
## The 3D preview owns a distinct scene instance acquired from AvatarService;
## the request lease is released when switching avatars, closing the card, or
## freeing the card, so neither the main window nor remote peers are affected.
## The preview renders the third-person layer only (the imported model marks the
## first-person duplicate as layer 2) and stays static unless the native spring
## installer is available, in which case it mirrors the current preference.

signal closed

const STATUS_COLOR := Color("#a0bdd4")
const HINT_COLOR := Color("#74869a")
const ERROR_COLOR := Color("#f28b82")

const DEFAULT_ID := "default"
const SPRINGS_SCRIPT := "res://avatar/avatar_springs.gd"

var _pending_id := DEFAULT_ID
var _applied_id := DEFAULT_ID
var _generation := 0
var _request: AvatarLoadRequest
var _model: Node3D
var _model_bounds := AABB()
var _simulators: Array = []
var _selection_group := ButtonGroup.new()
var _buttons: Dictionary = {}
const BATCH_SIZE := 18
var _loaded_count := 0
var _next_append_frame := 0
var _filtered: Array[Dictionary] = []
var _favorites_only := false
var _collection_buttons: Array[Button] = []
var _thumbnails: AvatarThumbnails
var _preview_ready := true
var _prefetch: AvatarLoadRequest
var _hover_id := ""
var _hover_generation := 0
var _fallback_preview: Node3D

@onready var _list: GridContainer = %AvatarList
@onready var _scroll: ScrollContainer = %AvatarListScroll
@onready var _apply: Button = %Apply
@onready var _stage: Node3D = %Stage


func _ready() -> void:
	_apply.pressed.connect(_apply_pressed)
	%CloseAvatarSettings.pressed.connect(close)
	%CloseAvatarSettings.icon = preload("res://UI/icons/avatar/done.svg")
	%AvatarSearch.text_changed.connect(func(_text: String): _filter_changed())
	%CollectionFilter.add_item("All collections")
	for collection in AvatarCatalog.collections():
		%CollectionFilter.add_item(collection)
	%CollectionFilter.item_selected.connect(func(_index: int): _filter_changed())
	_build_collection_navigation()
	%BrowseAll.pressed.connect(_browse_all)
	%BrowseFavorites.pressed.connect(_browse_favorites)
	%FavoriteAvatar.pressed.connect(_toggle_favorite)
	%RetryPreview.pressed.connect(func(): _show_preview(_pending_id))
	_thumbnails = AvatarThumbnails.new()
	add_child(_thumbnails)
	_thumbnails.loaded.connect(_thumbnail_loaded)
	%FavoriteAvatar.icon = preload("res://UI/icons/avatar/favorite.svg")
	_style_browser.call_deferred()
	_layout_preview_stage()
	AvatarService.selection_changed.connect(_selection_changed)
	AvatarService.springs_changed.connect(_springs_changed)
	set_open(false)


func _layout_preview_stage() -> void:
	# Mirror the lobby's world-preview frame styling and aim simple studio
	# lights; hand-written rotation matrices in the scene file are easy to get
	# wrong, so the small fixed stage is composed here instead.
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("#21344b")
	frame.set_corner_radius_all(14)
	%PreviewFrame.add_theme_stylebox_override("panel", frame)
	var key := %KeyLight as DirectionalLight3D
	key.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-30), 0)
	var fill := %FillLight as DirectionalLight3D
	fill.rotation = Vector3(deg_to_rad(-20), deg_to_rad(150), 0)
	# The preview SubViewport reflows with the card; keep the camera framed.
	var camera := %Camera as Camera3D
	camera.get_viewport().size_changed.connect(_frame_camera)


func set_open(open: bool) -> void:
	if open == visible:
		return
	visible = open
	if open:
		_rebuild()
	else:
		# Bump the generation before releasing so a completion emitted during
		# the release already reads as stale to its awaiting coroutine.
		_generation += 1
		_release_request()
		_clear_model()
		_thumbnails.cancel_pending()
		_cancel_prefetch()


func close() -> void:
	closed.emit()
	set_open(false)


func focus_entry() -> void:
	if _list.get_child_count() > 0:
		_list.get_child(0).grab_focus()
	else:
		%CloseAvatarSettings.grab_focus()


func _process(delta: float) -> void:
	if visible:
		_layout_browser()
	if not visible:
		# A hidden SubViewport stops rendering; the orbit must not unwind either.
		return
	if _model != null or (_fallback_preview != null and _fallback_preview.visible):
		_stage.rotation.y = fmod(_stage.rotation.y + delta * 0.35, TAU)
	_maybe_append_batch()
	if _request != null and not _request.finished:
		_update_download_progress()


func _rebuild() -> void:
	_applied_id = _safe_id(PlayerProfile.avatar_id)
	_pending_id = _applied_id
	%AvatarSearch.text = ""
	%CollectionFilter.select(0)
	_favorites_only = false
	_filter_changed()
	_sync_selection(_pending_id, true)


func _filter_changed() -> void:
	var collection: String = %CollectionFilter.get_item_text(%CollectionFilter.selected) if %CollectionFilter.selected > 0 else ""
	_filtered = AvatarCatalog.search(%AvatarSearch.text, collection)
	if _favorites_only:
		_filtered = _filtered.filter(func(entry: Dictionary): return str(entry.id) in PlayerProfile.avatar_favorites)
	var scope := "Favorites" if _favorites_only else collection if not collection.is_empty() else "All avatars"
	%AvatarSearch.placeholder_text = "Search all" if scope == "All avatars" else "Search in %s" % scope
	%AvatarSearch.tooltip_text = %AvatarSearch.placeholder_text
	%ResultCount.text = str(_filtered.size())
	%BrowseAll.set_pressed_no_signal(not _favorites_only and collection.is_empty())
	%BrowseFavorites.set_pressed_no_signal(_favorites_only)
	for index in _collection_buttons.size():
		_collection_buttons[index].set_pressed_no_signal(not _favorites_only and %CollectionFilter.selected == index + 1)
	_refresh_list()


func _refresh_list() -> void:
	_cancel_prefetch()
	_thumbnails.cancel_pending()
	_scroll.scroll_vertical = 0
	for child in _list.get_children():
		child.free()
	_buttons.clear()
	_loaded_count = 0
	%EmptyResults.visible = _filtered.is_empty()
	%EmptyResults.text = "Your favorites will appear here.\nChoose a look and select the star to save it." if _favorites_only else "No matching avatars.\nTry another collection or clear your search."
	%ListFrame.visible = not _filtered.is_empty()
	_append_batch()


func _maybe_append_batch() -> void:
	if _loaded_count >= _filtered.size() or not _scroll.is_visible_in_tree() or Engine.get_process_frames() < _next_append_frame:
		return
	var bar := _scroll.get_v_scroll_bar()
	if bar.value + bar.page >= bar.max_value - 240.0:
		_append_batch()


func _append_batch() -> void:
	var owner_ui := get_parent()
	var end := mini(_loaded_count + BATCH_SIZE, _filtered.size())
	for entry: Dictionary in _filtered.slice(_loaded_count, end):
		var id := str(entry.get("id", ""))
		if id.is_empty():
			continue
		var button := _make_avatar_card(entry)
		_list.add_child(button)
		if owner_ui != null and owner_ui.has_method("_configure_buttons"):
			owner_ui.call("_configure_buttons", button)
		_buttons[id] = button
		var texture := _thumbnails.request(AvatarAssets.url(id, "thumbnail"))
		if texture != null:
			_set_card_thumbnail(button, texture)
	_loaded_count = end
	# Wait for the grid/scroll range to settle before checking the threshold.
	_next_append_frame = Engine.get_process_frames() + 2


func sync_pending(id: String) -> void:
	if id == _pending_id or not AvatarCatalog.has_avatar(id):
		return
	_pending_id = id
	var thumbnail_url := AvatarAssets.url(id, "thumbnail")
	var thumbnail := _thumbnails.prioritize(thumbnail_url)
	if thumbnail != null and _buttons.has(id):
		_set_card_thumbnail(_buttons[id], thumbnail)
	_sync_selection(id, true)


func _selection_changed(id: String) -> void:
	var avatar_id := _safe_id(id)
	_applied_id = avatar_id
	if avatar_id != _pending_id:
		_pending_id = avatar_id
		_sync_selection(avatar_id, is_visible())
		return
	if is_visible():
		_sync_selection(avatar_id, false)


func _update_apply() -> void:
	_apply.disabled = _pending_id == _applied_id or not _preview_ready
	_apply.text = "Wearing" if _pending_id == _applied_id else "Wear avatar" if _preview_ready else "Loading..."


func _sync_selection(id: String, with_preview: bool) -> void:
	for entry_id in _buttons:
		(_buttons[entry_id] as Button).set_pressed_no_signal(entry_id == id)
		var badge: Label = _buttons[entry_id].get_node("Card/Credits/Badge")
		badge.visible = entry_id == _applied_id
	var entry := AvatarCatalog.definition(id)
	if entry.is_empty():
		_apply.disabled = true
		_set_status("This avatar is no longer in the catalog.", true)
		return
	_update_apply()
	%SelectedTitle.text = str(entry.get("title", id))
	_layout_browser()
	%FavoriteAvatar.set_pressed_no_signal(id in PlayerProfile.avatar_favorites)
	%FavoriteAvatar.icon = load("res://UI/icons/avatar/favorite_saved.svg" if id in PlayerProfile.avatar_favorites else "res://UI/icons/avatar/favorite.svg")
	var license := str(entry.get("license", ""))
	%Attribution.text = license
	%Attribution.tooltip_text = str(entry.get("attribution", license))
	if with_preview:
		_show_preview(id)


func _safe_id(id: String) -> String:
	return id if AvatarCatalog.has_avatar(id) else DEFAULT_ID


func _title_for(id: String) -> String:
	var entry := AvatarCatalog.definition(id)
	return str(entry.get("title", id)) if not entry.is_empty() else id


func _show_preview(id: String) -> void:
	_generation += 1
	var generation := _generation
	_release_request()
	_clear_model()
	_preview_ready = false
	%DownloadProgress.show()
	%DownloadProgress.indeterminate = true
	%RetryPreview.hide()
	_update_apply()
	if AvatarCatalog.definition(id).is_empty():
		_set_status("This avatar is no longer in the catalog.", true)
		return
	var thumbnail := _thumbnails.request(AvatarAssets.url(id, "thumbnail"))
	%PreviewThumbnail.texture = thumbnail
	%PreviewThumbnail.visible = thumbnail != null
	var request := AvatarService.acquire(id)
	_request = request
	_cancel_prefetch()
	if request.finished:
		# The lease can complete instantly (cached or bundled): no await needed.
		_process_result(request, id, generation)
		return
	_set_status("Loading %s..." % _title_for(id))
	await request.completed
	if generation != _generation:
		return
	_process_result(request, id, generation)


func _process_result(request: AvatarLoadRequest, _id: String, generation: int) -> void:
	if generation != _generation or request.released:
		# A stale or released lease must not touch the current preview.
		return
	%DownloadProgress.hide()
	var error := request.error
	var scene := request.scene
	_release_request()
	if not error.is_empty():
		_set_status(error, true)
		%RetryPreview.show()
		_apply.text = "Preview unavailable"
		return
	%PreviewThumbnail.hide()
	if scene == null:
		# The bundled default has no model: rooms render a simple fallback body.
		_show_default_preview()
		_preview_ready = true
		_update_apply()
		_set_status("")
		return
	if not _place_model(scene):
		_set_status("This avatar could not be shown in the preview.", true)
		%RetryPreview.show()
		_apply.text = "Preview unavailable"
		return
	_preview_ready = true
	_update_apply()
	_set_status("")


func _place_model(scene: PackedScene) -> bool:
	_clear_model()
	var model := scene.instantiate() as Node3D
	if model == null:
		return false
	_model = model
	model.name = "PreviewAvatar"
	_stage.add_child(model)
	_fit_model(model)
	# One install per preview model, even with the preference disabled, so
	# toggling springs later just flips the returned simulators' active state.
	_configure_model_simulation()
	return true


func _fit_model(model: Node3D) -> void:
	# The loader normalizes avatars on the mesh side (standing eye height 1.7)
	# without node scaling (AvatarScale), so the preview keeps scale ONE and
	# frames the model purely through camera placement.
	var combined := AABB()
	var have := false
	for node in model.find_children("*", "VisualInstance3D", true, false):
		var instance := node as VisualInstance3D
		if instance.get_aabb().size.length_squared() <= 0.0:
			continue
		# Frame the child geometry in the model's own space; this stays correct
		# even while the stage orbits.
		var relative: Transform3D = model.global_transform.inverse() * instance.global_transform
		var local_box: AABB = relative * instance.get_aabb()
		combined = local_box if not have else combined.merge(local_box)
		have = true
	if not have:
		model.position.y = 0.6
		return
	if combined.size.y <= 0.001:
		model.position.y = 0.6
		return
	# Settle the model: feet on the origin and XZ centered. Translation only:
	# relative bone/skin poses stay untouched for the spring simulators.
	var center := combined.get_center()
	model.position = Vector3(-center.x, -combined.position.y, -center.z)
	_model_bounds = combined
	_frame_camera()


func _frame_camera() -> void:
	# Fit through camera distance so the model keeps scale ONE.
	if _model_bounds.size.y <= 0.001:
		return
	var camera := %Camera as Camera3D
	var viewport := camera.get_viewport()
	var aspect := viewport.get_visible_rect().size.x
	aspect = aspect / maxf(viewport.get_visible_rect().size.y, 1.0)
	var vfov := deg_to_rad(camera.fov)
	var hfov := 2.0 * atan(tan(vfov * 0.5) * maxf(aspect, 0.001))
	var half_height := _model_bounds.size.y * 0.5
	var half_width := maxf(_model_bounds.size.x, _model_bounds.size.z) * 0.5
	var distance := maxf(half_height / tan(vfov * 0.5), half_width / tan(hfov * 0.5)) * 1.1
	var center := _model_bounds.get_center()
	camera.position = Vector3(0, center.y, distance)


## Springs install exactly once per preview model — even when the preference
## is off — so toggling later never stacks disabled duplicates; the returned
## native simulators are toggled/reset in place. When the native installer is
## unavailable, the vendored VRM secondary's scripted (loop + modifier-driven)
## simulation is silenced instead and the pose stays static.
func _configure_model_simulation() -> void:
	_simulators.clear()
	var installer: Script = load(SPRINGS_SCRIPT) if ResourceLoader.exists(SPRINGS_SCRIPT) else null
	if installer == null or not installer.has_method("install") or _model == null:
		_still_vrm_secondary(_model)
		return
	_simulators = installer.call("install", _model)
	_update_simulators()


func _springs_changed(enabled: bool) -> void:
	_update_simulators()


func _update_simulators() -> void:
	for simulator: Variant in _simulators:
		if simulator != null and is_instance_valid(simulator) and "active" in simulator:
			simulator.set("active", PlayerProfile.spring_bones_enabled)
			if PlayerProfile.spring_bones_enabled and simulator.has_method("reset"):
				simulator.call("reset")


func _still_vrm_secondary(model: Node3D) -> void:
	for node: Node in _simulation_nodes(model):
		node.set_process(false)
		node.set_physics_process(false)
		for connection: Dictionary in node.get_incoming_connections():
			# The vendored secondary is also driven by the skeleton's internal
			# modifier's modification_processed callback — the signal belongs to
			# that modifier node, so disconnect on the emitting Signal itself
			# rather than on the secondary node.
			var emitter: Variant = connection.get("signal")
			if emitter is Signal:
				if (emitter as Signal).get_name() == &"modification_processed":
					(emitter as Signal).disconnect(connection["callable"])
			elif emitter is Dictionary:
				var definition := emitter as Dictionary
				if str(definition.get("name", "")) == "modification_processed":
					var owner_node: Variant = definition.get("object")
					if owner_node != null:
						owner_node.call("disconnect", &"modification_processed", connection["callable"])


func _simulation_nodes(model: Node3D) -> Array:
	var nodes := []
	var candidates := [model] as Array
	candidates.append_array(model.find_children("*", "Node3D", true, false))
	for node: Node in candidates:
		var script: Script = node.get_script()
		if script != null and str(script.resource_path).ends_with("vrm_secondary.gd"):
			nodes.append(node)
	return nodes


func _apply_pressed() -> void:
	if _apply.disabled or _pending_id.is_empty() or not AvatarCatalog.has_avatar(_pending_id):
		return
	AvatarService.select_avatar(_pending_id)


func _set_status(message: String, is_error := false, is_hint := false) -> void:
	var status: Label = %PreviewStatus
	status.visible = not message.is_empty()
	status.text = message
	if message.is_empty():
		return
	if is_error:
		status.add_theme_color_override("font_color", ERROR_COLOR)
	elif is_hint:
		status.add_theme_color_override("font_color", HINT_COLOR)
	else:
		status.add_theme_color_override("font_color", STATUS_COLOR)


func _release_request() -> void:
	var request := _request
	_request = null
	if request != null:
		request.release()


func _clear_model() -> void:
	%PreviewThumbnail.hide()
	%PreviewThumbnail.texture = null
	%DownloadProgress.hide()
	if _fallback_preview != null:
		_fallback_preview.hide()
	if is_instance_valid(_model):
		_model.free()
	_model = null
	# Installed simulators were children of the model and left with it.
	_simulators.clear()
	_model_bounds = AABB()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_cancel_prefetch()
		# The picker may be freed mid-flight; never leave the service's lease.
		_generation += 1
		_release_request()
		_clear_model()


func _build_collection_navigation() -> void:
	for index in range(1, %CollectionFilter.item_count):
		var collection: String = %CollectionFilter.get_item_text(index)
		var button := Button.new()
		button.text = collection
		button.tooltip_text = collection
		button.toggle_mode = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.custom_minimum_size = Vector2(154, 38)
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(_choose_collection.bind(index))
		%Collections.add_child(button)
		_collection_buttons.append(button)


func _choose_collection(index: int) -> void:
	_favorites_only = false
	%CollectionFilter.select(index)
	%AvatarSearch.text = ""
	_filter_changed()


func _browse_all() -> void:
	_favorites_only = false
	%CollectionFilter.select(0)
	%AvatarSearch.text = ""
	_filter_changed()


func _browse_favorites() -> void:
	_favorites_only = true
	%CollectionFilter.select(0)
	%AvatarSearch.text = ""
	_filter_changed()


func _toggle_favorite() -> void:
	if _pending_id in PlayerProfile.avatar_favorites:
		PlayerProfile.avatar_favorites.erase(_pending_id)
	else:
		PlayerProfile.avatar_favorites.append(_pending_id)
	PlayerProfile.save()
	%FavoriteAvatar.set_pressed_no_signal(_pending_id in PlayerProfile.avatar_favorites)
	%FavoriteAvatar.icon = load("res://UI/icons/avatar/favorite_saved.svg" if _pending_id in PlayerProfile.avatar_favorites else "res://UI/icons/avatar/favorite.svg")
	if _favorites_only:
		_filter_changed()


func _make_avatar_card(entry: Dictionary) -> Button:
	var id := str(entry.id)
	var button := Button.new()
	button.name = ("Avatar" + str(entry.get("title", id)).replace(" ", "")).validate_node_name()
	button.custom_minimum_size = Vector2(138, 178)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.toggle_mode = true
	button.button_group = _selection_group
	button.set_pressed_no_signal(id == _pending_id)
	button.tooltip_text = "%s\n%s · %s" % [entry.get("title", id), entry.get("collection", "Bundled"), entry.get("license", "")]
	button.pressed.connect(sync_pending.bind(id))
	button.mouse_entered.connect(_hover_avatar.bind(id))
	button.focus_entered.connect(_hover_avatar.bind(id))
	button.mouse_exited.connect(_leave_avatar.bind(id))
	button.focus_exited.connect(_leave_avatar.bind(id))
	button.set_meta("thumbnail_url", AvatarAssets.url(id, "thumbnail"))
	_decorate_button(button)
	var content := VBoxContainer.new()
	content.name = "Card"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 16
	content.offset_right = -16
	content.offset_top = 12
	content.offset_bottom = -12
	content.add_theme_constant_override("separation", 4)
	button.add_child(content)
	var art := Control.new()
	art.custom_minimum_size.y = 108
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(art)
	var fallback := Label.new()
	fallback.name = "Fallback"
	fallback.text = "EX" if id == "default" else str(entry.get("title", "?")).left(2).to_upper()
	fallback.add_theme_font_size_override("font_size", 32)
	fallback.add_theme_color_override("font_color", Color("#74869a"))
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(fallback)
	var image := TextureRect.new()
	image.name = "Thumbnail"
	var rounded := ShaderMaterial.new()
	rounded.shader = preload("res://UI/rounded_thumbnail.gdshader")
	image.material = rounded
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(image)
	var title := Label.new()
	title.text = str(entry.get("title", id))
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", 15)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(title)
	var credits := HBoxContainer.new()
	credits.name = "Credits"
	credits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(credits)
	var artist := Label.new()
	artist.name = "Artist"
	artist.text = str(entry.get("creator", "SirRichard94 / Lyuma" if id == "godette" else ""))
	artist.tooltip_text = artist.text
	artist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	artist.clip_text = true
	artist.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	artist.add_theme_font_size_override("font_size", 11)
	artist.add_theme_color_override("font_color", Color("#74869a"))
	artist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	credits.add_child(artist)
	var badge := Label.new()
	badge.name = "Badge"
	badge.text = "Wearing"
	badge.visible = id == _applied_id
	badge.clip_text = true
	badge.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	badge.add_theme_font_size_override("font_size", 11)
	badge.add_theme_color_override("font_color", Color("#a0bdd4") if id == _applied_id else Color("#74869a"))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	credits.add_child(badge)
	return button


func _thumbnail_loaded(url: String, texture: Texture2D) -> void:
	if not visible or texture == null:
		return
	if url == AvatarAssets.url(_pending_id, "thumbnail") and not _preview_ready:
		%PreviewThumbnail.texture = texture
		%PreviewThumbnail.show()
	for button: Button in _buttons.values():
		if button.get_meta("thumbnail_url", "") == url:
			_set_card_thumbnail(button, texture)


func _set_card_thumbnail(button: Button, texture: Texture2D) -> void:
	button.get_node("Card").get_child(0).get_node("Thumbnail").texture = texture
	button.get_node("Card").get_child(0).get_node("Fallback").hide()


func _layout_browser() -> void:
	# Keep the first sidebar row, search field and preview heading on one baseline.
	var header_height := maxf(%BrowseAll.get_minimum_size().y, %AvatarSearch.get_minimum_size().y)
	%BrowseAll.custom_minimum_size.y = header_height
	%BrowseFavorites.custom_minimum_size.y = header_height
	%AvatarSearch.custom_minimum_size.y = header_height
	%SelectedTitle.get_parent().custom_minimum_size.y = header_height
	var available := _scroll.size.x - _scroll.get_v_scroll_bar().size.x
	_list.columns = clampi(int((available + 12.0) / 150.0), 2, 4)


func _style_scrollbar(scroll: ScrollContainer) -> void:
	var bar := scroll.get_v_scroll_bar()
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0)
	track.content_margin_left = 4
	track.content_margin_right = 4
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var thumb := StyleBoxFlat.new()
		thumb.bg_color = Color("#354e65" if state == "grabber" else "#74869a")
		thumb.set_corner_radius_all(4)
		thumb.content_margin_left = 4
		thumb.content_margin_right = 4
		thumb.content_margin_top = 12
		thumb.content_margin_bottom = 12
		bar.add_theme_stylebox_override(state, thumb)
	var blank := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	for icon in ["increment", "increment_highlight", "increment_pressed", "decrement", "decrement_highlight", "decrement_pressed"]:
		bar.add_theme_icon_override(icon, blank)


func _style_browser() -> void:
	_style_scrollbar(_scroll)
	_style_scrollbar($Content/Body/Sidebar/CollectionScroll)
	var list_style := StyleBoxFlat.new()
	list_style.bg_color = Color("#142237")
	var button_style := %BrowseAll.get_theme_stylebox("normal") as StyleBoxFlat
	if button_style != null:
		list_style.corner_radius_top_left = button_style.corner_radius_top_left
		list_style.corner_radius_top_right = button_style.corner_radius_top_right
		list_style.corner_radius_bottom_left = button_style.corner_radius_bottom_left
		list_style.corner_radius_bottom_right = button_style.corner_radius_bottom_right
	%ListFrame.add_theme_stylebox_override("panel", list_style)
	# Reserve room inside the field for its result count. The built-in clear
	# button is laid out before this margin, so neither text nor controls overlap.
	for state in ["normal", "focus"]:
		var style := %AvatarSearch.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		if style != null:
			style.content_margin_right = 80
			%AvatarSearch.add_theme_stylebox_override(state, style)
	# Inherit the shared room-selector theme, including panel margins/colors.
	for button: BaseButton in find_children("*", "BaseButton", true, false):
		_decorate_button(button, button == _apply or button == %CloseAvatarSettings)
	%FavoriteAvatar.icon = load("res://UI/icons/avatar/favorite_saved.svg" if _pending_id in PlayerProfile.avatar_favorites else "res://UI/icons/avatar/favorite.svg")


func _decorate_button(button: BaseButton, primary := false) -> void:
	# Copy the shared primary treatment; ordinary controls inherit their styles.
	if primary:
		var style := get_theme_stylebox("normal", "Button").duplicate() as StyleBoxFlat
		if style != null:
			style.bg_color = Color("#a0bdd4")
			button.add_theme_stylebox_override("normal", style)
		button.add_theme_color_override("font_color", Color("#162838"))


func _show_default_preview() -> void:
	if _fallback_preview == null:
		_fallback_preview = Node3D.new()
		_stage.add_child(_fallback_preview)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#a0bdd4")
		material.roughness = 0.65
		var torso := CapsuleMesh.new()
		torso.radius = 0.22
		torso.height = 1.15
		var head := SphereMesh.new()
		head.radius = 0.16
		head.height = 0.32
		for item in [[torso, Vector3(0, 0.8, 0)], [head, Vector3(0, 1.55, 0)]]:
			var mesh := MeshInstance3D.new()
			mesh.mesh = item[0]
			mesh.position = item[1]
			mesh.material_override = material
			_fallback_preview.add_child(mesh)
	_fallback_preview.show()
	_model_bounds = AABB(Vector3(-0.25, 0, -0.25), Vector3(0.5, 1.75, 0.5))
	_frame_camera()


func _hover_avatar(id: String) -> void:
	_cancel_prefetch()
	_hover_id = id
	var generation := _hover_generation
	await get_tree().create_timer(0.4).timeout
	if not is_inside_tree() or not visible or generation != _hover_generation or id == _pending_id:
		return
	_prefetch = AvatarService.acquire(id, true)


func _leave_avatar(id: String) -> void:
	if id == _hover_id:
		_cancel_prefetch()


func _cancel_prefetch() -> void:
	_hover_generation += 1
	_hover_id = ""
	if _prefetch != null:
		_prefetch.release()
		_prefetch = null


func _update_download_progress() -> void:
	var progress: Dictionary = AvatarService.download_progress(_pending_id)
	%DownloadProgress.show()
	var total := int(progress.get("total", -1))
	var downloaded := int(progress.get("downloaded", 0))
	%DownloadProgress.indeterminate = total <= 0
	if progress.get("preparing", false):
		%DownloadProgress.indeterminate = true
		_set_status("Preparing...")
	elif total > 0:
		var percent := clampf(100.0 * downloaded / total, 0, 100)
		%DownloadProgress.value = percent
		_set_status("%.1f / %.1f MB (%d%%)" % [downloaded / 1048576.0, total / 1048576.0, roundi(percent)])
	elif downloaded > 0:
		_set_status("Downloading %.1f MB" % (downloaded / 1048576.0))
	else:
		_set_status("Connecting...")
