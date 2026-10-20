extends SceneTree
## Original procedural audio, generated once and shipped as WAVs. No sampled music.
const RATE := 22050
const DIRECTORY := "res://worlds/blackthorn_house/audio/"

func _initialize() -> void:
	_generate("clock", 1.0)
	_generate("rain", 8.0)
	_generate("fire", 6.0)
	_generate("gramophone", 24.0)
	quit()

func _generate(kind: String, duration: float) -> void:
	var data := PackedByteArray()
	var frames := int(duration * RATE)
	data.resize(frames * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 1931
	var low := 0.0
	var pop := 0.0
	# Eight bars of an original slow, slightly wistful waltz, in D minor.
	var chords := [[50, 57, 65], [58, 62, 65], [55, 58, 62], [57, 61, 64], [50, 57, 65], [53, 57, 60], [57, 61, 64], [50, 57, 65]]
	var melody := [74, 77, 76, 74, 72, 70, 69, 74, 72, 73, 76, 69, 74, 77, 81, 79, 77, 76, 73, 72, 69, 74, 69, 65]
	for i in frames:
		var t := float(i) / RATE
		var noise := random.randf_range(-1, 1)
		low = lerpf(low, noise, 0.04)
		var value := 0.0
		match kind:
			"clock":
				var beat := fmod(t, 0.5)
				var pitch := 1850.0 if t < 0.5 else 1390.0
				value = (sin(TAU * pitch * beat) * 0.6 + noise * 0.4) * exp(-beat * 160.0) * minf(beat * 1500.0, 1.0)
			"rain":
				value = (noise * 0.055 + low * 0.7) * (0.75 + sin(t * TAU / 8) * 0.12)
			"fire":
				if random.randf() < 0.0008:
					pop = random.randf_range(0.18, 0.55)
				pop *= 0.975
				value = low * 0.35 + noise * pop
			"gramophone":
				var bar := mini(7, int(t / 3.0))
				var beat := int(t) % 3
				var within := fmod(t, 1.0)
				var chord: Array = chords[bar]
				if beat == 0:
					value += _tone(chord[0] - 12, within, 0.6) * 0.15
				else:
					for note: int in chord:
						value += _tone(note, within, 0.4) * 0.045
				value += _tone(melody[mini(23, int(t))], within, 0.8) * 0.18
				value += noise * 0.003
				# Short seam fade is part of the composition, not a sudden loop click.
				value *= minf(t / 0.04, 1.0) * minf((duration - t) / 0.16, 1.0)
		data.encode_s16(i * 2, int(clampf(value, -0.95, 0.95) * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = frames
	var error := stream.save_to_wav(DIRECTORY + kind + ".wav")
	if error != OK:
		push_error("Could not save " + kind)
		quit(1)
	print(kind, ": ", frames, " samples")

func _tone(midi: int, t: float, decay: float) -> float:
	var hz := 440.0 * pow(2.0, float(midi - 69) / 12.0)
	var phase := t * hz * TAU + sin(t * TAU * 5) * 0.014
	var envelope := minf(t * 130.0, 1.0) * exp(-t * (2.7 / decay))
	return (sin(phase) + sin(phase * 2) * 0.23 + sin(phase * 3) * 0.08) * envelope
