class_name TrainingDummy
extends ActiveRagdoll
## A straw training dummy. It is the same active ragdoll as the player: it
## keeps its fists up, turns to face its opponent, can be knocked over, gets
## back up, and waddles back to its spot afterwards.

@export var opponent: ActiveRagdoll
@export var turn_speed := 2.5
@export var home_radius := 0.4

var home := Vector3.ZERO


func _ready() -> void:
	super()
	home = global_position
	elbow_pole_r = Vector3(0.8, -1.0, 0.2)
	elbow_pole_l = Vector3(-0.8, -1.0, 0.2)
	_add_target_mark()


func _think(delta: float) -> void:
	hand_target_r = Vector3(0.16, 1.45, -0.3)
	hand_target_l = Vector3(-0.16, 1.45, -0.3)
	var here := root_origin()
	var to_home := Vector3(home.x - here.x, 0.0, home.z - here.z)
	if to_home.length() > home_radius:
		move_input = to_home.normalized() * clampf(to_home.length() / 2.0, 0.3, 0.6)
	else:
		move_input = Vector3.ZERO
	if opponent and opponent.parts.has("pelvis"):
		var d: Vector3 = opponent.parts.pelvis.global_position - here
		if Vector2(d.x, d.z).length() > 0.3:
			var want := atan2(-d.x, -d.z)
			heading_yaw += clampf(wrapf(want - heading_yaw, -PI, PI), -turn_speed * delta, turn_speed * delta)


## A red bullseye on the chest so there is something to aim at.
func _add_target_mark() -> void:
	var chest: RigidBody3D = parts.chest
	var colors := [Color(0.85, 0.15, 0.12), Color(0.95, 0.9, 0.8), Color(0.85, 0.15, 0.12)]
	for i in colors.size():
		var ring := CylinderMesh.new()
		var r := 0.13 - i * 0.045
		ring.top_radius = r
		ring.bottom_radius = r
		ring.height = 0.01 + i * 0.004
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colors[i]
		mat.roughness = 0.9
		var mi := MeshInstance3D.new()
		mi.mesh = ring
		mi.material_override = mat
		mi.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.02, -0.2))
		chest.add_child(mi)
		_meshes[chest].append(mi)
