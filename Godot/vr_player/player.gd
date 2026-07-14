extends Node3D

var xr_interface: XRInterface
var vr: bool = true

func _ready():
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		print("OpenXR initialized successfully")
		get_viewport().use_xr = true
	else:
		print("OpenXR not initialized, please check if your headset is connected. Starting in desktop mode")
		get_node("Origin").visible = false
		vr = false
