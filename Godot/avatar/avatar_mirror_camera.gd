extends Camera3D
## Attach to a mirror's SubViewport camera to show the full local avatar.
## Reflection position/orientation and the mirror surface are owned by the world.

func _ready() -> void:
	AvatarView.configure_mirror_camera(self)
