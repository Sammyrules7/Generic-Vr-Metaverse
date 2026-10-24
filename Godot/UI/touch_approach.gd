class_name TouchApproach
extends RefCounted
## Classifies the motion before contact, in panel-local metres. Intent is
## latched by the caller for the entire contact, including deep penetration.
const WINDOW_MS := 140
const MIN_TRAVEL := 0.006
var _samples: Array[Vector4] = []

func reset() -> void:
	_samples.clear()

func sample(point: Vector3, time_ms: int = Time.get_ticks_msec()) -> void:
	if point.z > 0.05 or point.z < -0.04:
		reset()
		return
	while not _samples.is_empty() and time_ms - _samples[0].w > WINDOW_MS:
		_samples.pop_front()
	_samples.append(Vector4(point.x, point.y, point.z, time_ms))
	if _samples.size() > 32:
		_samples.pop_front()

func intent() -> String:
	if _samples.size() < 2:
		return "unknown"
	var movement: Vector4 = _samples.back() - _samples.front()
	var lateral := Vector2(movement.x, movement.y).length()
	var inward := maxf(0.0, -movement.z)
	if lateral >= MIN_TRAVEL and lateral >= inward * 0.65:
		return "scroll"
	if inward >= MIN_TRAVEL and inward >= lateral * 2.0:
		return "press"
	return "unknown"
