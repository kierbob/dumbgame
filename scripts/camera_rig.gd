class_name CameraRig
extends Node3D
## Third-person orbit camera that follows the player's chest.
## The SpringArm3D child pulls the camera in when a wall gets in the way.

@export var target: ActiveRagdoll
@export var mouse_sensitivity := 0.0025
@export var height := 0.5
@export var follow_speed := 9.0

var yaw := 0.0
var pitch := -0.2


func _ready() -> void:
	top_level = true
	# Moved every rendered frame, so it must not be physics-interpolated.
	physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF
	if target:
		yaw = target.global_rotation.y
	snap.call_deferred()


func orbit(relative: Vector2) -> void:
	yaw = wrapf(yaw - relative.x * mouse_sensitivity, -PI, PI)
	pitch = clampf(pitch - relative.y * mouse_sensitivity, -1.2, 0.7)


func snap() -> void:
	if target and target.parts.has("chest"):
		global_position = _focus()
	rotation = Vector3(pitch, yaw, 0.0)


func _focus() -> Vector3:
	var chest: RigidBody3D = target.parts.chest
	return chest.get_global_transform_interpolated().origin + Vector3.UP * height


func _process(delta: float) -> void:
	if target == null or not target.parts.has("chest"):
		return
	global_position = global_position.lerp(_focus(), 1.0 - exp(-follow_speed * delta))
	rotation = Vector3(pitch, yaw, 0.0)
