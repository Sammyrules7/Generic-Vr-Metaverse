extends Node
## F / B-Y operate furnishings, leaving murder controls untouched.
var _held := false
var _objects: Array[Node] = []
var _controls_cache: PlayerControls
var _touch_points: Dictionary = {}

func _ready() -> void:
	for object: Node in get_tree().get_nodes_in_group("briarwick_interactable"):
		if get_parent().is_ancestor_of(object):
			_objects.append(object)
			var tp := (object as Node3D).get_node_or_null("TouchPoint") as Node3D
			if tp != null:
				_touch_points[object] = tp

func _controls(camera: Camera3D) -> PlayerControls:
	if is_instance_valid(_controls_cache):
		return _controls_cache
	var node: Node = camera
	while node != null:
		if node is PlayerControls:
			_controls_cache = node
			return node
		node = node.get_parent()
	return null

func _target(camera: Camera3D, origin: Node3D) -> Node3D:
	var best: Node3D
	var best_score := -INF
	var controls := _controls(camera)
	var body_rid := controls.body.get_rid() if controls != null and is_instance_valid(controls.body) else RID()
	for object: Node3D in _objects:
		var touch: Node3D = _touch_points.get(object)
		if touch == null or not is_instance_valid(touch):
			continue
		var point: Vector3 = touch.global_position
		var offset := point - origin.global_position
		if camera.global_position.distance_to(point) > 2.6 or offset.length() > 2.6:
			continue
		var alignment := -origin.global_basis.z.dot(offset.normalized())
		if alignment < 0.90 and offset.length() > 0.3:
			continue
		var ray := PhysicsRayQueryParameters3D.create(origin.global_position, point, 1)
		if body_rid.is_valid():
			ray.exclude = [body_rid]
		var hit := camera.get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and hit.position.distance_to(point) > 0.32:
			continue
		var score := alignment - offset.length() * 0.08
		if score > best_score:
			best = object
			best_score = score
	return best

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or event.physical_keycode != KEY_F:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var controls := _controls(camera)
	if controls == null or not controls.input_enabled:
		return
	var object := _target(camera, camera)
	if object != null:
		object.activate()
		get_viewport().set_input_as_handled()

func _physics_process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var controls := _controls(camera)
	var pressed := false
	var target: Node3D = null
	if controls != null and controls.input_enabled:
		for hand in [controls.right_hand, controls.left_hand]:
			if hand is XRController3D and hand.get_is_active() and hand.is_button_pressed("by_button"):
				pressed = true
				if target == null:
					target = _target(camera, hand)
	if pressed and not _held and target != null:
		target.activate()
	_held = pressed
