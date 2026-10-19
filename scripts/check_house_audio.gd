extends SceneTree
## Run in an empty project against the exported PCK, so source-tree resources
## and the project's native-only voice extensions cannot mask missing assets.
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or not ProjectSettings.load_resource_pack(args[0]):
		push_error("Supply the exported PCK to check house audio")
		quit(1)
		return
	var durations := {"clock": 1.0, "gramophone": 24.0, "fire": 6.0, "rain": 8.0}
	for kind: String in durations:
		check(ResourceLoader.exists("res://worlds/blackthorn_house/audio/" + kind + ".wav"), "Export omitted house audio: " + kind)
	if failures:
		quit(1)
		return
	var atmosphere := Node3D.new()
	atmosphere.set_script(load("res://worlds/blackthorn_house/house_atmosphere.gd"))
	root.add_child(atmosphere)
	for kind: String in durations:
		atmosphere._sound(kind, Vector3.ZERO, -15.0, 10.0)
		var player := atmosphere.get_node_or_null(kind.capitalize() + "Sound") as AudioStreamPlayer3D
		check(player != null, "Exported audio player missing: " + kind)
		if player == null:
			continue
		var stream := player.stream as AudioStreamWAV
		check(player.playing and stream != null, "Exported audio did not start: " + kind)
		if stream != null:
			check(is_equal_approx(stream.get_length(), durations[kind]), "Exported audio duration changed: " + kind)
			check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_end == roundi(durations[kind] * stream.mix_rate), "Exported audio loop is truncated: " + kind)
	atmosphere.free()
	print("Exported house audio: 4 streams, ", failures, " failures")
	quit(1 if failures else 0)
