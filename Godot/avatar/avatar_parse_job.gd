class_name AvatarParseJob
extends RefCounted
## One isolated resource parser at a time. No active scene nodes are touched.
## Scene generation and GPU-facing consumer setup stay on the main thread.
var bytes := PackedByteArray()
var document: GLTFDocument
var state: GLTFState
var task_id := -1
var result := ERR_UNCONFIGURED
var elapsed_ms := 0.0
func run() -> void:
	var started := Time.get_ticks_usec()
	result = document.append_from_buffer(bytes, "", state, 8)
	elapsed_ms = (Time.get_ticks_usec() - started) / 1000.0
