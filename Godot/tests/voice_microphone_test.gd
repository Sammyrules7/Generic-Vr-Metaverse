extends SceneTree

var failures := 0
var voice: VoiceChat


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func wait_for_input() -> bool:
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		if voice.is_input_ready():
			return true
		await process_frame
	return false


func run() -> void:
	# Run with a real display/audio driver. Capture stays local: no room is joined.
	if DisplayServer.get_name() == "headless":
		print("Microphone lifecycle: requires a real audio driver; run without --headless")
		quit(1)
		return
	var network := root.get_node("Networking")
	network.set_process(false)
	network.ws.close(-1)
	voice = network.voice_chat
	var profile_existed := FileAccess.file_exists("user://profile.cfg")
	var profile_backup := FileAccess.get_file_as_bytes("user://profile.cfg") if profile_existed else PackedByteArray()
	var ui: Control = load("res://UI/room_selector.tscn").instantiate()
	root.add_child(ui)
	voice.set_muted(false)
	voice.prepare_microphone()
	check(await wait_for_input(), "Real microphone did not produce frames")
	var generation := voice.capture_generation
	var codec := voice.encoder
	# The automatic permission/device-label refreshes run at 1 and 3 seconds.
	await create_timer(4.0).timeout
	for refresh in range(4):
		voice.refresh_input_devices()
	voice.set_input_device(AudioServer.input_device)
	check(voice.capture_generation == generation and voice.encoder == codec, "Device refresh/reselection reopened the real microphone")
	check(voice.capturing and voice.is_input_ready(), "Device refresh interrupted live capture")
	for toggle in range(8):
		voice.set_muted(true)
		check(not voice.capturing and not voice.is_input_ready(), "Mute did not stop microphone capture")
		voice.set_muted(false)
		voice.prepare_microphone()
		check(await wait_for_input(), "Microphone did not recover after toggle %d" % toggle)
		await create_timer(0.1).timeout
	voice.set_muted(true)
	ui.queue_free()
	if profile_existed:
		FileAccess.open("user://profile.cfg", FileAccess.WRITE).store_buffer(profile_backup)
	else:
		DirAccess.remove_absolute("user://profile.cfg")
	print("Real microphone lifecycle: ", failures, " failures")
	quit(1 if failures else 0)
