class_name CameraRig
extends Node3D
## Close over-the-shoulder camera that follows the player's chest, with a
## first-person view from the head (V) and a lock-on that keeps the
## opponent in front of you (Tab).

## Render layer the player's own head is on, hidden in first person.
const HEAD_LAYER := 2

@export var target: ActiveRagdoll
@export var opponent: ActiveRagdoll
@export var mouse_sensitivity := 0.0022
@export var distance := 2.3
@export var shoulder_offset := -0.42
@export var height := 0.38
@export var follow_speed := 10.0

var yaw := 0.0
var pitch := -0.12
var first_person := false
var locked := false

@onready var _arm: SpringArm3D = $SpringArm3D
@onready var _camera: Camera3D = $SpringArm3D/Camera3D


func _ready() -> void:
	top_level = true
	# Moved every rendered frame, so it must not be physics-interpolated.
	physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF
	if target:
		yaw = target.global_rotation.y
	snap.call_deferred()


func orbit(relative: Vector2) -> void:
	yaw = wrapf(yaw - relative.x * mouse_sensitivity, -PI, PI)
	pitch = clampf(pitch - relative.y * mouse_sensitivity, -1.2, 0.9)


func toggle_lock() -> void:
	locked = not locked and opponent != null


## The world point under the crosshair (what a thrust should aim at).
func aim_point() -> Vector3:
	var from := _camera.global_position
	var forward := -_camera.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + forward * 6.0, 1 | 8)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit and from.distance_to(hit.position) > distance + 0.8:
		return hit.position
	return from + forward * (distance + 3.0)


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
	if locked and opponent and opponent.parts.has("chest") and not opponent.is_dead():
		var to: Vector3 = opponent.parts.chest.global_position - global_position
		var want := atan2(-to.x, -to.z)
		yaw = lerp_angle(yaw, want, 1.0 - exp(-6.0 * delta))
	elif locked:
		locked = false
	rotation = Vector3(pitch, yaw, 0.0)
	if first_person and target.parts.has("head") and not target.is_severed("head"):
		var head: RigidBody3D = target.parts.head
		global_position = head.get_global_transform_interpolated().origin + Vector3.UP * 0.04 \
				+ Basis(Vector3.UP, yaw) * Vector3(0, 0, -0.08)
		_arm.position = Vector3.ZERO
		_arm.spring_length = 0.0
		_camera.cull_mask = 0xFFFFF & ~(1 << (HEAD_LAYER - 1))
		_camera.fov = 80.0
	else:
		global_position = global_position.lerp(_focus(), 1.0 - exp(-follow_speed * delta))
		_arm.position = Vector3(shoulder_offset, 0, 0)
		_arm.spring_length = distance
		_camera.cull_mask = 0xFFFFF
		_camera.fov = 70.0
