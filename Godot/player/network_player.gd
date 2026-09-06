class_name NetworkPlayer
extends CharacterBody3D

# Both input modes use the same body, physics, and remote avatar. Controls exist
# only on the owning client, so a remote VR avatar never initializes local XR.
const DESKTOP_CONTROLS = preload("res://player/desktop_controls.tscn")
const VR_CONTROLS = preload("res://player/vr_controls.tscn")

@export var speed := 5.0
@export var acceleration := 100.0
@export var jump_height := 1.0

var use_vr := false
var controls: PlayerControls
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	$Avatar.visible = not is_multiplayer_authority()
	$Avatar/LeftHand.visible = use_vr
	$Avatar/RightHand.visible = use_vr
	if is_multiplayer_authority():
		controls = (VR_CONTROLS if use_vr else DESKTOP_CONTROLS).instantiate()
		add_child(controls)
	else:
		# Remote poses are supplied by their owner; don't simulate collisions twice.
		$Collider.disabled = true


func _physics_process(delta: float) -> void:
	if controls == null:
		return
	controls.update(delta)
	velocity.x = move_toward(velocity.x, controls.movement.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, controls.movement.z * speed, acceleration * delta)
	if is_on_floor():
		velocity.y = 0
	else:
		velocity.y -= gravity * delta
	if controls.consume_jump() and is_on_floor():
		velocity.y = sqrt(2 * jump_height * gravity)
	move_and_slide()


func apply_pose(body_pose: Transform3D, head_pose: Transform3D, left_pose: Transform3D, right_pose: Transform3D) -> void:
	# The body is in world space; tracked parts are relative to that body, making
	# the wire format independent of the desktop camera or XR rig's node layout.
	global_transform = body_pose
	$Avatar/Head.transform = head_pose
	$Avatar/LeftHand.transform = left_pose
	$Avatar/RightHand.transform = right_pose
