extends Node3D


func _ready() -> void:
	# This scene is intentionally usable without the signaling service.
	Networking.set_process(false)
	Networking.ws.close()
