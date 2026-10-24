extends Node
## Avatar picker submenu checks. Runs fully offline: only the bundled Godette
## sample (bundled_path) and the "default" placeholder are exercised; the three
## pinned remote catalog entries are never selected, so no downloads start.

var failed := false


func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func _ready() -> void:
	_run.call_deferred()


func _wait_until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 20000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return condition.call()


func _run() -> void:
	var profile_existed := FileAccess.file_exists("user://profile.cfg")
	var profile_backup := FileAccess.get_file_as_bytes("user://profile.cfg") if profile_existed else PackedByteArray()
	Networking.set_process(false)
	Networking.ws.close(-1)
	Networking.room_networking.reset()
	Networking.connection_message = "Server offline · Retrying automatically"

	# Profile persistence and validation run before any UI restores the file.
	PlayerProfile.avatar_id = "godette"
	PlayerProfile.spring_bones_enabled = false
	check(PlayerProfile.save() == OK, "Avatar preferences did not persist")
	PlayerProfile.avatar_id = "Explorer"
	PlayerProfile.spring_bones_enabled = true
	PlayerProfile.restore()
	check(PlayerProfile.avatar_id == "godette" and not PlayerProfile.spring_bones_enabled, "Saved avatar selection or spring preference was lost")
	PlayerProfile.avatar_id = "the-long-forgotten-avatar"
	PlayerProfile.save()
	PlayerProfile.restore()
	check(PlayerProfile.avatar_id == "default", "A no-longer-catalogued avatar ID did not fall back to default")

	var game = load("res://Main.tscn").instantiate()
	add_child(game)
	var ui = game.get_node("roomSelector")
	var card = ui.get_node("%AvatarSettings")
	card._thumbnails.enabled = false
	check(ui.get_node("%OpenAvatarPicker").text == "Avatar settings" and ui.get_node("%OpenSessionAvatarPicker").text == "Avatar settings", "Avatar submenu entry buttons are missing from the home and session menus")
	check(PlayerProfile.avatar_id == "default", "Main scene did not restore the profile avatar")

	# Keep the offline lobby so submenu state changes are only our own doing.
	Networking.signaling_connected.emit()
	ui._select_world("moon_garden")

	# Voice and avatar submenus are mutually exclusive, like two voice cards.
	ui.get_node("%OpenVoiceSettings").pressed.emit()
	check(ui.get_node("%VoiceSettings").visible, "Voice settings submenu did not open")
	ui.get_node("%OpenAvatarPicker").pressed.emit()
	check(card.visible and not ui.get_node("%VoiceSettings").visible and not ui.get_node("VBoxContainer").visible, "Avatar submenu did not replace the voice/main cards")
	var entries := AvatarCatalog.entries()
	check(card.get_node("%AvatarList").get_child_count() == mini(entries.size(), card.BATCH_SIZE), "Avatar browser must initially create only one batch")
	var default_button: Button = card.get_node("%AvatarList/AvatarExplorer")
	check(default_button.get_node("Card").get_child(0).get_node("Thumbnail").material is ShaderMaterial, "Card thumbnails must round their image corners")
	check(default_button.button_pressed and card._applied_id == "default", "Current avatar is not highlighted in the list")
	check(card.get_node("%Attribution").text.contains("Bundled"), "Attribution for the default avatar is missing")
	check(card.get_node("%Apply").disabled, "Apply is enabled without a pending change")
	check(ui.get_viewport().gui_get_focus_owner() == card.get_node("%AvatarList/AvatarExplorer"), "Opening the submenu did not focus the list")

	# Scroll near the end to append a batch without pagination or model loads.
	check(card.get_node_or_null("%NextPage") == null, "Pagination buttons must be removed")
	await get_tree().process_frame
	await get_tree().process_frame
	# Real wheel events must reach the scroll container through an avatar card.
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = card.get_node("%AvatarList").get_child(0).get_global_rect().get_center()
	wheel.global_position = wheel.position
	ui.get_viewport().push_input(wheel, true)
	await get_tree().process_frame
	check(card.get_node("%AvatarListScroll").scroll_vertical > 0, "Wheel scrolling over an avatar card must move the gallery")
	var gallery_scroll: ScrollContainer = card.get_node("%AvatarListScroll")
	gallery_scroll.scroll_vertical = 0
	var gallery_point: Vector2 = gallery_scroll.get_global_rect().get_center()
	ui.get_node("Navigation").handle_stick(Vector2(0, -1), gallery_point, 0.2)
	check(gallery_scroll.scroll_vertical > 0, "Controller stick must scroll the open avatar gallery")
	var previous_scroll := gallery_scroll.scroll_vertical
	ui.get_node("Navigation").handle_stick(Vector2(0, -1), card.get_node("%PreviewFrame").get_global_rect().get_center(), 0.2)
	check(gallery_scroll.scroll_vertical == previous_scroll, "Pointing at the preview must not scroll the gallery")
	# Finger swipes scroll without activating cards; taps activate on release.
	gallery_scroll.scroll_vertical = 0
	await get_tree().process_frame
	await get_tree().process_frame
	var taps := [0]
	default_button.pressed.connect(func(): taps[0] += 1)
	var touch := InputEventScreenTouch.new()
	touch.index = 43
	touch.position = default_button.get_global_rect().get_center()
	touch.pressed = true
	ui.get_viewport().push_input(touch, true)
	var drag := InputEventScreenDrag.new()
	drag.index = touch.index
	drag.position = touch.position - Vector2(0, 110)
	ui.get_viewport().push_input(drag, true)
	touch.position = drag.position
	touch.pressed = false
	ui.get_viewport().push_input(touch, true)
	await get_tree().process_frame
	check(gallery_scroll.scroll_vertical > 0 and taps[0] == 0 and card._pending_id == "default", "Touch swipes must scroll without selecting an avatar")
	gallery_scroll.scroll_vertical = 0
	await get_tree().process_frame
	await get_tree().process_frame
	touch.position = default_button.get_global_rect().get_center()
	touch.pressed = true
	ui.get_viewport().push_input(touch, true)
	touch.pressed = false
	ui.get_viewport().push_input(touch, true)
	await get_tree().process_frame
	check(taps[0] == 1, "A stationary touch must activate its card exactly once on release")
	touch.pressed = true
	ui.get_viewport().push_input(touch, true)
	touch.pressed = false
	touch.canceled = true
	ui.get_viewport().push_input(touch, true)
	await get_tree().process_frame
	check(taps[0] == 1 and not ui.get_node("Navigation")._dragging, "Canceled touches must clear the gesture without activating a card")
	var collection_scroll: ScrollContainer = card.get_node("Content/Body/Sidebar/CollectionScroll")
	var collection_button: Button = card.get_node("%Collections").get_child(0)
	var collection_minimum := collection_button.custom_minimum_size
	collection_button.custom_minimum_size.y += 500
	await get_tree().process_frame
	await get_tree().process_frame
	touch.canceled = false
	touch.pressed = true
	touch.position = collection_scroll.get_global_rect().get_center()
	ui.get_viewport().push_input(touch, true)
	drag.position = touch.position - Vector2(0, 80)
	ui.get_viewport().push_input(drag, true)
	touch.position = drag.position
	touch.pressed = false
	ui.get_viewport().push_input(touch, true)
	check(collection_scroll.scroll_vertical > 0, "Touch dragging must also scroll the collections list")
	collection_button.custom_minimum_size = collection_minimum
	collection_scroll.scroll_vertical = 0
	await get_tree().process_frame
	await get_tree().process_frame
	# XR touch/controller drags share the swipe path without leaking a click.
	var navigation = ui.get_node("Navigation")
	var pointer := Node3D.new()
	gallery_scroll.scroll_vertical = 0
	var pointer_point := gallery_scroll.get_global_rect().get_center()
	var pointer_event := XRToolsPointerEvent.new(XRToolsPointerEvent.Type.PRESSED, pointer, null, Vector3.ZERO, Vector3.ZERO)
	check(navigation.pointer_event(pointer_event, pointer_point), "Avatar gallery must consume XR touch presses")
	pointer_event.event_type = XRToolsPointerEvent.Type.MOVED
	navigation.pointer_event(pointer_event, pointer_point - Vector2(0, 100))
	pointer_event.event_type = XRToolsPointerEvent.Type.RELEASED
	navigation.pointer_event(pointer_event, pointer_point - Vector2(0, 100))
	await get_tree().process_frame
	check(gallery_scroll.scroll_vertical > 0 and taps[0] == 1, "XR touch dragging must scroll without activating cards")
	# Optical pokes confirm before withdrawal, with feedback at first contact.
	gallery_scroll.scroll_vertical = 0
	await get_tree().process_frame
	await get_tree().process_frame
	var poke_point := default_button.get_global_rect().get_center()
	pointer.set_meta("ui_poke_depth", 0.005)
	pointer_event.event_type = XRToolsPointerEvent.Type.PRESSED
	navigation.pointer_event(pointer_event, poke_point)
	check(default_button.has_focus(), "Touch-down must immediately highlight the original card")
	pointer.set_meta("ui_poke_depth", -0.002)
	pointer_event.event_type = XRToolsPointerEvent.Type.MOVED
	navigation.pointer_event(pointer_event, poke_point + Vector2(0, 6))
	await get_tree().process_frame
	check(taps[0] == 2 and navigation._dragging, "A forward optical poke must select before finger withdrawal")
	pointer_event.event_type = XRToolsPointerEvent.Type.RELEASED
	navigation.pointer_event(pointer_event, poke_point)
	await get_tree().process_frame
	check(taps[0] == 2, "Poke release must not activate the card twice")
	pointer.remove_meta("ui_poke_depth")
	# A small tremor remains a tap rather than becoming a canceled swipe.
	touch.canceled = false
	touch.pressed = true
	touch.position = poke_point
	ui.get_viewport().push_input(touch, true)
	drag.position = poke_point + Vector2(0, 14)
	ui.get_viewport().push_input(drag, true)
	touch.pressed = false
	touch.position = drag.position
	ui.get_viewport().push_input(touch, true)
	await get_tree().process_frame
	check(taps[0] == 3, "Small touch tremor must not cancel selection")
	# Releasing across a narrow card gap must not retarget the gesture.
	var neighbor: Button = card.get_node("%AvatarList").get_child(1)
	var neighbor_taps := [0]
	neighbor.pressed.connect(func(): neighbor_taps[0] += 1)
	var press_edge := Vector2(default_button.get_global_rect().end.x - 1, default_button.get_global_rect().get_center().y)
	var release_edge := Vector2(neighbor.get_global_rect().position.x + 1, press_edge.y)
	touch.pressed = true
	touch.position = press_edge
	ui.get_viewport().push_input(touch, true)
	drag.position = release_edge
	ui.get_viewport().push_input(drag, true)
	touch.pressed = false
	touch.position = release_edge
	ui.get_viewport().push_input(touch, true)
	await get_tree().process_frame
	check(neighbor_taps[0] == 0 and taps[0] == 3, "A touch must remain pinned to its original card rather than selecting its neighbor")
	pointer.free()
	var initial_count: int = card._loaded_count
	var scrollbar: VScrollBar = card.get_node("%AvatarListScroll").get_v_scroll_bar()
	scrollbar.value = scrollbar.max_value
	check(await _wait_until(func(): return card._loaded_count > initial_count), "Scrolling must append more avatars")
	check(card._loaded_count < entries.size(), "Lazy scrolling must not build the whole catalog")
	card.get_node("%AvatarSearch").text = "Godette"
	card._filter_changed()
	check(card._loaded_count == 1 and card.get_node("%AvatarList").get_child_count() == 1, "Search must reset lazy results and filter the catalog")
	check(card._request == null, "Filtering must not download avatars")
	card.get_node("%AvatarSearch").text = ""
	var filter: OptionButton = card.get_node("%CollectionFilter")
	for index in filter.item_count:
		if filter.get_item_text(index) == "100Avatars R3":
			filter.select(index)
	card._filter_changed()
	check(card._filtered.size() == 100, "Collection filter did not include all R3 avatars")
	check(card.get_node("%AvatarSearch").placeholder_text == "Search in 100Avatars R3" and card.get_node("%ResultCount").text == "100", "Search scope and count must track collection changes")
	filter.select(0)
	card._filter_changed()

	check(card.get_node_or_null("%ResetAvatar") == null and card.get_node_or_null("%AutoRotate") == null, "Redundant Explorer/turntable buttons must be removed")
	check(card.get_node("%FavoriteAvatar").icon != null, "Icons must use bundled SVGs rather than system-font glyphs")
	var panel_style := card.get_theme_stylebox("panel", "PanelContainer") as StyleBoxFlat
	check(panel_style.bg_color == Color("#142237") and panel_style.content_margin_left == 16 and panel_style.content_margin_top == 12, "Wardrobe must inherit the shared theme colors and margins")

	var queued := AvatarThumbnails.new()
	queued._jobs["one"] = AvatarThumbnailJob.new()
	queued._jobs["two"] = AvatarThumbnailJob.new()
	queued.request("https://example.invalid/first.png")
	queued.request("https://example.invalid/clicked.png")
	queued.prioritize("https://example.invalid/clicked.png")
	check(queued._queue.front() == "https://example.invalid/clicked.png", "A clicked thumbnail must jump ahead of gallery preloads")
	queued.free()

	# Selecting the bundled Godette loads it without any network use.
	card.get_node("%AvatarList/AvatarGodette").pressed.emit()
	var model_placed := func(): return card._model != null and is_instance_valid(card._model)
	if not await _wait_until(model_placed):
		failed = true
		push_error("Bundled Godette did not appear in the preview (status: %s)" % card.get_node("%PreviewStatus").text)
	if card._model != null:
		check(card._model.scale.is_equal_approx(Vector3.ONE), "Preview scaled the model node; the loader normalizes avatars instead")
		var relative: Transform3D = card.get_node("%Camera").get_transform().inverse() * card._model.global_transform
		var projection := relative * AABB(Vector3.ZERO, Vector3.ONE)
		check(absf(projection.position.z) > 0.05, "Preview camera was not pulled away from the avatar")
	check(card.get_node("%Attribution").text == "CC-BY-3.0" and card.get_node("%AvatarList/AvatarGodette/Card/Credits/Artist").text.contains("SirRichard94"), "Godette attribution and license are missing")
	check(not card.get_node("%Apply").disabled, "Selecting a different avatar did not enable Apply")
	card.get_node("%Apply").pressed.emit()
	check(PlayerProfile.avatar_id == "godette", "Apply did not change the profile avatar")
	check(card.get_node("%Apply").disabled and card.get_node("%AvatarList/AvatarGodette").button_pressed, "Apply did not mark the selection as current")
	check(PlayerProfile.spring_bones_enabled == false, "Spring preference from the current profile was changed spuriously")

	# Saved looks, turntable controls, and category navigation work without model downloads.
	PlayerProfile.avatar_favorites.clear()
	card.get_node("%FavoriteAvatar").pressed.emit()
	check("godette" in PlayerProfile.avatar_favorites, "Saving a favorite failed")
	PlayerProfile.restore()
	check("godette" in PlayerProfile.avatar_favorites, "Favorite did not persist across profile restore")
	card.get_node("%BrowseFavorites").pressed.emit()
	check(card._filtered.size() == 1 and card._filtered[0].id == "godette", "Favorites library must show saved looks")
	card.get_node("%FavoriteAvatar").pressed.emit()
	check(card._filtered.is_empty() and card.get_node("%EmptyResults").visible, "Empty favorites needs a clear empty state")
	card.get_node("%BrowseAll").pressed.emit()
	check(card._filtered.size() == entries.size(), "All avatars did not restore the library")
	check(card.get_node_or_null("%RotateLeft") == null and card.get_node_or_null("%SpringEnabled") == null and card.get_node_or_null("Content/Header") == null, "Removed layout controls must not remain")
	check(card.get_node("%CloseAvatarSettings").get_parent() == card.get_node("Content/Body/Sidebar"), "Done must share the bottom action row in the sidebar")
	check(card.get_node_or_null("%GalleryTitle") == null and card.get_node("%ResultCount").get_parent() == card.get_node("%AvatarSearch"), "Search and result count must replace the separate header")
	check(card.get_node("%AvatarSearch").placeholder_text == "Search all" and card.get_node("%ResultCount").horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT, "Unified search field must identify the collection and right-align results")
	check(card.get_node_or_null("Content/Body/Sidebar/LibraryLabel") == null, "Redundant Library label must be removed")
	check(card.get_node("%Attribution").get_parent() == card.get_node("%PreviewFrame"), "License must sit directly inside the preview")
	check(card.get_node("%Attribution").anchor_right == 1.0 and card.get_node("%Attribution").anchor_bottom == 1.0 and card.get_node("%Attribution").horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT, "License must anchor at the lower right with right-aligned text")
	check(card.get_node_or_null("%ArtistName") == null and card.get_node_or_null("%SelectedCollection") == null and card.get_node_or_null("%LicenseHolder") == null, "Viewer must omit artist, collection, and license panel")
	var gallery_style: StyleBoxFlat = card.get_node("%ListFrame").get_theme_stylebox("panel")
	var button_style: StyleBoxFlat = card.get_node("%BrowseAll").get_theme_stylebox("normal")
	check(gallery_style.corner_radius_top_left == button_style.corner_radius_top_left and gallery_style.corner_radius_top_right == button_style.corner_radius_top_right and gallery_style.corner_radius_bottom_left == button_style.corner_radius_bottom_left and gallery_style.corner_radius_bottom_right == button_style.corner_radius_bottom_right, "All gallery corners must match button corners")
	check(card.get_node("%ListFrame").clip_children == CanvasItem.CLIP_CHILDREN_AND_DRAW, "Gallery must clip scrolled cards to its rounded frame")
	check(is_equal_approx(card.get_node("%Apply").get_global_rect().end.y, card.get_node("%CloseAvatarSettings").get_global_rect().end.y), "All action buttons must sit at the panel bottom")
	check(card.get_node("%CloseAvatarSettings").icon != null, "Done must have a distinct completion icon")
	check(card.get_node_or_null("Content/Footer") == null and card.find_children("*", "HSeparator", true, false).is_empty(), "Extra bottom space and divider lines must be removed")
	check(card.get_node("%AvatarList").columns >= 3, "Wardrobe must use horizontal space for a multi-column gallery")
	check(is_equal_approx(card.get_node("%BrowseAll").get_global_rect().position.y, card.get_node("%AvatarSearch").get_global_rect().position.y), "Search and All avatars must align")
	check(is_equal_approx(card.get_node("%BrowseFavorites").get_global_rect().position.y, card.get_node("%ListFrame").get_global_rect().position.y), "Favorites and gallery must align")
	check(is_equal_approx(card.get_node("%BrowseFavorites").get_global_rect().position.y, card.get_node("%AvatarList").get_child(0).get_global_rect().position.y), "The first avatar card must align with Favorites")
	check(is_equal_approx(card.get_node("%AvatarSearch").get_global_rect().position.x, card.get_node("%AvatarList").get_child(0).get_global_rect().position.x), "The first avatar card must align with the search field's left edge")

	check(card.get_node("%AvatarScrollbar").get_theme_stylebox("grabber").corner_radius_top_left == 4, "Scrollbar must use a rounded thumb")
	# Exercise responsive breakpoints without changing the enclosing menu size.
	var scroll: ScrollContainer = card.get_node("%AvatarListScroll")
	var original_scroll_size := scroll.size
	scroll.size.x = 660
	card._layout_browser()
	check(card.get_node("%AvatarList").columns == 4, "Wide galleries must fit four cards")
	scroll.size = original_scroll_size
	card._layout_browser()
	await get_tree().process_frame
	await get_tree().process_frame
	var outer_margins: Vector2 = Vector2(32, 24) * ui.get_node("VBoxContainer").scale
	check(card.get_global_rect().position.is_equal_approx(outer_margins), "Wardrobe outer margins must match the lobby")
	check((ui.get_viewport_rect().size - card.get_global_rect().end).is_equal_approx(outer_margins), "Opposite outer margins must match")
	var frame_rect: Rect2 = card.get_node("%PreviewFrame").get_global_rect()
	check(frame_rect.end.x <= card.get_global_rect().end.x, "Preview extends beyond the wardrobe")
	check(card.get_node("Content/Body/Sidebar").get_global_rect().end.x < card.get_node("Content/Body/Gallery").get_global_rect().position.x, "Sidebar and gallery overlap")
	check(card.get_node("Content/Body/Gallery").get_global_rect().end.x < frame_rect.position.x, "Gallery and preview overlap")

	# Reset returns to the bundled placeholder immediately.
	for index in card.get_node("%CollectionFilter").item_count:
		if card.get_node("%CollectionFilter").get_item_text(index) == "Bundled":
			card._choose_collection(index)
	card.get_node("%AvatarList/AvatarExplorer").pressed.emit()
	card.get_node("%Apply").pressed.emit()
	check(PlayerProfile.avatar_id == "default" and card.get_node("%Apply").disabled, "Default reset did not apply the bundled avatar")
	check(not card.get_node("%PreviewStatus").visible and card._fallback_preview.visible, "Explorer should show a preview without extra hint text")
	check(await _wait_until(func(): return card._model == null), "Default avatar preview kept the loaded model")

	# Loading overlays must not resize the viewer, and retry shares the Wear action.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var stable_preview_rect: Rect2 = card.get_node("%PreviewFrame").get_global_rect()
	card.get_node("%DownloadProgress").show()
	card._set_status("Downloading 1.0 / 2.0 MB (50%)")
	await get_tree().process_frame
	await get_tree().process_frame
	check(card.get_node("%PreviewFrame").get_global_rect().is_equal_approx(stable_preview_rect), "Loading feedback must not move or resize the viewer")
	check(card.get_node("%DownloadProgress").get_parent() == card.get_node("%PreviewFrame") and card.get_node("%PreviewStatus").get_parent() == card.get_node("%PreviewFrame"), "Loading feedback must overlay the preview")
	check(card.get_node("%PreviewFrame").clip_children == CanvasItem.CLIP_CHILDREN_AND_DRAW, "Preview must clip progress and images at its rounded corners")
	check(card.get_node_or_null("%RetryPreview") == null, "Retry must not have its own button")
	card._preview_ready = false
	card._set_status("Preview download failed", true)
	check(card.get_node("%Apply").text == "Retry preview" and not card.get_node("%Apply").disabled, "Failed previews must turn Wear into an enabled retry action")
	card.get_node("%Apply").pressed.emit()
	check(card._preview_ready and not card._preview_failed and card.get_node("%Apply").text == "Wearing", "Retry must reload the selected preview and restore Wear state")
	var done: Button = card.get_node("%CloseAvatarSettings")
	check(done.get_theme_color("icon_normal_color") == done.get_theme_color("font_color") and done.get_theme_color("icon_hover_color") == done.get_theme_color("font_hover_color"), "Done icon colors must follow its text colors")
	check(card.get_node("%GalleryTrack").get_theme_constant("separation") == 12, "Cards must have a separate gap before the scrollbar")
	check(card.get_node("%AvatarScrollbar").get_global_rect().position.x - card.get_node("%ListFrame").get_global_rect().end.x >= 12 * card.get_global_transform().get_scale().x - 0.01, "Scrollbar must sit outside the rounded card area")
	var native_bar: VScrollBar = card.get_node("%AvatarListScroll").get_v_scroll_bar()
	var outside_bar: VScrollBar = card.get_node("%AvatarScrollbar")
	var previous_value := native_bar.value
	outside_bar.value = outside_bar.max_value
	check(is_equal_approx(native_bar.value, outside_bar.value), "Outside scrollbar must drive the card scroll position")
	native_bar.value = previous_value

	# Dwell prefetch is shared/cancellable and does not replace the preview.
	card._hover_avatar("godette")
	await get_tree().create_timer(0.45).timeout
	check(card._prefetch != null and card._prefetch.finished and card._prefetch.scene == null, "Hover should warm bytes without creating another preview scene")
	check(card._pending_id == "default", "Hover must not change the selected avatar")
	card._leave_avatar("godette")
	check(card._prefetch == null, "Leaving a card must release its speculative request")

	# Closing restores the menu and the focus that opened the submenu.
	card.get_node("%CloseAvatarSettings").pressed.emit()
	check(not card.visible and ui.get_node("VBoxContainer").visible, "Done did not return to the lobby menu")
	check(ui.get_viewport().gui_get_focus_owner() == ui.get_node("%OpenAvatarPicker"), "Closing the submenu did not restore entry-button focus")
	check(card._request == null and card._model == null, "Closing the submenu left a preview lease or model alive")

	# A closed panel must stop releasing work into the service's lease book.
	ui.get_node("%OpenAvatarPicker").pressed.emit()
	card.get_node("%AvatarList/AvatarGodette").pressed.emit()
	if await _wait_until(model_placed):
		card.get_node("%AvatarList/AvatarExplorer").pressed.emit()
		await get_tree().process_frame
		card.get_node("%CloseAvatarSettings").pressed.emit()
		check(card._request == null, "Switching avatars left the previous acquire alive")
	ui.get_node("%OpenAvatarPicker").pressed.emit()
	check(await _wait_until(func(): return card.get_node("%AvatarList/AvatarGodette").is_visible_in_tree() and card._model == null), "Reopening the card did not restart the preview for the default avatar")

	# Springs remain a viewing preference without a redundant menu toggle.
	AvatarService.set_springs_enabled(true)
	check(PlayerProfile.spring_bones_enabled, "Spring preference must remain available to the service")

	# In-room sessions reach the same submenu from the Session menu.
	var state: RoomNetworking = Networking.room_networking
	state.current_room = roomClass.new(31, "Avatar room", 1)
	ui.set_menu_open(true)
	check(ui.get_node("Session").visible and ui.get_node("%OpenSessionAvatarPicker").is_visible_in_tree(), "In-room menu does not expose the avatar submenu")
	ui.get_node("%OpenSessionAvatarPicker").pressed.emit()
	check(card.visible and not ui.get_node("Session").visible, "In-room avatar submenu did not replace the session card")
	card.get_node("%CloseAvatarSettings").pressed.emit()
	check(not card.visible and ui.get_node("Session").visible, "In-room Done did not restore the session card")
	check(ui.get_viewport().gui_get_focus_owner() == ui.get_node("%OpenSessionAvatarPicker"), "In-room close did not restore entry-button focus")

	# Escape closes the submenu first, before anything else reacts.
	ui.get_node("%OpenSessionAvatarPicker").pressed.emit()
	ui._input(_key(KEY_ESCAPE))
	check(not card.visible and ui.get_node("Session").visible, "Escape did not close the avatar submenu")
	ui._input(_key(KEY_ESCAPE))
	check(not ui.menu_open, "Escape with a closed submenu did not close the room menu")
	ui.set_menu_open(true)

	# The shared card scales in the VR panel for controller or hand pointers.
	var panel = load("res://UI/vr_panel.tscn").instantiate()
	game.add_child(panel)
	ui.reparent(panel.get_node("Viewport"))
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.vr_mode = true
	ui.get_node("%OpenSessionAvatarPicker").pressed.emit()
	var apply_point: Vector2 = ui.get_node("%AvatarSettings").get_global_rect().get_center()
	check(ui.xr_point_is_visible(apply_point), "Open avatar submenu is not touchable in the VR panel")
	await get_tree().process_frame
	await get_tree().process_frame
	var vr_rect: Rect2 = card.get_global_rect()
	check(vr_rect.position.x >= 0 and vr_rect.end.x <= 1120 and vr_rect.position.y >= 0 and vr_rect.end.y <= 800, "Wide wardrobe must fit the headset panel")
	ui.vr_mode = false
	ui.reparent(game)
	panel.queue_free()

	state.current_room = null
	ui.set_menu_open(true)
	game.free()
	await get_tree().create_timer(0.08).timeout
	Networking.set_process(false)
	Networking.ws.close(-1)
	if profile_existed:
		FileAccess.open("user://profile.cfg", FileAccess.WRITE).store_buffer(profile_backup)
	else:
		DirAccess.remove_absolute("user://profile.cfg")
	print("Avatar picker tests: ", "FAIL" if failed else "PASS")
	get_tree().quit(1 if failed else 0)


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event
