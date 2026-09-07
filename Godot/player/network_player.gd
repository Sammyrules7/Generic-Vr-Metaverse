class_name NetworkPlayer
extends CharacterBody3D

# Both input modes use the same body, physics, and remote avatar. Controls exist
# only on the owning client, so a remote VR avatar never initializes local XR.
const DESKTOP_CONTROLS = preload("res://player/desktop_controls.tscn")
const VR_CONTROLS = preload("res://player/vr_controls.tscn")

var use_vr := false
var controls: PlayerControls
@onready var motor: CharacterMotor = $Motor


func _ready() -> void:
	$Avatar.visible = not is_multiplayer_authority()
	$Avatar/LeftHand.visible = use_vr
	$Avatar/RightHand.visible = use_vr
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
