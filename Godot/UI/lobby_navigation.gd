class_name LobbyNavigation
extends Node

const DRAG_THRESHOLD := 20.0
const TAP_RELEASE_TOLERANCE := 4.0
const POKE_CONFIRM_DEPTH := -0.001
const SWIPE_THRESHOLD := 40.0
const STICK_DEADZONE := 0.25
const SCROLL_SPEED := 600.0

enum Region { NONE, ROOMS, WORLDS, AVATARS, COLLECTIONS }

@onready var ui: Control = get_parent()
@onready var rooms: ScrollContainer = ui.get_node("%Scroll")
@onready var world: Control = ui.get_node("%WorldPreviewFrame")

var _dragging := false
var _touch_index := -1
var _region := Region.NONE
var _start := Vector2.ZERO
var _drag_pointer: Node3D
var _start_scroll := 0
var _dragged := false
var _start_button: Button
var _button_focus_style: StyleBox
var _poke_committed := false
var _press_feedback_active := false
var _stick_direction := 0
var _stick_repeat := 0.0
var _scroll_fraction := 0.0


func _ready() -> void:
	world.gui_input.connect(_world_gui_input)


func _process(_delta: float) -> void:
	var target := _scroll_for_region(_region)
	if not _active() or (target != null and not target.is_visible_in_tree()) or (_drag_pointer is XRToolsFunctionPointer and not _drag_pointer.enabled):
		_cancel_drag()


func _active() -> bool:
	return ui.get_node("%AvatarSettings").is_visible_in_tree() or (ui.menu_open and ui.get_node("VBoxContainer").visible)


func _region_at(point: Vector2) -> Region:
	var avatar := ui.get_node("%AvatarSettings")
	if avatar.is_visible_in_tree():
		if avatar.get_node("%AvatarListScroll").get_global_rect().has_point(point):
			return Region.AVATARS
		var collections: ScrollContainer = avatar.get_node("Content/Body/Sidebar/CollectionScroll")
		if collections.get_global_rect().has_point(point) and not collections.get_v_scroll_bar().get_global_rect().has_point(point):
			return Region.COLLECTIONS
		return Region.NONE
	var panel := get_viewport().get_parent()
	# Direct finger contact activates buttons immediately. Dragging the empty
	# list/preview and controller-ray drag buffering retain their existing path.
	if ui.vr_mode and panel != null and panel.has_method("is_hand_pointer") and panel.is_hand_pointer(panel.input_pointer) and ui.xr_button_at(point) != null:
		return Region.NONE
	if rooms.is_visible_in_tree() and rooms.get_global_rect().has_point(point):
		# Keep the native scrollbar draggable as well.
		var bar := rooms.get_v_scroll_bar()
		if bar.visible and bar.get_global_rect().has_point(point):
			return Region.NONE
		return Region.ROOMS
	if world.is_visible_in_tree() and world.get_global_rect().has_point(point):
		return Region.WORLDS
	return Region.NONE


func _input(event: InputEvent) -> void:
	if not _active():
		_cancel_drag()
		return
	if event is InputEventKey:
		_key_input(event)
		return
	# Native touchscreen input uses the same gesture state as XR pointers.
	if event is InputEventScreenTouch:
		if event.pressed and not _dragging:
			var region := _region_at(event.position)
			if region != Region.NONE:
				_begin_drag(region, event.position)
				_touch_index = event.index
				get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _touch_index:
			if event.canceled:
				_cancel_drag()
			else:
				_end_drag(event.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_drag_to(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not ui.vr_mode and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _region_at(event.position) == Region.WORLDS:
			_begin_drag(Region.WORLDS, event.position)
			get_viewport().set_input_as_handled()
		elif not event.pressed and _dragging:
			_end_drag(event.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		if _drag_pointer == null:
			_drag_to(event.position)
		get_viewport().set_input_as_handled()


func _begin_drag(region: Region, point: Vector2) -> void:
	_dragging = true
	_region = region
	_start = point
	var scroll := _scroll_for_region(region)
	_start_scroll = scroll.scroll_vertical if scroll != null else 0
	_dragged = false
	if scroll != null:
		_start_button = ui.xr_button_at(point) as Button
		if _start_button != null and scroll.is_ancestor_of(_start_button):
			_button_focus_style = _start_button.get_theme_stylebox("focus") if _start_button.has_theme_stylebox_override("focus") else null
			_press_feedback_active = true
			_start_button.add_theme_stylebox_override("focus", _start_button.get_theme_stylebox("pressed"))
			_start_button.grab_focus()
		else:
			_start_button = null
			scroll.grab_focus()
	else:
		world.grab_focus()


func _drag_to(point: Vector2) -> void:
	if point.distance_to(_start) >= DRAG_THRESHOLD:
		_dragged = true
		_clear_press_feedback()
	var scroll := _scroll_for_region(_region)
	if _dragged and scroll != null:
		scroll.scroll_vertical = _start_scroll + roundi(_start.y - point.y)


func _end_drag(point: Vector2) -> void:
	_drag_to(point)
	var region := _region
	var was_dragged := _dragged
	var movement := point - _start
	var pointer := _drag_pointer
	var button := _start_button
	var committed := _poke_committed
	_cancel_drag()
	if was_dragged:
		if region == Region.WORLDS and absf(movement.x) >= SWIPE_THRESHOLD and absf(movement.x) > absf(movement.y):
			ui._step_world(-1 if movement.x > 0 else 1)
	elif not committed and is_instance_valid(button) and button.get_global_rect().grow(TAP_RELEASE_TOLERANCE).has_point(point):
		_click.call_deferred(point, pointer, button)


func _scroll_for_region(region: Region) -> ScrollContainer:
	match region:
		Region.ROOMS: return rooms
		Region.AVATARS: return ui.get_node("%AvatarSettings/%AvatarListScroll")
		Region.COLLECTIONS: return ui.get_node("%AvatarSettings/Content/Body/Sidebar/CollectionScroll")
	return null


func _clear_press_feedback() -> void:
	if not _press_feedback_active:
		return
	_press_feedback_active = false
	if not is_instance_valid(_start_button):
		return
	if _button_focus_style != null:
		_start_button.add_theme_stylebox_override("focus", _button_focus_style)
	else:
		_start_button.remove_theme_stylebox_override("focus")
	_button_focus_style = null


func _confirm_poke(point: Vector2) -> void:
	# Optical contact has real depth. A forward press confirms selection early;
	# lateral movement turns into scrolling. Rays/screens keep tap-on-release.
	if _dragged or _poke_committed or not is_instance_valid(_start_button) or not is_instance_valid(_drag_pointer):
		return
	if not _start_button.get_global_rect().grow(TAP_RELEASE_TOLERANCE).has_point(point):
		return
	if not _drag_pointer.has_meta("ui_poke_depth") or float(_drag_pointer.get_meta("ui_poke_depth")) > POKE_CONFIRM_DEPTH:
		return
	_poke_committed = true
	_click.call_deferred(point, _drag_pointer, _start_button)


func _cancel_drag() -> void:
	_clear_press_feedback()
	_start_button = null
	_poke_committed = false
	_dragging = false
	_touch_index = -1
	_region = Region.NONE
	_dragged = false
	_drag_pointer = null


func cancel_pointer_drag() -> void:
	# A controller leaving the panel or losing tracking must not leave a press held.
	_cancel_drag()


func pointer_event(event: XRToolsPointerEvent, point: Vector2) -> bool:
	# Consume XR gestures directly, before the body forwards ordinary GUI input.
	if not _active():
		var consumed := event.pointer == _drag_pointer
		_cancel_drag()
		return consumed
	if event.event_type == XRToolsPointerEvent.Type.PRESSED:
		_cancel_drag()
		var region := _region_at(point)
		if region == Region.NONE:
			return false
		_begin_drag(region, point)
		_drag_pointer = event.pointer
		_confirm_poke(point)
	elif event.pointer != _drag_pointer:
		return false
	elif event.event_type == XRToolsPointerEvent.Type.MOVED:
		_drag_to(point)
		_confirm_poke(point)
	elif event.event_type == XRToolsPointerEvent.Type.RELEASED:
		_end_drag(point)
	elif event.event_type == XRToolsPointerEvent.Type.EXITED:
		_cancel_drag()
	return true


func _click(point: Vector2, pointer: Node3D = null, original_button: Button = null) -> void:
	if not _active():
		return
	if original_button != null and not is_instance_valid(original_button):
		return
	var button := original_button if is_instance_valid(original_button) else ui.xr_button_at(point) as Button
	if button == null or not button.is_visible_in_tree():
		return
	var panel := get_viewport().get_parent()
	var body := panel.get_node_or_null("StaticBody3D") if panel != null else null
	if ui.vr_mode and body != null and body.has_method("accept_button_press") and not body.accept_button_press(button.get_global_rect().get_center()):
		return
	if body != null and is_instance_valid(pointer):
		body.get_parent().input_pointer = pointer
	var target := _scroll_for_region(_region_at(button.get_global_rect().get_center()))
	if button != null and not button.disabled and target != null and target.is_ancestor_of(button):
		button.grab_focus()
		button.pressed.emit()


func _key_input(event: InputEventKey) -> void:
	if ui.get_node("%AvatarSettings").is_visible_in_tree():
		return
	if not event.pressed:
		return
	var focus := get_viewport().gui_get_focus_owner()
	# Text fields retain arrow keys for editing and selection.
	if focus is LineEdit or focus is TextEdit:
		return
	var in_rooms := focus == null or focus == rooms or rooms.is_ancestor_of(focus)
	var in_world := focus == null or focus == world or focus == ui.get_node("%PreviousWorld") or focus == ui.get_node("%NextWorld")
	if in_rooms and (event.is_action_pressed("ui_down", true) or event.is_action_pressed("ui_up", true)):
		_focus_room(1 if event.is_action_pressed("ui_down", true) else -1)
		get_viewport().set_input_as_handled()
	elif in_world and (event.is_action_pressed("ui_left", true) or event.is_action_pressed("ui_right", true)):
		world.grab_focus()
		ui._step_world(1 if event.is_action_pressed("ui_right", true) else -1)
		get_viewport().set_input_as_handled()
	elif in_rooms and event.keycode in [KEY_PAGEDOWN, KEY_PAGEUP, KEY_HOME, KEY_END]:
		rooms.grab_focus()
		match event.keycode:
			KEY_PAGEDOWN: _scroll_by(rooms.size.y * 0.9)
			KEY_PAGEUP: _scroll_by(-rooms.size.y * 0.9)
			KEY_HOME: rooms.scroll_vertical = 0
			KEY_END: rooms.scroll_vertical = int(rooms.get_v_scroll_bar().max_value)
		get_viewport().set_input_as_handled()


func _focus_room(direction: int) -> void:
	var buttons: Array[Button] = []
	for row in ui.get_node("%roomList").get_children():
		var button := row.get_node_or_null("room/Button") as Button
		if button != null and not button.disabled:
			buttons.append(button)
	if buttons.is_empty():
		rooms.grab_focus()
		return
	var focused := get_viewport().gui_get_focus_owner() as Button
	var index := buttons.find(focused) if focused != null else -1
	index = clampi(index + direction, 0, buttons.size() - 1) if index >= 0 else (0 if direction > 0 else buttons.size() - 1)
	buttons[index].grab_focus()
	rooms.ensure_control_visible(buttons[index])


func _world_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			world.grab_focus()
			ui._step_world(1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
			world.accept_event()


func _scroll_by(pixels: float) -> void:
	_scroll_fraction += pixels
	var whole := int(_scroll_fraction)
	_scroll_fraction -= whole
	var previous := rooms.scroll_vertical
	rooms.scroll_vertical += whole
	if rooms.scroll_vertical == previous and whole != 0:
		_scroll_fraction = 0.0


func handle_stick(stick: Vector2, point: Vector2, delta: float) -> void:
	if ui.get_node("%AvatarSettings").is_visible_in_tree():
		_reset_stick()
		ui.get_node("%AvatarSettings").handle_stick(stick, point, delta)
		return
	if not _active() or _dragging or ui.get_node("%Keyboard").visible:
		_reset_stick()
		return
	match _region_at(point):
		Region.ROOMS:
			_reset_stick()
			if absf(stick.y) > STICK_DEADZONE:
				var speed := (absf(stick.y) - STICK_DEADZONE) / (1.0 - STICK_DEADZONE)
				_scroll_by(-signf(stick.y) * speed * SCROLL_SPEED * delta)
		Region.WORLDS:
			if absf(stick.x) < STICK_DEADZONE:
				_reset_stick()
				return
			if absf(stick.x) < 0.55:
				return
			var direction := 1 if stick.x > 0 else -1
			_stick_repeat -= delta
			if direction != _stick_direction:
				ui._step_world(direction)
				_stick_direction = direction
				_stick_repeat = 0.45
			elif _stick_repeat <= 0:
				ui._step_world(direction)
				_stick_repeat = 0.2
		_:
			_reset_stick()


func _reset_stick() -> void:
	_stick_direction = 0
	_stick_repeat = 0.0
