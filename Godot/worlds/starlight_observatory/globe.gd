extends Node3D
## Decorative local interaction; deliberately has no network state or RPCs.

const MAP_NAMES := ["THE VOYAGER", "THE CROWN", "THE SWAN"]
var selected_map := 0
var spinning := true
var trigger_held := false
var grip_held := false
var _camera_cache: Camera3D
var _poll_accum := 0.0
@onready var orbits: Node3D = $Orbits
@onready var maps: Node3D = $Orbits/Constellations
@onready var caption: Label3D = $Caption


func _ready() -> void:
	_update_map()


func _process(delta: float) -> void:
	if spinning:
		orbits.rotate_y(delta * 0.09)
	_poll_accum += delta
	if _poll_accum < 0.1:
		return
	_poll_accum = 0.0
	if _camera_cache == null or not is_instance_valid(_camera_cache):
		_camera_cache = get_viewport().get_camera_3d()
	var camera := _camera_cache
	if camera == null or camera.global_position.distance_to(global_position) > 4.2:
		trigger_held = false
		grip_held = false
		return
	# XR action names match the existing project's default OpenXR action map.
	var trigger := false
	var grip := false
	for tracker_name in [&"left_hand", &"right_hand"]:
		var tracker := XRServer.get_tracker(tracker_name) as XRControllerTracker
		if tracker != null:
			var trigger_value: Variant = tracker.get_input(&"trigger")
			var grip_value: Variant = tracker.get_input(&"grip")
			if trigger_value is float:
				trigger = trigger or trigger_value > 0.7
			if grip_value is float:
				grip = grip or grip_value > 0.7
	if trigger and not trigger_held:
		cycle_map()
	if grip and not grip_held:
		spinning = not spinning
	trigger_held = trigger
	grip_held = grip


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.global_position.distance_to(global_position) > 4.2:
		return
	if event.physical_keycode == KEY_E:
		cycle_map()
	elif event.physical_keycode == KEY_R:
		spinning = not spinning


func cycle_map() -> void:
	selected_map = (selected_map + 1) % MAP_NAMES.size()
	_update_map()


func _update_map() -> void:
	for i in maps.get_child_count():
		(maps.get_child(i) as Node3D).visible = i == selected_map
	caption.text = MAP_NAMES[selected_map] + "\nE / TRIGGER  ·  constellation\nR / GRIP  ·  pause orbit"
