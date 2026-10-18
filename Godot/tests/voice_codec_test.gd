extends SceneTree

var failures := 0
var voice: VoiceChat


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func wait_for_results(encoded: bool) -> Array[Dictionary]:
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		voice.worker_mutex.lock()
		var results := voice.encoded_frames.duplicate() if encoded else voice.decoded_packets.duplicate()
		if encoded:
			voice.encoded_frames.clear()
		else:
			voice.decoded_packets.clear()
		voice.worker_mutex.unlock()
		if not results.is_empty():
			return results
		await process_frame
	check(false, "Timed out waiting for TwoVoip worker")
	return []


func encode(codec: TwovoipOpusEncoder, frames: PackedVector2Array, transmit := true) -> Array[Dictionary]:
	voice._queue_job({"encode": frames, "encoder": codec, "generation": voice.voice_generation,
		"capture_generation": voice.capture_generation, "gain": 1.0, "transmit": transmit})
	return await wait_for_results(true)


func run() -> void:
	# The real native codecs run on the real worker without opening a microphone.
	var network := root.get_node("Networking")
	network.set_process(false)
	network.ws.close(-1)
	voice = network.voice_chat
	voice.set_process(false)
	check(voice.worker.is_started(), "Voice worker failed to start")
	var anchor := Node3D.new()
	root.add_child(anchor)
	voice.set_peer_anchor(2, anchor)
	var playback := voice._speaker_playback(2)
	check(playback is AudioStreamPlaybackOpus, "Voice must use TwoVoip's native playback")
	check(voice.speakers[2].get_parent() == anchor, "Voice must attach to the avatar anchor")
	voice.set_output_volume(0.35)
	check(is_equal_approx(voice.speakers[2].volume_db, linear_to_db(0.35)), "Voice volume did not reach the native speaker")

	for input_rate in [48000, 44100, 44117]:
		var codec := voice._create_encoder(input_rate)
		check(codec != null, "TwoVoip must support device sample rate %d" % input_rate)
		if codec == null:
			continue
		var frames := PackedVector2Array()
		frames.resize(codec.get_required_input_chunk_size())
		var silence := await encode(codec, frames)
		check(not silence.is_empty() and not silence[0].active, "Silence must not transmit")
		for index in frames.size():
			var sample := sin(TAU * 440.0 * index / input_rate) * 0.2
			frames[index] = Vector2(sample, sample)
		var speech := await encode(codec, frames)
		check(not speech.is_empty() and speech[0].active, "Speech must activate the native encoder")
		if speech.is_empty():
			continue
		var packet: PackedByteArray = speech[0].packet
		check(not packet.is_empty() and packet.size() < VoiceChat.SAMPLES_PER_FRAME * 2, "Voice must be compressed Opus, not PCM")
		voice._queue_job({"decode": packet, "peer_id": 2, "playback": playback, "generation": voice.voice_generation})
		var decoded := await wait_for_results(false)
		check(not decoded.is_empty() and decoded[0].frames == VoiceChat.SAMPLES_PER_FRAME, "Native Opus decoding must yield one 20 ms frame")
		var blocked := await encode(codec, frames, false)
		check(not blocked.is_empty() and not blocked[0].active and blocked[0].packet.is_empty(), "Push-to-talk release must prevent encoding")

	check(playback.get_decode_errors() == 0, "Native decoder reported an error on real encoded audio")
	# Per-peer decode fairness: a flooding peer drops its own excess packets
	# instead of crowding the shared job queue and starving other speakers.
	var fairness := VoiceChat.new()
	for packet_index in VoiceChat.MAX_PENDING_DECODES_PER_PEER + 2:
		fairness._queue_job({"decode": PackedByteArray(), "peer_id": 2, "generation": 1})
	fairness._queue_job({"decode": PackedByteArray(), "peer_id": 3, "generation": 1})
	var flooded := 0
	var other := 0
	for job in fairness.jobs:
		if job.peer_id == 2:
			flooded += 1
		elif job.peer_id == 3:
			other += 1
	check(flooded == VoiceChat.MAX_PENDING_DECODES_PER_PEER and other == 1, "Decode fairness must cap one peer's pending packets without dropping others")
	fairness.free()
	voice._set_local_speaking(true)
	voice.set_muted(true)
	check(not voice.local_speaking and voice.encoded_frames.is_empty(), "Mute must clear queued speech and activity")
	voice.set_audience_policy(func(_sender, _listener): return false)
	check(voice.speakers.is_empty(), "Audience changes must stop buffered native playback")
	voice._stop_voice()
	voice.worker_mutex.lock()
	check(voice.jobs.is_empty() and voice.decoded_packets.is_empty(), "Room teardown must clear pending voice work")
	voice.worker_mutex.unlock()
	anchor.queue_free()
	await process_frame
	print("TwoVoip native codec and worker: ", failures, " failures")
	quit(1 if failures else 0)
