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
const PAGE_SIZE := 18
var _page := 0
var _filtered: Array[Dictionary] = []
var _favorites_only := false
var _collection_buttons: Array[Button] = []
var _thumbnails: AvatarThumbnails
var _preview_ready := true
var _fallback_preview: Node3D

@onready var _list: GridContainer = %AvatarList
@onready var _scroll: ScrollContainer = %AvatarListScroll
@onready var _apply: Button = %Apply
@onready var _stage: Node3D = %Stage


func _ready() -> void:
	_apply.pressed.connect(_apply_pressed)
	%ResetAvatar.pressed.connect(_default_pressed)
	%SpringEnabled.toggled.connect(_spring_toggled)
	%CloseAvatarSettings.pressed.connect(close)
	%AvatarSearch.text_changed.connect(func(_text: String): _filter_changed())
	%CollectionFilter.add_item("All collections")
	for collection in AvatarCatalog.collections():
		%CollectionFilter.add_item(collection)
	%CollectionFilter.item_selected.connect(func(_index: int): _filter_changed())
	%PreviousPage.pressed.connect(_change_page.bind(-1))
	%NextPage.pressed.connect(_change_page.bind(1))
	_build_collection_navigation()
	%BrowseAll.pressed.connect(_browse_all)
	%BrowseFavorites.pressed.connect(_browse_favorites)
	%ClearFilters.pressed.connect(_clear_filters)
	%FavoriteAvatar.pressed.connect(_toggle_favorite)
	%RetryPreview.pressed.connect(func(): _show_preview(_pending_id))
	%RotateLeft.pressed.connect(_rotate_preview.bind(-1.0))
	%RotateRight.pressed.connect(_rotate_preview.bind(1.0))
	_thumbnails = AvatarThumbnails.new()
	add_child(_thumbnails)
	_thumbnails.loaded.connect(_thumbnail_loaded)
	_style_browser()
	_layout_preview_stage()
	AvatarService.selection_changed.connect(_selection_changed)
	AvatarService.springs_changed.connect(_springs_changed)
	set_open(false)


func _layout_preview_stage() -> void:
	# Mirror the lobby's world-preview frame styling and aim simple studio
	# lights; hand-written rotation matrices in the scene file are easy to get
	# wrong, so the small fixed stage is composed here instead.
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("#152c36")
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


func close() -> void:
	closed.emit()
	set_open(false)


func focus_entry() -> void:
	if _list.get_child_count() > 0:
		_list.get_child(0).grab_focus()
	else:
		%CloseAvatarSettings.grab_focus()


func _process(delta: float) -> void:
	if not visible:
		# A hidden SubViewport stops rendering; the orbit must not unwind either.
		return
	if %AutoRotate.button_pressed and (_model != null or (_fallback_preview != null and _fallback_preview.visible)):
		_stage.rotation.y = fmod(_stage.rotation.y + delta * 0.35, TAU)


func _rebuild() -> void:
	_applied_id = _safe_id(PlayerProfile.avatar_id)
	_pending_id = _applied_id
	%SpringEnabled.set_pressed_no_signal(PlayerProfile.spring_bones_enabled)
	%AvatarSearch.text = ""
	%CollectionFilter.select(0)
	_page = 0
	_favorites_only = false
	_filter_changed()
	_sync_selection(_pending_id, true)


func _filter_changed() -> void:
	var collection: String = %CollectionFilter.get_item_text(%CollectionFilter.selected) if %CollectionFilter.selected > 0 else ""
	_filtered = AvatarCatalog.search(%AvatarSearch.text, collection)
	if _favorites_only:
		_filtered = _filtered.filter(func(entry: Dictionary): return str(entry.id) in PlayerProfile.avatar_favorites)
	%GalleryTitle.text = "Favorites" if _favorites_only else collection if not collection.is_empty() else "All avatars"
	%ResultCount.text = "%s looks" % _filtered.size()
	%BrowseAll.set_pressed_no_signal(not _favorites_only and collection.is_empty())
	%BrowseFavorites.set_pressed_no_signal(_favorites_only)
	for index in _collection_buttons.size():
		_collection_buttons[index].set_pressed_no_signal(not _favorites_only and %CollectionFilter.selected == index + 1)
	_page = 0
	_refresh_list()


func _change_page(delta: int) -> void:
	_page = clampi(_page + delta, 0, maxi(0, ceili(float(_filtered.size()) / PAGE_SIZE) - 1))
	_refresh_list()


func _refresh_list() -> void:
	_thumbnails.cancel_pending()
	_scroll.scroll_vertical = 0
	for child in _list.get_children():
		child.free()
	_buttons.clear()
	for entry: Dictionary in _filtered.slice(_page * PAGE_SIZE, (_page + 1) * PAGE_SIZE):
		var id := str(entry.get("id", ""))
		if id.is_empty():
			continue
		var button := _make_avatar_card(entry)
		_list.add_child(button)
		_buttons[id] = button
		var url := str(entry.get("thumbnail_url", ""))
		var texture := _thumbnails.request(url)
		if texture != null:
			_set_card_thumbnail(button, texture)
	var pages := maxi(1, ceili(float(_filtered.size()) / PAGE_SIZE))
	%PageInfo.text = "%d / %d" % [_page + 1, pages]
	%EmptyResults.visible = _filtered.is_empty()
	%EmptyResults.text = "Your favorites will appear here.\nChoose a look and select the star to save it." if _favorites_only else "No matching avatars.\nTry another collection or clear your search."
	_scroll.visible = not _filtered.is_empty()
	%PreviousPage.disabled = _page == 0
	%NextPage.disabled = _page + 1 >= pages
	# Late-built list buttons follow the same VR press/debounce rules as the rest.
	var owner_ui := get_parent()
	if owner_ui != null and owner_ui.has_method("_configure_buttons"):
		owner_ui.call("_configure_buttons", _list)


func sync_pending(id: String) -> void:
	if id == _pending_id or not AvatarCatalog.has_avatar(id):
		return
	_pending_id = id
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
	_apply.text = "Wearing" if _pending_id == _applied_id else "Wear avatar" if _preview_ready else "Loading…"
	%WearingLabel.text = "Wearing %s" % _title_for(_applied_id)


func _sync_selection(id: String, with_preview: bool) -> void:
	for entry_id in _buttons:
		(_buttons[entry_id] as Button).set_pressed_no_signal(entry_id == id)
		var badge: Label = _buttons[entry_id].get_node("Card/Badge")
		badge.text = "Wearing" if entry_id == _applied_id else str(AvatarCatalog.definition(entry_id).get("collection", "Bundled"))
	var entry := AvatarCatalog.definition(id)
	if entry.is_empty():
		_apply.disabled = true
		_set_status("This avatar is no longer in the catalog.", true)
		return
	_update_apply()
	%SelectedTitle.text = str(entry.get("title", id))
	%SelectedCollection.text = str(entry.get("collection", "Bundled"))
	%FavoriteAvatar.set_pressed_no_signal(id in PlayerProfile.avatar_favorites)
	%FavoriteAvatar.text = "★" if id in PlayerProfile.avatar_favorites else "☆"
	var license := str(entry.get("license", ""))
	var attribution := str(entry.get("attribution", ""))
	if license.is_empty():
		%Attribution.text = str(entry.get("title", id))
	elif attribution.is_empty():
		%Attribution.text = "%s · %s" % [entry.get("title", id), license]
	else:
		%Attribution.text = "%s · %s\n%s" % [entry.get("title", id), license, attribution]
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
	%RetryPreview.hide()
	_update_apply()
	if AvatarCatalog.definition(id).is_empty():
		_set_status("This avatar is no longer in the catalog.", true)
		return
	var request := AvatarService.acquire(id)
	_request = request
	if request.finished:
		# The lease can complete instantly (cached or bundled): no await needed.
		_process_result(request, id, generation)
		return
	_set_status("Loading %s…" % _title_for(id))
	await request.completed
	if generation != _generation:
		return
	_process_result(request, id, generation)


func _process_result(request: AvatarLoadRequest, _id: String, generation: int) -> void:
	if generation != _generation or request.released:
		# A stale or released lease must not touch the current preview.
		return
	var error := request.error
	var scene := request.scene
	_release_request()
	if not error.is_empty():
		_set_status(error, true)
		%RetryPreview.show()
		_apply.text = "Preview unavailable"
		return
	if scene == null:
		# The bundled default has no model: rooms render a simple fallback body.
		_show_default_preview()
		_preview_ready = true
		_update_apply()
		_set_status("A simple, lightweight Explorer.", false, true)
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
	%SpringEnabled.set_pressed_no_signal(enabled)
	_update_simulators()


func _spring_toggled(_enabled: bool) -> void:
	AvatarService.set_springs_enabled(%SpringEnabled.button_pressed)


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


func _default_pressed() -> void:
	# Reset applies immediately; "default" is always in the catalog.
	AvatarService.select_avatar(DEFAULT_ID)


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


func _clear_filters() -> void:
	_browse_all()


func _toggle_favorite() -> void:
	if _pending_id in PlayerProfile.avatar_favorites:
		PlayerProfile.avatar_favorites.erase(_pending_id)
	else:
		PlayerProfile.avatar_favorites.append(_pending_id)
	PlayerProfile.save()
	%FavoriteAvatar.set_pressed_no_signal(_pending_id in PlayerProfile.avatar_favorites)
	%FavoriteAvatar.text = "★" if _pending_id in PlayerProfile.avatar_favorites else "☆"
	if _favorites_only:
		_filter_changed()


func _rotate_preview(direction: float) -> void:
	%AutoRotate.set_pressed_no_signal(false)
	_stage.rotation.y += direction * PI / 6.0


func _make_avatar_card(entry: Dictionary) -> Button:
	var id := str(entry.id)
	var button := Button.new()
	button.name = ("Avatar" + str(entry.get("title", id)).replace(" ", "")).validate_node_name()
	button.custom_minimum_size = Vector2(138, 170)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.toggle_mode = true
	button.button_group = _selection_group
	button.set_pressed_no_signal(id == _pending_id)
	button.tooltip_text = "%s\n%s · %s" % [entry.get("title", id), entry.get("collection", "Bundled"), entry.get("license", "")]
	button.pressed.connect(sync_pending.bind(id))
	button.set_meta("thumbnail_url", str(entry.get("thumbnail_url", "")))
	_decorate_button(button)
	var content := VBoxContainer.new()
	content.name = "Card"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 10
	content.offset_right = -10
	content.offset_top = 10
	content.offset_bottom = -10
	content.add_theme_constant_override("separation", 4)
	button.add_child(content)
	var art := Control.new()
	art.custom_minimum_size.y = 108
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(art)
	var fallback := Label.new()
	fallback.name = "Fallback"
	fallback.text = "◉" if id == "default" else str(entry.get("title", "?")).left(2).to_upper()
	fallback.add_theme_font_size_override("font_size", 32)
	fallback.add_theme_color_override("font_color", Color("#668d98"))
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(fallback)
	var image := TextureRect.new()
	image.name = "Thumbnail"
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
	var badge := Label.new()
	badge.name = "Badge"
	badge.text = "Wearing" if id == _applied_id else str(entry.get("collection", "Bundled"))
	badge.clip_text = true
	badge.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	badge.add_theme_font_size_override("font_size", 11)
	badge.add_theme_color_override("font_color", Color("#7ed5c9") if id == _applied_id else Color("#8299ad"))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(badge)
	return button


func _thumbnail_loaded(url: String, texture: Texture2D) -> void:
	if not visible or texture == null:
		return
	for button: Button in _buttons.values():
		if button.get_meta("thumbnail_url", "") == url:
			_set_card_thumbnail(button, texture)


func _set_card_thumbnail(button: Button, texture: Texture2D) -> void:
	button.get_node("Card").get_child(0).get_node("Thumbnail").texture = texture
	button.get_node("Card").get_child(0).get_node("Fallback").hide()


func _style_browser() -> void:
	var panel := _box(Color("#101d2d"), Color("#2a4054"), 18)
	panel.content_margin_left = 24
	panel.content_margin_right = 24
	panel.content_margin_top = 20
	panel.content_margin_bottom = 20
	panel.shadow_color = Color(0, 0, 0, 0.35)
	panel.shadow_size = 24
	add_theme_stylebox_override("panel", panel)
	add_theme_color_override("font_color", Color("#e5edf4"))
	for button: BaseButton in find_children("*", "BaseButton", true, false):
		_decorate_button(button, button == _apply)
	var search := %AvatarSearch as LineEdit
	search.add_theme_stylebox_override("normal", _box(Color("#17283a"), Color("#30445a")))
	search.add_theme_stylebox_override("focus", _box(Color("#17283a"), Color("#79d3c9")))
	search.add_theme_font_size_override("font_size", 15)


func _decorate_button(button: BaseButton, primary := false) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var color := Color("#192c3e")
		var border := Color("#2a4054")
		if state in ["hover", "pressed", "hover_pressed"]:
			color = Color("#24414d")
			border = Color("#7ed5c9") if state != "hover" else Color("#4e7984")
		if primary and state != "disabled":
			color = Color("#80d8ca") if state == "normal" else Color("#a1ebdd")
			border = color
		if state == "disabled":
			color = Color("#152635")
		if state == "focus":
			color = Color.TRANSPARENT
			border = Color("#a1ebdd")
		var style := _box(color, border)
		if state == "focus":
			style.set_border_width_all(2)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", Color("#112e32") if primary else Color("#e2edf4"))
	button.add_theme_color_override("font_hover_color", Color("#112e32") if primary else Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color("#112e32") if primary else Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color("#8ba8b7"))
	button.add_theme_font_size_override("font_size", 15)


func _box(color: Color, border: Color, radius := 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _show_default_preview() -> void:
	if _fallback_preview == null:
		_fallback_preview = Node3D.new()
		_stage.add_child(_fallback_preview)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#80c6c4")
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
