extends SceneTree
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	var world = load("res://worlds/prairie_crossing/prairie_crossing.tscn").instantiate()
	root.add_child(world)
	var control = world.get_node("WeatherControl")
	var weather = world.get_node("Weather")
	check(control.buttons.size() == 3, "Station needs three physical buttons")
	check(world.find_children("*", "CanvasLayer", true, false).is_empty(), "Weather control must be entirely in the world")
	await physics_frame
	await physics_frame
	for index in [0, 2, 1, 0, 1, 2, 0]:
		var button: Node3D = control.buttons[index]
		var start := button.global_position + button.global_basis.z * 1.5
		check(control._pick(start, -button.global_basis.z.normalized()) == index, "Physical ray must select the intended weather button")
		control.select_button(index)
		check(weather.preset == weather.PRESETS[index], "Weather button did not select its preset")
	await create_timer(weather.TRANSITION_SECONDS + 0.1).timeout
	for entry in weather._baseline:
		check(entry[0].get(entry[1]) == entry[2], "Daylight must restore " + str(entry[1]))
	check(not weather._rain.visible and not weather._night.visible, "Daylight must disable rain and night effects")
	world.free()
	print("Prairie weather: ", failures, " failures")
	quit(1 if failures else 0)
