class_name NetworkPlayer
extends CharacterBody3D

signal controls_changed

# Both input modes use the same body, physics, and remote avatar. Controls exist
# only on the owning client, so a remote VR avatar never initializes local XR.
const DESKTOP_CONTROLS = preload("res://player/desktop_controls.tscn")
const VR_CONTROLS = preload("res://player/vr_controls.tscn")

var use_vr := false
var controls: PlayerControls
var avatar_replication: PlayerReplication
var _avatar_progress: MeshInstance3D
var _avatar_progress_material: ShaderMaterial
@onready var motor: CharacterMotor = $Motor


func _ready() -> void:
	if is_multiplayer_authority():
		controls = (VR_CONTROLS if use_vr else DESKTOP_CONTROLS).instantiate()
		add_child(controls)
		motor.input_source = controls
	else:
		# Remote poses are supplied by their owner; don't simulate collisions twice.
		$Collider.disabled = true
		motor.set_physics_process(false)


func apply_pose(body_pose: Transform3D, head_pose: Transform3D, left_pose: Transform3D, right_pose: Transform3D) -> void:
	# The body is in world space; tracked parts are relative to that body, making
	# the wire format independent of the desktop camera or XR rig's node layout.
	global_transform = body_pose
	$Avatar/Head.transform = head_pose
	$Avatar/LeftHand.transform = left_pose
	$Avatar/RightHand.transform = right_pose


func set_control_mode(vr: bool) -> void:
	if use_vr == vr:
		return
	# WebXR can finish starting after the world has spawned its desktop rig.
	var was_enabled := controls.input_enabled
	controls.free()
	use_vr = vr
	controls = (VR_CONTROLS if vr else DESKTOP_CONTROLS).instantiate()
	add_child(controls)
	controls.input_enabled = was_enabled
	motor.input_source = controls
	Networking.player_replication.set_local_player(self)
	controls_changed.emit()
	$Avatar.control_mode_changed()


func set_avatar(id: String) -> void:
	$Avatar.set_avatar(id)


func set_display_name(display_name: String) -> void:
	var label := get_node_or_null("NameTag") as Label3D
	if label == null:
		label = Label3D.new()
		label.name = "NameTag"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 48
		label.pixel_size = 0.004
		label.position.y = 2.15
		add_child(label)
	label.text = display_name if not display_name.is_empty() else "Explorer"
	label.visible = not is_multiplayer_authority()


func _process(_delta: float) -> void:
	if avatar_replication == null or is_multiplayer_authority():
		return
	var progress := avatar_replication.avatar_progress(get_multiplayer_authority())
	var pending := not progress.is_empty() or $Avatar._request != null
	if _avatar_progress == null and pending:
		_avatar_progress = MeshInstance3D.new()
		_avatar_progress.name = "AvatarProgress"
		_avatar_progress.position.y = 2.02
		var quad := QuadMesh.new()
		quad.size = Vector2(0.65, 0.025)
		_avatar_progress.mesh = quad
		_avatar_progress.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_avatar_progress_material = ShaderMaterial.new()
		_avatar_progress_material.shader = preload("res://avatar/avatar_progress.gdshader")
		_avatar_progress.material_override = _avatar_progress_material
		add_child(_avatar_progress)
	if _avatar_progress == null:
		return
	_avatar_progress.visible = pending
	if pending:
		var total := int(progress.get("total", 0))
		var measurable: bool = total > 0 and not progress.get("preparing", false)
		_avatar_progress_material.set_shader_parameter("fraction", float(progress.get("downloaded", 0)) / total if measurable else -1.0)
