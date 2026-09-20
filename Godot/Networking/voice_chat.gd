class_name VoiceChat
extends Node

# Voice uses a separate unreliable WebRTC channel so a late audio frame can never
# delay player poses. AudioServer and scene nodes remain on the main thread; the
# comparatively expensive PCM conversion runs on a dedicated worker.
const SAMPLE_RATE := 24000
const FRAME_MS := 20
const SAMPLES_PER_FRAME := SAMPLE_RATE * FRAME_MS / 1000
const BYTES_PER_FRAME := SAMPLES_PER_FRAME * 2
const MAX_PENDING_JOBS := 32
const MAX_READY_FRAMES := 16
const SILENCE_THRESHOLD := 0.003
const SILENCE_HANGOVER_FRAMES := 12
const REMOTE_ACTIVITY_TIMEOUT_MS := 350

signal local_speaking_changed(active: bool)
signal peer_speaking_changed(peer_id: int, active: bool)
signal muted_changed(muted: bool)
signal input_device_changed(device: String)
signal output_volume_changed(volume: float)

var room_networking: RoomNetworking
var muted := false
var output_volume := 0.8
var input_gain := 1.0
var push_to_talk := false
var capture: AudioEffectCapture
var microphone: AudioStreamPlayer
var capture_bus := -1
var capture_frames := 0
var worker := Thread.new()
var worker_mutex := Mutex.new()
var worker_wakeup := Semaphore.new()
var worker_running := false
var jobs: Array = []
var encoded_frames: Array = []
var decoded_frames: Array = []
var speakers: Dictionary[int, AudioStreamPlayer3D] = {}
var voice_generation := 0
var peer_anchors: Dictionary[int, Node3D] = {}
var peer_activity_deadlines: Dictionary[int, int] = {}
var local_speaking := false
var silence_frames := 0


func _ready() -> void:
	# Headless integration clients share one AudioServer and have no microphone.
	# Keeping voice dormant there also makes server-side test runs deterministic.
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	room_networking = get_parent().room_networking
	room_networking.room_joined.connect(_start_voice)
	room_networking.room_left.connect(_stop_voice)
	multiplayer.peer_disconnected.connect(_remove_speaker)
	worker_running = true
	worker.start(_worker_loop)
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
	if capture != null and muted:
		capture.clear_buffer()
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
	AudioServer.input_device = device if available.has(device) else "Default"
	input_device_changed.emit(AudioServer.input_device)


func get_input_devices() -> PackedStringArray:
	return AudioServer.get_input_device_list()


func set_peer_anchor(peer_id: int, anchor: Node3D) -> void:
	remove_peer_anchor(peer_id)
	peer_anchors[peer_id] = anchor


func remove_peer_anchor(peer_id: int) -> void:
	peer_anchors.erase(peer_id)
	_remove_speaker(peer_id)


func _start_voice(_room: roomClass) -> void:
	if microphone != null:
		return
	if OS.has_feature("android"):
		OS.request_permission("RECORD_AUDIO")
	capture_bus = AudioServer.bus_count
	AudioServer.add_bus(capture_bus)
	AudioServer.set_bus_name(capture_bus, "VoiceCapture%d" % get_instance_id())
	AudioServer.set_bus_mute(capture_bus, true)
	capture = AudioEffectCapture.new()
	capture.buffer_length = 0.1
	AudioServer.add_bus_effect(capture_bus, capture)
	capture_frames = maxi(1, roundi(AudioServer.get_mix_rate() * FRAME_MS / 1000.0))
	microphone = AudioStreamPlayer.new()
	microphone.name = "Microphone"
	microphone.stream = AudioStreamMicrophone.new()
	microphone.bus = AudioServer.get_bus_name(capture_bus)
	add_child(microphone)
	microphone.play()


func _stop_voice() -> void:
	if microphone != null:
		microphone.stop()
		microphone.queue_free()
		microphone = null
	for peer_id in speakers.keys():
		_remove_speaker(peer_id)
	if capture_bus >= 0:
		AudioServer.remove_bus(capture_bus)
	capture_bus = -1
	capture = null
	worker_mutex.lock()
	voice_generation += 1
	silence_frames = 0
	jobs.clear()
	encoded_frames.clear()
	decoded_frames.clear()
	worker_mutex.unlock()
	_set_local_speaking(false)


func _process(_delta: float) -> void:
	if capture != null and not muted:
		# Bound work during a hitch: old speech is less useful than current speech.
		while capture.get_frames_available() >= capture_frames:
			_queue_job({
				"encode": capture.get_buffer(capture_frames),
				"generation": voice_generation,
				"gain": input_gain,
				"transmit": not push_to_talk or Input.is_action_pressed("voice_push_to_talk")
			})
	elif capture != null:
		capture.clear_buffer()

	worker_mutex.lock()
	var outgoing := encoded_frames.duplicate()
	var incoming := decoded_frames.duplicate()
	encoded_frames.clear()
	decoded_frames.clear()
	worker_mutex.unlock()
	if room_networking == null or room_networking.current_room == null:
		return
	for result: Dictionary in outgoing:
		_set_local_speaking(result.active)
		if result.active:
			voice_packet.rpc(result.packet)
	for item: Dictionary in incoming:
		_push_audio(item.peer_id, item.frames)
	var now := Time.get_ticks_msec()
	for peer_id: int in peer_activity_deadlines.keys():
		if now >= peer_activity_deadlines[peer_id]:
			peer_activity_deadlines.erase(peer_id)
			peer_speaking_changed.emit(peer_id, false)


func _queue_job(job: Dictionary) -> void:
	worker_mutex.lock()
	if jobs.size() >= MAX_PENDING_JOBS:
		jobs.pop_front()
	jobs.append(job)
	worker_mutex.unlock()
	worker_wakeup.post()


func _worker_loop() -> void:
	while true:
		worker_wakeup.wait()
		worker_mutex.lock()
		var running := worker_running
		var job: Dictionary = jobs.pop_front() if not jobs.is_empty() else {}
		worker_mutex.unlock()
		if not running:
			return
		if job.has("encode"):
			var result := _encode_pcm(job.encode, job.gain)
			worker_mutex.lock()
			var active: bool = job.transmit and result.level >= SILENCE_THRESHOLD
			if active:
				silence_frames = SILENCE_HANGOVER_FRAMES
			elif silence_frames > 0 and job.transmit:
				silence_frames -= 1
				active = true
			if job.generation == voice_generation and encoded_frames.size() < MAX_READY_FRAMES:
				encoded_frames.append({"packet": result.packet, "active": active})
			worker_mutex.unlock()
		elif job.has("decode"):
			var frames := _decode_pcm(job.decode)
			worker_mutex.lock()
			if job.generation == voice_generation and decoded_frames.size() < MAX_READY_FRAMES:
				decoded_frames.append({"peer_id": job.peer_id, "frames": frames})
			worker_mutex.unlock()


func _encode_pcm(source: PackedVector2Array, gain := 1.0) -> Dictionary:
	var packet := PackedByteArray()
	packet.resize(BYTES_PER_FRAME)
	var energy := 0.0
	for index in SAMPLES_PER_FRAME:
		# Capture runs at the output mix rate. This also handles non-48 kHz devices.
		var source_index := mini(source.size() - 1, index * source.size() / SAMPLES_PER_FRAME)
		var stereo := source[source_index]
		var mono := clampf((stereo.x + stereo.y) * 0.5 * gain, -1.0, 1.0)
		energy += mono * mono
		packet.encode_s16(index * 2, roundi(mono * 32767.0))
	return {"packet": packet, "level": sqrt(energy / SAMPLES_PER_FRAME)}


func _decode_pcm(packet: PackedByteArray) -> PackedVector2Array:
	var frames := PackedVector2Array()
	frames.resize(SAMPLES_PER_FRAME)
	for index in SAMPLES_PER_FRAME:
		var sample := packet.decode_s16(index * 2) / 32768.0
		frames[index] = Vector2(sample, sample)
	return frames


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func voice_packet(packet: PackedByteArray) -> void:
	var peer_id := multiplayer.get_remote_sender_id()
	if packet.size() != BYTES_PER_FRAME or not multiplayer.get_peers().has(peer_id):
		return
	if not peer_activity_deadlines.has(peer_id):
		peer_speaking_changed.emit(peer_id, true)
	peer_activity_deadlines[peer_id] = Time.get_ticks_msec() + REMOTE_ACTIVITY_TIMEOUT_MS
	_queue_job({"decode": packet, "peer_id": peer_id, "generation": voice_generation})


func _push_audio(peer_id: int, frames: PackedVector2Array) -> void:
	var anchor := peer_anchors.get(peer_id) as Node3D
	if not is_instance_valid(anchor):
		return
	var speaker := speakers.get(peer_id) as AudioStreamPlayer3D
	if speaker == null:
		var stream := AudioStreamGenerator.new()
		stream.mix_rate = SAMPLE_RATE
		stream.buffer_length = 0.12
		speaker = AudioStreamPlayer3D.new()
		speaker.name = "Speaker%d" % peer_id
		speaker.stream = stream
		speaker.volume_db = linear_to_db(output_volume)
		speaker.unit_size = 2.0
		speaker.max_distance = 40.0
		speaker.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		anchor.add_child(speaker)
		speaker.play()
		speakers[peer_id] = speaker
	var playback := speaker.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback != null and playback.can_push_buffer(frames.size()):
		playback.push_buffer(frames)


func _remove_speaker(peer_id: int) -> void:
	var speaker := speakers.get(peer_id) as AudioStreamPlayer3D
	if is_instance_valid(speaker):
		speaker.queue_free()
	speakers.erase(peer_id)
	if peer_activity_deadlines.erase(peer_id):
		peer_speaking_changed.emit(peer_id, false)


func _set_local_speaking(active: bool) -> void:
	if local_speaking != active:
		local_speaking = active
		local_speaking_changed.emit(active)
