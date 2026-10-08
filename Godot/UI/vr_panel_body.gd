extends "res://addons/godot-xr-tools/objects/viewport_2d_in_3d_body.gd"
## Navigation owns XR gestures. Ordinary Controls receive only mouse input.

@export_range(0, 500) var button_debounce_ms := 100
var last_button_press_ms: Dictionary[int, int] = {}
var ignored_presses: Dictionary[Node3D, bool] = {}
var _buffering_mouse := false

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
	elif ignored_presses.has(event.pointer):
		if event.event_type in [XRToolsPointerEvent.Type.RELEASED, XRToolsPointerEvent.Type.EXITED]:
			ignored_presses.erase(event.pointer)
			if event.event_type == XRToolsPointerEvent.Type.EXITED:
				super._on_pointer_event(event)
		return
	var navigation := _viewport.get_child(0).get_node_or_null("Navigation")
	var at := global_to_viewport(event.position)
	_buffering_mouse = navigation != null and navigation.pointer_event(event, at)
	super._on_pointer_event(event)
	_buffering_mouse = false
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


func _report_mouse_down(at: Vector2) -> void:
	if not _buffering_mouse:
		super._report_mouse_down(at)


func _report_mouse_up(at: Vector2) -> void:
	if not _buffering_mouse:
		super._report_mouse_up(at)


func _report_mouse_move(pressed: bool, from: Vector2, to: Vector2) -> void:
	if not _buffering_mouse:
		super._report_mouse_move(pressed, from, to)


# XR Tools also emits touch input. Gestures have already been handled above.
func _report_touch_down(_index: int, _at: Vector2) -> void:
	pass


func _report_touch_up(_index: int, _at: Vector2) -> void:
	pass


func _report_touch_move(_index: int, _pressed: bool, _from: Vector2, _to: Vector2) -> void:
	pass
