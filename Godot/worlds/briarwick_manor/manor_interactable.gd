extends Node3D
## Local decorative state only. No roles, pickups or network state live here.
@export_enum("Candles", "Curtains", "Music", "Orrery") var action := 0
@export var active := true
@export var audio_path: NodePath
var _time := 0.0
var _tween: Tween
var _base_energy := 0.0

func _ready() -> void:
	if has_node("Glow"):
		_base_energy = $Glow.light_energy
	_apply(false)

func activate() -> void:
	active = not active
	_apply(true)

func _apply(animate: bool) -> void:
	if _tween != null:
		_tween.kill()
	match action:
		0:
			$Flames.visible = active
			$Glow.visible = active
			$Smoke.emitting = not active
			$Sparks.emitting = active
		1:
			_tween = create_tween().set_parallel(true)
			for side in [-1, 1]:
				var cloth := get_node("LeftCurtain" if side < 0 else "RightCurtain") as Node3D
				_tween.tween_property(cloth, "position:x", side * (0.52 if active else 1.02), 0.65 if animate else 0.0)
				_tween.tween_property(cloth, "scale:x", 1.6 if active else 1.0, 0.65 if animate else 0.0)
		2:
			var audio := get_node_or_null(audio_path) as AudioStreamPlayer3D
			if audio != null:
				audio.stream_paused = not active

func _process(delta: float) -> void:
	_time += delta
	if action == 0 and active:
		$Glow.light_energy = _base_energy * (0.94 + 0.04 * sin(_time * 9.1 + position.x) + 0.02 * sin(_time * 17.3))
	elif action == 2 and active:
		$WindingKey.rotate_z(delta * 0.8)
	elif action == 3 and active:
		$Orbits.rotate_y(delta * 0.3)
