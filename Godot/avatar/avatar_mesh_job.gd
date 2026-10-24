class_name AvatarMeshJob
extends RefCounted
## Operates only on detached packed CPU arrays. Rendering resources stay on main.
var surfaces: Array[Dictionary] = []
var factor := 1.0
var task_id := -1
var elapsed_ms := 0.0
func run() -> void:
	var started := Time.get_ticks_usec()
	var transform := Transform3D(Basis.from_scale(Vector3.ONE * factor), Vector3.ZERO)
	for surface in surfaces:
		var arrays: Array = surface.arrays
		arrays[Mesh.ARRAY_VERTEX] = transform * (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)
		for shape: Array in surface.shapes:
			shape[Mesh.ARRAY_VERTEX] = transform * (shape[Mesh.ARRAY_VERTEX] as PackedVector3Array)
	elapsed_ms = (Time.get_ticks_usec() - started) / 1000.0
