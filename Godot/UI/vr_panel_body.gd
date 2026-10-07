extends "res://addons/godot-xr-tools/objects/viewport_2d_in_3d_body.gd"
## One GUI press per XR action. Touch events go only to drag navigation;
## ordinary Controls receive the mouse stream, never both event streams.

@export_range(0, 500) var button_debounce_ms := 100
var last_button_press_ms: Dictionary[int, int] = {}
var ignored_presses: Dictionary[Node3D, bool] = {}

func _on_pointer_event(event: XRToolsPointerEvent) -> void:
	if event.event_type == XRToolsPointerEvent.Type.PRESSED:
		if _presses.has(event.pointer) or ignored_presses.has(event.pointer):
			return
		get_parent().input_pointer = event.pointer
		var ui := _viewport.get_child(0)
		var at := global_to_viewport(event.position)
		var navigation := ui.get_node_or_null("Navigation")
		var buffered: bool = navigation != null and navigation._active() and navigation._region_at(at) != LobbyNavigation.Region.NONE
		if not buffered and not accept_button_press(at):
			ignored_presses[event.pointer] = true
			return
		# A second hand can take over the single GUI mouse without leaving
		# the first hand's button or slider held down.
		if is_instance_valid(_mouse) and _mouse != event.pointer and _presses.has(_mouse):
			_report_mouse_up(_mouse_last)
		_mouse = event.pointer
		_report_mouse_move(false, at, at)
	elif ignored_presses.has(event.pointer):
		if event.event_type in [XRToolsPointerEvent.Type.RELEASED, XRToolsPointerEvent.Type.EXITED]:
			ignored_presses.erase(event.pointer)
			if event.event_type == XRToolsPointerEvent.Type.EXITED:
				super._on_pointer_event(event)
		return
	super._on_pointer_event(event)
	if event.pointer == _mouse:
		_mouse_last = global_to_viewport(event.position)


func accept_button_press(at: Vector2) -> bool:
	var ui := _viewport.get_child(0)
	if not ui.has_method("xr_button_at"):
		return true
	var button: BaseButton = ui.xr_button_at(at)
	if button == null:
		return true
	var id := button.get_instance_id()
	var now := Time.get_ticks_msec()
	for previous_id in last_button_press_ms.keys():
		if now - last_button_press_ms[previous_id] >= button_debounce_ms:
			last_button_press_ms.erase(previous_id)
	if now - last_button_press_ms.get(id, -1000) < button_debounce_ms:
		return false
	last_button_press_ms[id] = now
	return true


func _report_touch_down(index: int, at: Vector2) -> void:
	_navigation_touch(index, at, true)


func _report_touch_up(index: int, at: Vector2) -> void:
	_navigation_touch(index, at, false)


func _navigation_touch(index: int, at: Vector2, pressed: bool) -> void:
	var navigation := _viewport.get_child(0).get_node_or_null("Navigation")
	if navigation != null:
		var event := InputEventScreenTouch.new()
		event.index = index
		event.position = at
		event.pressed = pressed
		navigation._input(event)


func _report_touch_move(index: int, pressed: bool, from: Vector2, to: Vector2) -> void:
	var navigation := _viewport.get_child(0).get_node_or_null("Navigation")
	if navigation != null:
		var event := InputEventScreenDrag.new()
		event.index = index
		event.position = to
		event.pressure = 1.0 if pressed else 0.0
		event.relative = to - from
		navigation._input(event)
