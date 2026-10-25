class_name AvatarInstanceJob
extends RefCounted
## Service-owned detached instantiation. Cancellation is inspected only on main.
var scene: PackedScene
var model: Node3D
var callback: Callable
var cancelled := false
var task_id := -1
var elapsed_ms := 0.0
var id := ""
func run() -> void:
	var started := Time.get_ticks_usec()
	model = scene.instantiate() as Node3D
	elapsed_ms = (Time.get_ticks_usec() - started) / 1000.0
func take_model() -> Node3D:
	var value := model
	model = null
	return value
func cancel() -> void:
	cancelled = true
