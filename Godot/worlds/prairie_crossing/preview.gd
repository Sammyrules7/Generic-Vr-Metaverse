extends Node3D
## Offline preview; --weather=night or --weather=daylight select other moods.

func _enter_tree() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--weather="):
			var preset := argument.trim_prefix("--weather=")
			if preset in ["daylight", "rain", "night"]:
				$World.weather_preset = preset

func _ready() -> void:
	Networking.set_process(false)
	Networking.ws.close()
	$Players/PreviewPlayer/HUD/Controls.text = "PRAIRIE CROSSING / " + $World.weather_preset.to_upper() + "\nWASD / arrows · walk    Mouse · look    Esc · release cursor\nExplore the bench overlook and enjoy the ravine views."
