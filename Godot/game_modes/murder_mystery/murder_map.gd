class_name MurderMap
extends Node

## A map supplies locations; it never owns roles, combat, timers, or networking.
@export var spawns_path: NodePath = ^"../GameSpawns"
@export var clues_path: NodePath = ^"../ClueSpawns"
@export var knives_path: NodePath = ^"../KnifeSpawns"
@export var table_path: NodePath = ^"../GameTable"


func valid() -> bool:
	return spawn_positions().size() >= 3 and get_node_or_null(table_path) is Node3D and get_node_or_null("../GameDisplay") is Node3D


func item_layout() -> Dictionary:
	var layout := {}
	for kind: String in ["clue", "knife"]:
		var group := get_node_or_null(clues_path if kind == "clue" else knives_path)
		if group == null:
			continue
		for marker: Node in group.get_children():
			if marker is Node3D:
				layout[kind + ":" + str(marker.name)] = {"kind": kind, "position": marker.global_position}
	return layout


func spawn_positions() -> Array[Vector3]:
	var points: Array[Vector3] = []
	var group := get_node_or_null(spawns_path)
	if group == null:
		return points
	for marker: Node in group.get_children():
		if marker is Node3D:
			points.append(marker.global_position)
	return points


func table_position() -> Vector3:
	return (get_node(table_path) as Node3D).global_position
