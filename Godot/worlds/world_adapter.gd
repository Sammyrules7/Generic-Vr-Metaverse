extends RefCounted
## Bundled world contract: Node3D root and a direct Marker3D SpawnPoint after
## readiness/preparation. Optional incremental preparation must support cancellation.
## Methods take no arguments; progress, when supplied, is one float in [0, 1].

static func validate(world: Node3D) -> bool:
	if world == null:
		return false
	for method in ["prepare_world", "cancel_world_preparation"]:
		if world.has_method(method):
			for description in world.get_method_list():
				if description.name == method and not description.args.is_empty():
					push_error("World adapter method must take no arguments: " + method)
					return false
	if world.has_method("prepare_world") and not world.has_method("cancel_world_preparation"):
		push_error("Incremental worlds must support cancel_world_preparation")
		return false
	for description in world.get_signal_list():
		if description.name == "world_build_progress":
			if description.args.size() != 1 or description.args[0].type != TYPE_FLOAT:
				push_error("World progress must supply one float")
				return false
	return true


static func spawn_point(world: Node3D) -> Marker3D:
	var spawn := world.get_node_or_null("SpawnPoint") as Marker3D
	if spawn == null:
		push_error("World adapter requires a direct Marker3D SpawnPoint")
	return spawn
