extends Node

@export var desktop_player_scene: PackedScene = preload("uid://c7ib7q76huhy")
@export var vr_player_scene: PackedScene = preload("uid://vxxwgpbct06d")

@onready var spawn_point: Marker3D = get_node("/root/Main/World/SpawnPoint")

func _ready() -> void:
	var xr_interface = XRServer.find_interface("OpenXR")
	var player_instance: Node3D

	if xr_interface and xr_interface.initialize():
		print("VR Headset detected! Starting in vr!")
		player_instance = vr_player_scene.instantiate()
	else:
		print("No VR Headset found. Starting in desktop!")
		player_instance = desktop_player_scene.instantiate()

	player_instance.global_transform = spawn_point.global_transform
	add_child(player_instance)
