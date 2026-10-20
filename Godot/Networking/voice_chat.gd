class_name VoiceChat
extends Node

# Godot owns microphone capture; TwoVoip owns resampling, denoising, Opus, and
# the playback ring. Encoding and decoding stay on one worker. Only AudioServer,
# scene nodes, controls, and multiplayer RPCs are accessed on the main thread.
const SAMPLE_RATE := 48000
const FRAME_MS := 20
@warning_ignore("integer_division")
const SAMPLES_PER_FRAME := SAMPLE_RATE * FRAME_MS / 1000
const BIT_RATE := 24000
const MAX_PACKET_BYTES := 1275
const MAX_PENDING_JOBS := 16
# One hostile peer must not crowd the shared job queue and starve other
# speakers' decodes: drop that peer's excess pending packets instead. The
# playback ring (~10 frames) would shed them shortly anyway.
const MAX_PENDING_DECODES_PER_PEER := 6
const MAX_READY_FRAMES := 16
const SILENCE_THRESHOLD := 0.003
const SILENCE_HANGOVER_FRAMES := 12
const REMOTE_ACTIVITY_TIMEOUT_MS := 350
const PLAYBACK_BUFFER_SECONDS := 0.2
const PLAYBACK_START_FRAMES := SAMPLES_PER_FRAME * 3

signal local_speaking_changed(active: bool)
signal peer_speaking_changed(peer_id: int, active: bool)
signal muted_changed(muted: bool)
signal input_device_changed(device: String)
signal input_devices_changed(devices: PackedStringArray)
signal input_ready_changed(ready: bool)
signal input_permission_denied
signal output_volume_changed(volume: float)

var room_networking: RoomNetworking
var muted := false
var output_volume := 0.8
var input_gain := 1.0
var push_to_talk := false
var encoder: TwovoipOpusEncoder
var capture_frames := 0
var capturing := false
var worker := Thread.new()
var worker_mutex := Mutex.new()
var worker_wakeup := Semaphore.new()
var worker_running := false
var jobs: Array[Dictionary] = []
var encoded_frames: Array[Dictionary] = []
var decoded_packets: Array[Dictionary] = []
var speakers: Dictionary[int, AudioStreamPlayer3D] = {}
var voice_generation := 0
var capture_generation := 0
var peer_anchors: Dictionary[int, Node3D] = {}
var peer_activity_deadlines: Dictionary[int, int] = {}
var local_speaking := false
var input_ready := false
var input_permission_requested := false
var audience_policy := Callable()
var _web_permission_callback: JavaScriptObject


func set_audience_policy(policy: Callable) -> void:
	audience_policy = policy
	for peer_id: int in speakers.keys():
		if not can_hear(peer_id, multiplayer.get_unique_id()):
			_remove_speaker(peer_id)


func can_hear(sender_id: int, listener_id: int) -> bool:
	return not audience_policy.is_valid() or audience_policy.call(sender_id, listener_id)


func send_voice(packet: PackedByteArray) -> void:
	for peer_id: int in multiplayer.get_peers():
		if can_hear(multiplayer.get_unique_id(), peer_id):
			voice_packet.rpc_id(peer_id, packet)


func bind_signaling(signaling: RoomNetworking) -> void:
	if room_networking != null and room_networking != signaling:
		if room_networking.room_joined.is_connected(_start_voice):
			room_networking.room_joined.disconnect(_start_voice)
		if room_networking.room_left.is_connected(_stop_voice):
			room_networking.room_left.disconnect(_stop_voice)
		if room_networking.room_left.is_connected(_reset_audience_policy):
			room_networking.room_left.disconnect(_reset_audience_policy)
	room_networking = signaling
	if not room_networking.room_joined.is_connected(_start_voice):
		room_networking.room_joined.connect(_start_voice)
	if not room_networking.room_left.is_connected(_stop_voice):
		room_networking.room_left.connect(_stop_voice)
	if not room_networking.room_left.is_connected(_reset_audience_policy):
		room_networking.room_left.connect(_reset_audience_policy)
	if worker_running and is_inside_tree() and room_networking.current_room != null:
		_start_voice(room_networking.current_room)


func _ready() -> void:
	if room_networking == null:
		# Fallback for scenes/tests that instance VoiceChat without injection.
		# Preferred path is the Networking autoload setting room_networking before add_child.
		room_networking = get_parent().get("room_networking") as RoomNetworking
	if room_networking == null:
		push_error("VoiceChat has no RoomNetworking; voice will stay idle")
		return
	bind_signaling(room_networking)
	multiplayer.peer_disconnected.connect(_remove_speaker)
	if OS.has_feature("android"):
		get_tree().on_request_permissions_result.connect(_on_permission_result)
	worker_running = true
	if worker.start(_worker_loop) != OK:
		worker_running = false
		push_error("Could not start voice processing")
		set_process(false)
		return
	if room_networking.current_room != null:
		_start_voice(room_networking.current_room)


func _exit_tree() -> void:
	_stop_voice()
	if worker.is_started():
		worker_mutex.lock()
		worker_running = false
		worker_mutex.unlock()
		worker_wakeup.post()
		worker.wait_to_finish()


func set_muted(value: bool) -> void:
	if muted == value:
		return
	muted = value
	if muted:
		_stop_capture()
	muted_changed.emit(muted)
	_set_local_speaking(false)


func set_output_volume(value: float) -> void:
	output_volume = clampf(value, 0.0, 1.0)
	for speaker: AudioStreamPlayer3D in speakers.values():
		speaker.volume_db = linear_to_db(output_volume)
	output_volume_changed.emit(output_volume)


func set_input_gain(value: float) -> void:
	input_gain = clampf(value, 0.0, 2.0)


func set_push_to_talk(value: bool) -> void:
	push_to_talk = value
	if value and not Input.is_action_pressed("voice_push_to_talk"):
		_set_local_speaking(false)


func set_input_device(device: String) -> void:
	var available := AudioServer.get_input_device_list()
	var selected := device if available.has(device) else "Default"
	if selected == AudioServer.input_device:
		return
	var restart := capturing
	_stop_capture()
	AudioServer.input_device = selected
	input_device_changed.emit(AudioServer.input_device)
	if restart:
		prepare_microphone()


func get_input_devices() -> PackedStringArray:
	return AudioServer.get_input_device_list()


func refresh_input_devices() -> void:
	input_devices_changed.emit(get_input_devices())


func is_input_ready() -> bool:
	return input_ready


func has_requested_input_permission() -> bool:
	return input_permission_requested


func set_peer_anchor(peer_id: int, anchor: Node3D) -> void:
	remove_peer_anchor(peer_id)
	peer_anchors[peer_id] = anchor


func remove_peer_anchor(peer_id: int) -> void:
	peer_anchors.erase(peer_id)
	_remove_speaker(peer_id)


func _reset_audience_policy() -> void:
	set_audience_policy(Callable())


func _start_voice(_room: roomClass) -> void:
	_stop_voice()
	# Web microphone permission must originate in the voice/settings gesture,
	# without competing with the WebXR permission prompt when joining a room.
	if not muted and (not OS.has_feature("web") or input_permission_requested):
		prepare_microphone()


func _create_encoder(input_rate: float) -> TwovoipOpusEncoder:
	var codec := TwovoipOpusEncoder.new()
	var error := codec.initialize(int(input_rate), SAMPLE_RATE, 1,
		TwovoipOpusEncoder.DENOISER_RNNOISE, TwovoipOpusEncoder.AGC_DISABLED,
		SAMPLES_PER_FRAME)
	if error != OK or not codec.create_opus_encoder(BIT_RATE, 5, true):
		push_error("Could not initialize TwoVoip: %s" % error_string(error))
		return null
	return codec


func prepare_microphone() -> bool:
	if DisplayServer.get_name() == "headless" or not worker_running or muted:
		return false
	input_permission_requested = true
	if capturing:
		return input_ready
	if OS.has_feature("android") and not OS.request_permission("android.permission.RECORD_AUDIO"):
		return false
	if OS.has_feature("web"):
		_watch_web_microphone_permission()
	var error := AudioServer.set_input_device_active(true)
	if error != OK:
		push_warning("Could not start microphone: %s" % error_string(error))
		_microphone_permission_denied()
		return false
	encoder = _create_encoder(AudioServer.get_input_mix_rate())
	if encoder == null:
		AudioServer.set_input_device_active(false)
		return false
	capture_frames = encoder.get_required_input_chunk_size()
	capturing = true
	# Device labels become available after the browser permission prompt.
	get_tree().create_timer(1.0).timeout.connect(refresh_input_devices)
	get_tree().create_timer(3.0).timeout.connect(refresh_input_devices)
	return input_ready


func _watch_web_microphone_permission() -> void:
	if _web_permission_callback == null:
		_web_permission_callback = JavaScriptBridge.create_callback(_on_web_permission_result)
	JavaScriptBridge.eval("""
		window.vrPlatformWatchMicrophone = function(callback) {
			if (!navigator.permissions) return;
			navigator.permissions.query({name: "microphone"}).then(function(status) {
				const report = function() { callback(status.state); };
				status.onchange = report;
				report();
			}).catch(function() {});
		};
	""")
	JavaScriptBridge.get_interface("window").vrPlatformWatchMicrophone(_web_permission_callback)


func _on_web_permission_result(arguments: Array) -> void:
	if not arguments.is_empty() and str(arguments[0]) == "denied":
		_microphone_permission_denied()


func _microphone_permission_denied() -> void:
	set_muted(true)
	input_permission_requested = false
	input_permission_denied.emit()


func _on_permission_result(permission: String, granted: bool) -> void:
	if permission != "android.permission.RECORD_AUDIO":
		return
	if not granted:
		_microphone_permission_denied()
	elif input_permission_requested and not muted:
		prepare_microphone()


func _stop_capture() -> void:
	if capturing:
		AudioServer.set_input_device_active(false)
	capturing = false
	encoder = null
	if input_ready:
		input_ready = false
		input_ready_changed.emit(false)
	worker_mutex.lock()
	capture_generation += 1
	encoded_frames.clear()
	worker_mutex.unlock()
	_set_local_speaking(false)


func _stop_voice() -> void:
	_stop_capture()
	for peer_id in speakers.keys():
		_remove_speaker(peer_id)
	worker_mutex.lock()
	voice_generation += 1
	jobs.clear()
	encoded_frames.clear()
	decoded_packets.clear()
	worker_mutex.unlock()


func _can_transmit() -> bool:
	return room_networking != null and room_networking.current_room != null and not muted and (not push_to_talk or Input.is_action_pressed("voice_push_to_talk"))


func _process(_delta: float) -> void:
	var transmit := _can_transmit()
	if not transmit:
		_set_local_speaking(false)
	if capturing:
		# Discard old capture after a hitch instead of transmitting stale speech.
		var excess := AudioServer.get_input_frames_available() - capture_frames * 4
		if excess > 0:
			AudioServer.get_input_frames(excess)
		while true:
			var frames := AudioServer.get_input_frames(capture_frames)
			if frames.is_empty():
				break
			if not input_ready:
				input_ready = true
				input_ready_changed.emit(true)
			_queue_job({"encode": frames, "encoder": encoder, "generation": voice_generation,
				"capture_generation": capture_generation, "gain": input_gain, "transmit": transmit})

	worker_mutex.lock()
	var has_outgoing := not encoded_frames.is_empty()
	var has_incoming := not decoded_packets.is_empty()
	var outgoing: Array = []
	var incoming: Array = []
	if has_outgoing:
		outgoing = encoded_frames.duplicate()
		encoded_frames.clear()
	if has_incoming:
		incoming = decoded_packets.duplicate()
		decoded_packets.clear()
	worker_mutex.unlock()
	for result: Dictionary in outgoing:
		if result.capture_generation != capture_generation:
			continue
		var active: bool = result.active and transmit
		_set_local_speaking(active)
		if active:
			send_voice(result.packet)
	for result: Dictionary in incoming:
		var speaker := speakers.get(result.peer_id) as AudioStreamPlayer3D
		if result.frames > 0 and is_instance_valid(speaker) and speaker.get_stream_playback() == result.playback:
			if result.playback.queue_length_frames() >= PLAYBACK_START_FRAMES:
				# The true variant clears the atomic stream-end marker; it does
				# not reset the Opus decoder. The false variant resets that decoder
				# and stays confined to the worker via the "end" job below.
				result.playback.mark_end_opus_stream(true)
			if not peer_activity_deadlines.has(result.peer_id):
				peer_speaking_changed.emit(result.peer_id, true)
			peer_activity_deadlines[result.peer_id] = Time.get_ticks_msec() + REMOTE_ACTIVITY_TIMEOUT_MS
	var now := Time.get_ticks_msec()
	for peer_id: int in peer_activity_deadlines.keys():
		if now >= peer_activity_deadlines[peer_id]:
			var playback := speakers[peer_id].get_stream_playback() as AudioStreamPlaybackOpus
			# Also release utterances shorter than the initial buffering target.
			playback.mark_end_opus_stream(true)
			_queue_job({"end": playback, "generation": voice_generation})
			peer_activity_deadlines.erase(peer_id)
			peer_speaking_changed.emit(peer_id, false)


func _queue_job(job: Dictionary) -> void:
	worker_mutex.lock()
	if job.has("decode"):
		var pending_for_peer := 0
		for queued: Dictionary in jobs:
			if queued.get("peer_id", 0) == job.peer_id:
				pending_for_peer += 1
		if pending_for_peer >= MAX_PENDING_DECODES_PER_PEER:
			worker_mutex.unlock()
			return
	if jobs.size() >= MAX_PENDING_JOBS:
		jobs.pop_front()
	jobs.append(job)
	worker_mutex.unlock()
	worker_wakeup.post()


func _worker_loop() -> void:
	var codec: TwovoipOpusEncoder = null
	var pending_input := PackedVector2Array()
	var silence_frames := 0
	var was_active := false
	while true:
		worker_wakeup.wait()
		worker_mutex.lock()
		var running := worker_running
		var job: Dictionary = jobs.pop_front() if not jobs.is_empty() else {}
		var current_generation := voice_generation
		var current_capture := capture_generation
		worker_mutex.unlock()
		if not running:
			return
		if job.is_empty() or job.generation != current_generation:
			continue
		if job.has("encode"):
			if job.capture_generation != current_capture:
				continue
			if codec != job.encoder:
				codec = job.encoder
				pending_input.clear()
				silence_frames = 0
				was_active = false
			codec.set_gain(job.gain)
			pending_input.append_array(job.encode)
			while pending_input.size() >= codec.get_required_input_chunk_size():
				var consumed := codec.process_chunk(pending_input)
				if consumed <= 0:
					pending_input.clear()
					break
				# Speex can consume fewer input samples at fractional device rates.
				pending_input = pending_input.slice(consumed)
				var active: bool = job.transmit and codec.get_rms() >= SILENCE_THRESHOLD
				if active:
					silence_frames = SILENCE_HANGOVER_FRAMES
				elif silence_frames > 0 and job.transmit:
					silence_frames -= 1
					active = true
				if active and not was_active:
					codec.reset_opus_encoder()
				was_active = active
				var packet := codec.encode_chunk() if active else PackedByteArray()
				worker_mutex.lock()
				if job.generation == voice_generation and job.capture_generation == capture_generation and encoded_frames.size() < MAX_READY_FRAMES:
					encoded_frames.append({"packet": packet, "active": active and not packet.is_empty(), "capture_generation": job.capture_generation})
				worker_mutex.unlock()
		elif job.has("decode"):
			var frames: int = job.playback.push_opus_packet(job.decode, 0, 0)
			worker_mutex.lock()
			if job.generation == voice_generation and decoded_packets.size() < MAX_READY_FRAMES:
				decoded_packets.append({"peer_id": job.peer_id, "playback": job.playback, "frames": frames})
			worker_mutex.unlock()
		elif job.has("end"):
			# This resets the native decoder as well as marking the ring's tail,
			# so it must run on the same worker that calls push_opus_packet().
			job.end.mark_end_opus_stream(false)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func voice_packet(packet: PackedByteArray = PackedByteArray()) -> void:
	var peer_id := multiplayer.get_remote_sender_id()
	if packet.is_empty() or packet.size() > MAX_PACKET_BYTES or not multiplayer.get_peers().has(peer_id) or not can_hear(peer_id, multiplayer.get_unique_id()) or not worker_running:
		return
	var playback := _speaker_playback(peer_id)
	if playback != null:
		_queue_job({"decode": packet, "peer_id": peer_id, "playback": playback, "generation": voice_generation})


func _speaker_playback(peer_id: int) -> AudioStreamPlaybackOpus:
	var anchor := peer_anchors.get(peer_id) as Node3D
	if not is_instance_valid(anchor):
		return null
	var speaker := speakers.get(peer_id) as AudioStreamPlayer3D
	if speaker == null:
		var stream := AudioStreamOpus.new()
		stream.opus_sample_rate = SAMPLE_RATE
		stream.opus_channels = 1
		stream.buffer_length = PLAYBACK_BUFFER_SECONDS
		speaker = AudioStreamPlayer3D.new()
		speaker.name = "Speaker%d" % peer_id
		speaker.stream = stream
		speaker.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		speaker.volume_db = linear_to_db(output_volume)
		speaker.unit_size = 2.0
		speaker.max_distance = 40.0
		speaker.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		anchor.add_child(speaker)
		speaker.play()
		speakers[peer_id] = speaker
	return speaker.get_stream_playback() as AudioStreamPlaybackOpus


func _remove_speaker(peer_id: int) -> void:
	var speaker := speakers.get(peer_id) as AudioStreamPlayer3D
	if is_instance_valid(speaker):
		speaker.stop()
		speaker.queue_free()
	speakers.erase(peer_id)
	if peer_activity_deadlines.erase(peer_id):
		peer_speaking_changed.emit(peer_id, false)


func _set_local_speaking(active: bool) -> void:
	if local_speaking != active:
		local_speaking = active
		local_speaking_changed.emit(active)
