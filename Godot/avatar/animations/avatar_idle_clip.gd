extends RefCounted
## Loads the derived humanoid animation tracks used by AvatarRigDriver.
##
## The data file contains source-space bone directions sampled from a CC0
## animation plus a reference direction for each track. Idle uses its mean;
## locomotion uses the source rest direction to preserve knee flexion. The rig
## maps direction changes onto the target proportions and bone axes.
## Wrist offsets are stored relative to the upper arm and scaled at runtime.

const DEFAULT_PATH := "res://avatar/animations/quaternius_universal_idle_loop.json"

var duration := 0.0
var sample_count := 0
var source := {}
var tracks := {}
var wrists := {}
var error := ""


func load_file(path: String = DEFAULT_PATH) -> bool:
	error = ""
	if not FileAccess.file_exists(path):
		error = "missing " + path
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		error = "unreadable " + path
		return false
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		error = "invalid JSON"
		return false
	var data: Dictionary = parsed
	duration = float(data.get("duration", 0.0))
	sample_count = int(data.get("sample_count", 0))
	source = data.get("source", {})
	if duration <= 0.0 or sample_count < 2:
		error = "invalid timing"
		return false
	var raw_tracks: Dictionary = data.get("tracks", {})
	for key in raw_tracks:
		var entry: Dictionary = raw_tracks[key]
		var frames: Array[Vector3] = []
		for row in entry.get("frames", []):
			frames.append(_vector(row))
		if frames.size() != sample_count:
			error = "track size mismatch for " + str(key)
			tracks.clear()
			return false
		tracks[StringName(key)] = {
			"mean": _vector(entry.get("mean", [0.0, 1.0, 0.0])).normalized(),
			"reference": _vector(entry.get("reference", entry.get("mean", [0.0, 1.0, 0.0]))).normalized(),
			"frames": frames,
		}
	var raw_wrists: Dictionary = data.get("wrists", {})
	for key in raw_wrists:
		var frames: Array[Vector3] = []
		for row in raw_wrists[key]:
			frames.append(_vector(row))
		if frames.size() == sample_count:
			wrists[String(key)] = frames
	if tracks.is_empty():
		error = "no tracks"
		return false
	return true


func has_track(bone_name: StringName) -> bool:
	return tracks.has(bone_name)


func mean_direction(bone_name: StringName) -> Vector3:
	if not tracks.has(bone_name):
		return Vector3.UP
	var track: Dictionary = tracks[bone_name]
	return track["mean"]


## Idle uses its mean; locomotion uses source rest directions to retain knee flexion.
func reference_direction(bone_name: StringName) -> Vector3:
	return tracks[bone_name]["reference"] if tracks.has(bone_name) else Vector3.UP


func sample_direction(bone_name: StringName, time: float) -> Vector3:
	if not tracks.has(bone_name):
		return Vector3.UP
	var track: Dictionary = tracks[bone_name]
	return _sample(track["frames"], time, true)


func has_wrist(side: String) -> bool:
	return wrists.has(side)


## Offset from the upper arm to the hand, relative to the source arm length.
func sample_wrist(side: String, time: float) -> Vector3:
	if not wrists.has(side):
		return Vector3.ZERO
	return _sample(wrists[side], time, false)


func _sample(frames: Array, time: float, normalize_result: bool) -> Vector3:
	var t := fposmod(time, duration)
	var frame := t / duration * float(sample_count - 1)
	var index := clampi(int(floor(frame)), 0, sample_count - 2)
	var blend := clampf(frame - float(index), 0.0, 1.0)
	var a: Vector3 = frames[index]
	var b: Vector3 = frames[index + 1]
	var result := a.lerp(b, blend)
	return result.normalized() if normalize_result else result


func _vector(value) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
