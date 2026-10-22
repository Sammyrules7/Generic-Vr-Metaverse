class_name AvatarLoadRequest
extends RefCounted
## A consumer's lease on a shared load; release when switching or exiting.

signal completed

var bytes_only := false
var finished := false
var scene: PackedScene
var error := ""
var released := false
var _on_release: Callable


func release() -> void:
	if released:
		return
	released = true
	scene = null
	if _on_release.is_valid():
		_on_release.call()
	_on_release = Callable()
	if not finished:
		finished = true
		error = "Cancelled"
		completed.emit()


func finish(result: PackedScene, reason := "") -> void:
	if released or finished:
		return
	scene = result
	error = reason
	finished = true
	completed.emit()
