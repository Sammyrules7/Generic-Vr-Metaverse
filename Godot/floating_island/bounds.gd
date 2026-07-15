extends Area3D

func _ready() -> void:
	connect("body_exited", on_body_leave)

func on_body_leave(Body) -> void:
	await get_tree().create_timer(2.5).timeout
	Body.position = Vector3(0,100,0)
