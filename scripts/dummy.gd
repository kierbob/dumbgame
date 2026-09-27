class_name TrainingDummy
extends ActiveRagdoll
## A sparring partner in a kettle hat and a padded jack. It is the same
## active ragdoll as the player: it keeps its fists up, turns to face you,
## bleeds, can lose limbs, gets knocked over and back up, and waddles back to
## its spot. Press T to bring in a fresh one.

@export var opponent: ActiveRagdoll
@export var turn_speed := 2.5
@export var home_radius := 0.4

var home := Vector3.ZERO


func _ready() -> void:
	super()
	home = global_position
	elbow_pole_r = Vector3(0.8, -1.0, 0.2)
	elbow_pole_l = Vector3(-0.8, -1.0, 0.2)


func _think(delta: float) -> void:
	hand_target_r = Vector3(0.14, 1.36, -0.28)
	hand_target_l = Vector3(-0.14, 1.36, -0.28)
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
