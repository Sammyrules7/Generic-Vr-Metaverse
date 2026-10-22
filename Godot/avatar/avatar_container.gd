class_name AvatarContainer
extends Node3D
## Stable pose/voice anchors outlive every replaceable visual model.

signal avatar_loaded(id: String)
signal avatar_failed(id: String, reason: String)

var avatar_id := "default"
var model: Node3D
var _driver: Node3D
var _request: AvatarLoadRequest
var _generation := 0
var _springs: Array[SpringBoneSimulator3D] = []
var _previous_body := Vector3.ZERO
var _have_previous := false
var _local := false


func _ready() -> void:
	_local = get_parent().is_multiplayer_authority()
	# Controls sample before this; visuals follow tracking at display frame rate.
	process_priority = 5
	AvatarService.springs_changed.connect(_set_springs_enabled)
	if _local:
		AvatarService.selection_changed.connect(set_avatar)
	_update_fallback()


func set_avatar(id: String) -> void:
	if not AvatarCatalog.has_avatar(id):
		id = "default"
	if id == avatar_id and (model != null or _request != null):
		return
	avatar_id = id
	_generation += 1
	var generation := _generation
	if _request != null:
		_request.release()
		_request = null
	if id == "default":
		_clear_model()
		_update_fallback()
		avatar_loaded.emit(id)
		return
	var request := AvatarService.acquire(id)
	_request = request
	if not request.finished:
		await request.completed
	if generation != _generation or not is_inside_tree() or request.released:
		return
	if request.scene == null:
		var reason := request.error
		request.release()
		_request = null
		avatar_failed.emit(id, reason)
		return
	var replacement := request.scene.instantiate() as Node3D
	request.release()
	_request = null
	if replacement == null:
		avatar_failed.emit(id, "Avatar scene is invalid")
		return
	_clear_model()
	model = replacement
	model.name = "Model"
	add_child(model)
	_driver = Node3D.new()
	_driver.set_script(load("res://avatar/avatar_rig_driver.gd"))
	add_child(_driver)
	_driver.configure(model, $Head, $LeftHand, $RightHand, _local, get_parent().use_vr)
	if _local:
		AvatarFirstPerson.use_tracked_hands(model, get_parent().use_vr)
	_springs = load("res://avatar/avatar_springs.gd").install(model)
	_set_springs_enabled(PlayerProfile.spring_bones_enabled)
	_update_fallback()
	avatar_loaded.emit(id)


func _process(_delta: float) -> void:
	var player := get_parent() as NetworkPlayer
	if _local and player.controls != null:
		var controls := player.controls
		$Head.transform = controls.pose(controls.head)
		if player.use_vr:
			$LeftHand.transform = controls.hand_pose("left")
			$RightHand.transform = controls.hand_pose("right")
	# Native verlet history must be reset after teleport/respawn or long jumps.
	if _have_previous and player.global_position.distance_to(_previous_body) > 0.5:
		for simulator in _springs:
			if is_instance_valid(simulator):
				simulator.reset()
	_previous_body = player.global_position
	_have_previous = true


func control_mode_changed() -> void:
	if is_instance_valid(_driver):
		_driver.set_control_mode(get_parent().use_vr)
	if _local and is_instance_valid(model):
		AvatarFirstPerson.use_tracked_hands(model, get_parent().use_vr)
	_update_fallback()


func _set_springs_enabled(enabled: bool) -> void:
	for simulator in _springs:
		if is_instance_valid(simulator):
			simulator.active = enabled
			simulator.reset()


func _update_fallback() -> void:
	$Body.visible = model == null
	$Head.visible = model == null and not _local
	$LeftHand.visible = model == null and not _local and get_parent().use_vr
	$RightHand.visible = model == null and not _local and get_parent().use_vr


func _clear_model() -> void:
	_springs.clear()
	if is_instance_valid(_driver):
		_driver.free()
	_driver = null
	if is_instance_valid(model):
		model.free()
	model = null


func _exit_tree() -> void:
	_generation += 1
	if _request != null:
		_request.release()
		_request = null
