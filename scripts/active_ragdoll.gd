class_name ActiveRagdoll
extends Node3D
## A physics-driven human fighter in the spirit of Half Sword.
##
## Every body part is a RigidBody3D pinned to its parent with a ball joint.
## Nothing is animated. "Muscles" apply PD torques that pull each part toward
## a target pose, a hover spring carries the body's weight at the hips, and
## capped balance torques keep the torso upright. The legs plant their feet
## and step with two-bone IK, so a shove turns into stumbling footwork.
##
## Wounds are physical too: cuts bleed, damaged limbs lose muscle strength
## and go limp, hard enough cuts sever a limb at its joint, and blood loss or
## a ruined head or chest kills.
##
## Subclasses steer the body by overriding _think() and writing the intent
## variables (heading_yaw, move_input, hand targets, ...) every physics tick.

signal knocked_down
signal got_up
signal died
## kind is "cut", "stab", "blunt" or "armor" (a blade stopped by armour).
signal wounded(body: RigidBody3D, damage: float, kind: String, point: Vector3)
signal severed(body: RigidBody3D)

enum State { ACTIVE, KNOCKED, RECOVERING, DEAD }

const GRAVITY := 9.8
## Pelvis height above the soles in the rest pose.
const PELVIS_HEIGHT := 0.95
const UPPER_ARM_LENGTH := 0.27
## Elbow to the centre of the fist (where a weapon is held).
const LOWER_ARM_LENGTH := 0.31
const THIGH_LENGTH := 0.4
const SHIN_LENGTH := 0.41
const ANKLE_HEIGHT := 0.09
const SHOULDER_R := Vector3(0.215, 1.44, 0.0)
const SHOULDER_L := Vector3(-0.215, 1.44, 0.0)
const HAND_R := Vector3(0.24, 0.86, 0.0)
const HAND_L := Vector3(-0.24, 0.86, 0.0)
const HIP_R := Vector3(0.1, 0.9, 0.0)
const HIP_L := Vector3(-0.1, 0.9, 0.0)
const KICK_TIME := 0.5
const SEVERABLE := ["head", "arm_upper_r", "arm_upper_l", "arm_lower_r", "arm_lower_l",
		"leg_upper_r", "leg_upper_l", "leg_lower_r", "leg_lower_l"]

@export_group("Outfit")
@export var skin_color := Color(0.74, 0.56, 0.44)
@export var hair_color := Color(0.14, 0.1, 0.07)
@export var shirt_color := Color(0.66, 0.6, 0.48)
@export var trousers_color := Color(0.24, 0.21, 0.19)
@export var boots_color := Color(0.19, 0.12, 0.08)
@export var gloves_color := Color(0.28, 0.18, 0.11)
## Steel kettle hat. Stops most of any cut to the head.
@export var helmet := false
## Quilted gambeson. Soaks up part of every cut to the torso and arms.
@export var padded := false
## Render layers for the head, so a first-person camera can hide it.
@export_flags_3d_render var head_layers := 1

@export_group("Physics layers")
@export_flags_3d_physics var body_layer := 2
@export_flags_3d_physics var body_mask := 11

@export_group("Movement")
@export var walk_speed := 2.3
@export var sprint_speed := 4.4
@export var ground_accel := 14.0
@export var air_accel := 3.0
## Target distance from the pelvis to the ground while standing.
@export var hover_height := 0.91
@export var crouch_depth := 0.24
@export var hover_frequency := 9.0
## How far a foot may drift from where it wants to be before it steps.
@export var step_trigger := 0.17
@export var step_time := 0.24
@export var dodge_speed := 3.3

@export_group("Muscles")
@export var balance_frequency := 6.0
@export var balance_torque := 320.0
@export var limb_frequency := 14.0
## Muscle strength left over while knocked down (0 = completely floppy).
@export var limp_strength := 0.06
@export var grip_force := 560.0
@export var wrist_torque := 50.0
## How much balance a full-speed weapon swing costs (0..1).
@export var swing_wobble := 0.65
@export var knock_tilt_degrees := 65.0
@export var knock_duration := 1.8
@export var recover_duration := 1.2
## Impact speed (m/s) that knocks this body over outright.
@export var knockout_hit_speed := 15.0

@export_group("Health")
@export var max_blood := 100.0
## Damage from a single cut that takes a limb off.
@export var sever_damage := 60.0

# --- Intent. Written by subclasses in _think(). ---------------------------
var heading_yaw := 0.0
## World-space horizontal move direction, length 0..1.
var move_input := Vector3.ZERO
var sprinting := false
var crouching := false
var limp := false
## Hand targets in root space: x right, y up from the soles, -z forward.
var hand_target_r := Vector3(0.24, 0.9, -0.05)
var hand_target_l := Vector3(-0.24, 0.9, -0.05)
## Direction each elbow should point, in root space.
var elbow_pole_r := Vector3(0.6, -1.0, 0.5)
var elbow_pole_l := Vector3(-0.6, -1.0, 0.5)
## Chest twist in radians (positive turns the shoulders to the right).
var chest_twist := 0.0
## Look up/down in radians, used for the head.
var look_pitch := 0.0
## Wanted world orientation of the held weapon (y = blade, z = edge).
var sword_target := Basis.IDENTITY
## Off hand grabs the blade (the half-sword grip).
var half_sword := false

# --- State ---------------------------------------------------------------
var state := State.ACTIVE
## 0..1 overall muscle strength (0 while knocked down).
var strength := 1.0
## 0..1 temporary weakness after taking a hit.
var stagger := 0.0
var grounded := false
var parts := {}
var joints := {}
var health := {}
var max_health := {}
var bleed := {}
var blood := 100.0
var total_mass := 0.0
var sword: Sword = null
var half_sword_held := false

var _specs: Array = []
var _children := {}
var _severed := {}
var _armor := {}
var _meshes := {}
var _bleeders := {}
var _built: Array[Node] = []
var _exclude: Array[RID] = []
var _spawn := Transform3D.IDENTITY
var _state_time := 0.0
var _tilt_time := 0.0
var _ground_distance := INF
var _ground_y := 0.0
var _feet := {}
var _kick_t := 0.0
var _kick_hit := false
var _dodge_cooldown := 0.0
var _drip_timer := 0.0
var _sword_joint: Node = null
var _half_joint: Node = null
var _has_prev_sword_target := false
var _prev_grip_target := Vector3.ZERO
var _prev_sword_q := Quaternion.IDENTITY
var _grip_target_velocity := Vector3.ZERO
var _sword_target_spin := Vector3.ZERO


func _ready() -> void:
	_spawn = global_transform
	heading_yaw = global_rotation.y
	_build()


## Override to steer the body. Called at the start of every physics tick.
func _think(_delta: float) -> void:
	pass


func is_down() -> bool:
	return state != State.ACTIVE


func is_dead() -> bool:
	return state == State.DEAD


func is_severed(part_name: String) -> bool:
	return _severed.has(part_name)


## Root frame origin: under the pelvis, at sole level.
func root_origin() -> Vector3:
	var p: Vector3 = parts.pelvis.global_position
	return Vector3(p.x, p.y - PELVIS_HEIGHT, p.z)


func heading_quat() -> Quaternion:
	return Quaternion(Vector3.UP, heading_yaw)


func root_to_world(local: Vector3) -> Vector3:
	return root_origin() + heading_quat() * local


func center_of_mass_velocity() -> Vector3:
	var v := Vector3.ZERO
	var m := 0.0
	for part_name: String in parts:
		if _severed.has(part_name):
			continue
		var body: RigidBody3D = parts[part_name]
		v += body.linear_velocity * body.mass
		m += body.mass
	return v / maxf(m, 0.001)


func knock_down() -> void:
	if state == State.DEAD:
		return
	if state == State.KNOCKED:
		_state_time = 0.0
		return
	state = State.KNOCKED
	_state_time = 0.0
	strength = 0.0
	_kick_t = 0.0
	knocked_down.emit()


func die() -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	strength = 0.0
	died.emit()


func kick() -> void:
	if state == State.ACTIVE and grounded and _kick_t <= 0.0 and not _severed.has("leg_lower_r") \
			and not _severed.has("leg_upper_r"):
		_kick_t = 0.0001
		_kick_hit = false


## Quick sidestep or hop back along a world-space horizontal direction.
func dodge(direction: Vector3) -> void:
	if state != State.ACTIVE or not grounded or _dodge_cooldown > 0.0 or direction.length_squared() < 0.01:
		return
	_dodge_cooldown = 0.7
	var dv := direction.normalized() * dodge_speed
	for part_name: String in parts:
		if not _severed.has(part_name):
			parts[part_name].apply_central_impulse(dv * parts[part_name].mass)


## Applies a weapon (or kick) impact to one of our body parts.
## speed is the closing speed in m/s, edge is 1.0 for a clean edge-on cut
## and 0.0 for a flat or blunt blow, pierce is 1.0 for a point-first thrust.
## Returns what happened.
func receive_hit(body: RigidBody3D, point: Vector3, direction: Vector3, speed: float,
		edge: float, weapon_mass: float, pierce := 0.0) -> Dictionary:
	var part_name := String(body.name)
	if not health.has(part_name):
		return {}
	var energy := 0.5 * weapon_mass * speed * speed
	var stabbing := pierce >= 0.75 and speed >= 2.5
	var cutting := not stabbing and edge >= 0.55 and speed >= 4.0
	var kind := "stab" if stabbing else ("cut" if cutting else "blunt")
	var damage := energy * 0.3 * (lerpf(0.5, 1.3, edge) if cutting else 0.4)
	if stabbing:
		# All the energy goes into one small point.
		damage = energy * 0.3 * 2.2
	var armor: float = _armor.get(part_name, 0.0)
	if (cutting or stabbing) and armor > 0.0:
		# Padding stops cuts better than thrusts; steel stops both.
		damage *= 1.0 - (armor * 0.6 if stabbing and armor < 0.6 else armor)
		if armor >= 0.6:
			kind = "armor"
	if part_name == "head":
		damage *= 1.4
	health[part_name] -= damage

	var normal := _surface_normal(body, point)
	if kind == "cut" or kind == "stab":
		bleed[part_name] = minf(bleed[part_name] + damage * (0.04 if kind == "stab" else 0.025), 4.0)
		Gore.burst(get_parent(), point, (direction.normalized() + normal).normalized(),
				int(clampf(damage * 0.6, 6.0, 45.0)), clampf(speed * 0.35, 1.5, 5.0))
		Gore.stain(body, point, normal, clampf(0.06 + damage * 0.002, 0.07, 0.2), 0.12)
		_open_wound(part_name, point)

	stagger = clampf(maxf(stagger, speed / 20.0 + (0.15 if kind != "cut" else 0.0)), 0.0, 0.9)
	var head_blow := part_name == "head" and kind != "cut" and speed >= knockout_hit_speed * 0.6
	if speed >= knockout_hit_speed or head_blow:
		knock_down()
	if kind == "cut" and part_name in SEVERABLE and not _severed.has(part_name) \
			and (damage >= sever_damage or health[part_name] <= 0.0):
		sever(part_name)
	if health.get("head", 1.0) <= 0.0 or health.get("chest", 1.0) <= 0.0:
		die()
	wounded.emit(body, damage, kind, point)
	return {"damage": damage, "kind": kind, "part": part_name}


## Cuts a limb (and everything hanging off it) loose at its joint.
func sever(part_name: String) -> void:
	if _severed.has(part_name) or not joints.has(part_name):
		return
	var joint: PinJoint3D = joints[part_name]
	var stump := joint.global_position
	joint.queue_free()
	joints.erase(part_name)
	_mark_severed(part_name)
	var parent_name := _parent_of(part_name)
	bleed[parent_name] = bleed.get(parent_name, 0.0) + 3.0
	bleed[part_name] = bleed.get(part_name, 0.0) + 1.5
	_open_wound(parent_name, stump)
	_open_wound(part_name, stump)
	Gore.burst(get_parent(), stump, Vector3.UP, 60, 4.0)
	if part_name == "arm_lower_l" or part_name == "arm_upper_l":
		_release_half_sword()
	severed.emit(parts[part_name])
	if part_name == "head":
		die()
	elif part_name.begins_with("leg"):
		knock_down()


## Rebuilds the body from scratch at the spawn point, fully healed.
func respawn() -> void:
	for node in _built:
		if is_instance_valid(node):
			node.queue_free()
	_built.clear()
	parts.clear()
	joints.clear()
	_severed.clear()
	_bleeders.clear()
	_meshes.clear()
	_children.clear()
	_sword_joint = null
	_half_joint = null
	half_sword_held = false
	_exclude.clear()
	total_mass = 0.0
	heading_yaw = _spawn.basis.get_euler().y
	state = State.ACTIVE
	strength = 1.0
	stagger = 0.0
	_tilt_time = 0.0
	_kick_t = 0.0
	_has_prev_sword_target = false
	_grip_target_velocity = Vector3.ZERO
	_sword_target_spin = Vector3.ZERO
	_build()
	if sword:
		_attach_sword()


# --- Construction --------------------------------------------------------

func _part_specs() -> Array:
	var specs := [
		{"name": "pelvis", "parent": "", "a": Vector3(-0.09, 0.95, 0), "b": Vector3(0.09, 0.95, 0),
			"r": 0.13, "mass": 11.0, "mat": "trousers", "hp": 120.0, "scale": Vector3(0.9, 0.85, 0.72)},
		{"name": "chest", "parent": "pelvis", "joint": Vector3(0, 1.05, 0),
			"a": Vector3(0, 1.15, 0), "b": Vector3(0, 1.37, 0), "r": 0.165, "mass": 18.0,
			"mat": "shirt", "hp": 150.0, "scale": Vector3(1.22, 1.0, 0.8)},
		{"name": "head", "parent": "chest", "joint": Vector3(0, 1.53, 0),
			"a": Vector3(0, 1.655, 0), "b": Vector3(0, 1.665, 0), "r": 0.108, "mass": 5.0,
			"mat": "skin", "hp": 60.0, "scale": Vector3(0.9, 1.08, 1.0)},
	]
	for side: int in [1, -1]:
		var s := "_r" if side > 0 else "_l"
		var x := 0.215 * side
		var lx := 0.1 * side
		specs.append({"name": "arm_upper" + s, "parent": "chest", "joint": Vector3(x, 1.45, 0),
			"a": Vector3(x, 1.43, 0), "b": Vector3(x + 0.01 * side, 1.19, 0), "r": 0.05, "mass": 2.2,
			"mat": "shirt", "hp": 80.0})
		specs.append({"name": "arm_lower" + s, "parent": "arm_upper" + s, "joint": Vector3(x + 0.015 * side, 1.17, 0),
			"a": Vector3(x + 0.02 * side, 1.15, 0), "b": Vector3(x + 0.025 * side, 0.93, 0), "r": 0.042,
			"mass": 1.5, "mat": "shirt", "hp": 70.0, "hand": [Vector3(0.24 * side, 0.86, 0), 0.045]})
		specs.append({"name": "leg_upper" + s, "parent": "pelvis", "joint": Vector3(lx, 0.9, 0),
			"a": Vector3(lx, 0.87, 0), "b": Vector3(lx, 0.53, 0), "r": 0.075, "mass": 7.0,
			"mat": "trousers", "hp": 100.0})
		specs.append({"name": "leg_lower" + s, "parent": "leg_upper" + s, "joint": Vector3(lx, 0.5, 0),
			"a": Vector3(lx, 0.47, 0), "b": Vector3(lx, 0.14, 0), "r": 0.058, "mass": 3.6,
			"mat": "trousers", "hp": 90.0, "foot": [Vector3(lx, 0.045, -0.045), Vector3(0.1, 0.09, 0.26)]})
	return specs


func _build() -> void:
	_specs = _part_specs()
	var mats := {
		"skin": Looks.skin(skin_color),
		"hair": Looks.cloth(hair_color, 0.8, 0.2),
		"shirt": Looks.cloth(shirt_color, 0.95, 0.12 if padded else 0.08),
		"trousers": Looks.cloth(trousers_color),
		"boots": Looks.cloth(boots_color, 0.6, 0.05),
		"gloves": Looks.cloth(gloves_color, 0.65, 0.05),
		"steel": Looks.steel(),
	}
	var phys := PhysicsMaterial.new()
	phys.friction = 0.9

	for spec: Dictionary in _specs:
		var a: Vector3 = spec.a
		var b: Vector3 = spec.b
		var r: float = spec.r
		var mass: float = spec.mass
		var part_name: String = spec.name
		var mid := (a + b) * 0.5
		var bone := b - a
		var length := bone.length()
		var dir := bone / length
		if dir.y < 0.0:
			dir = -dir

		var body := RigidBody3D.new()
		body.name = part_name
		body.top_level = true
		body.mass = mass
		body.collision_layer = body_layer
		body.collision_mask = body_mask
		body.physics_material_override = phys
		body.can_sleep = false
		body.angular_damp = 1.0
		body.linear_damp = 0.05
		body.set_meta("ragdoll", self)
		body.set_meta("rest_offset", mid)
		if part_name.begins_with("leg_lower"):
			body.contact_monitor = true
			body.max_contacts_reported = 4
		# Explicit inertia (capsule approximated as a cylinder, padded for
		# stability) so the PD muscles know exactly what they are pushing.
		var h := length + r * 1.4
		var i_axis := maxf(0.5 * mass * r * r, 0.004) * 1.5
		var i_perp := maxf(mass * (3.0 * r * r + h * h) / 12.0, 0.004) * 1.5
		var along_x := absf(dir.x) > 0.5
		body.inertia = Vector3(i_axis, i_perp, i_perp) if along_x else Vector3(i_perp, i_axis, i_perp)

		var meshes: Array[MeshInstance3D] = []
		var shape_basis := Basis(_arc(Vector3.UP, dir))
		var capsule := CapsuleShape3D.new()
		capsule.radius = r
		capsule.height = length + 2.0 * r
		_add_shape(body, capsule, Transform3D(shape_basis, Vector3.ZERO))
		var cmesh := CapsuleMesh.new()
		cmesh.radius = r
		cmesh.height = length + 2.0 * r
		var scale: Vector3 = spec.get("scale", Vector3.ONE)
		meshes.append(_add_mesh(body, cmesh, Transform3D(shape_basis.scaled_local(scale), Vector3.ZERO), mats[spec.mat]))

		if spec.has("hand"):
			var c: Vector3 = spec.hand[0]
			var hr: float = spec.hand[1]
			var sphere := SphereShape3D.new()
			sphere.radius = hr
			_add_shape(body, sphere, Transform3D(Basis.IDENTITY, c - mid))
			var fist := SphereMesh.new()
			fist.radius = hr
			fist.height = hr * 2.0
			meshes.append(_add_mesh(body, fist, Transform3D(Basis.from_scale(Vector3(0.85, 1.2, 1.0)), c - mid), mats.gloves))
			body.set_meta("hand_offset", c - mid)
		if spec.has("foot"):
			var c: Vector3 = spec.foot[0]
			var size: Vector3 = spec.foot[1]
			var box := BoxShape3D.new()
			box.size = size
			_add_shape(body, box, Transform3D(Basis.IDENTITY, c - mid))
			var boot := BoxMesh.new()
			boot.size = size
			meshes.append(_add_mesh(body, boot, Transform3D(Basis.IDENTITY, c - mid), mats.boots))
			var shaft := CylinderMesh.new()
			shaft.top_radius = r + 0.012
			shaft.bottom_radius = r + 0.008
			shaft.height = 0.2
			meshes.append(_add_mesh(body, shaft, Transform3D(Basis.IDENTITY, Vector3(0, 0.2 - mid.y, 0)), mats.boots))
		if part_name == "pelvis":
			var belt := CylinderMesh.new()
			belt.top_radius = 0.15
			belt.bottom_radius = 0.15
			belt.height = 0.05
			meshes.append(_add_mesh(body, belt, Transform3D(Basis.from_scale(Vector3(1.25, 1, 0.85)), Vector3(0, 0.07, 0)), mats.gloves))
		if part_name == "head":
			_dress_head(body, meshes, mats)

		add_child(body)
		body.global_transform = global_transform * Transform3D(Basis.IDENTITY, mid)
		parts[part_name] = body
		_meshes[body] = meshes
		_built.append(body)
		_exclude.append(body.get_rid())
		total_mass += mass
		max_health[part_name] = spec.hp
		health[part_name] = spec.hp
		bleed[part_name] = 0.0
		_armor[part_name] = 0.0
		if padded and part_name in ["chest", "arm_upper_r", "arm_upper_l", "pelvis"]:
			_armor[part_name] = 0.35
		if helmet and part_name == "head":
			_armor[part_name] = 0.85
		_children[spec.parent] = _children.get(spec.parent, []) + [part_name]

	for spec: Dictionary in _specs:
		if spec.parent == "":
			continue
		var joint := PinJoint3D.new()
		joint.name = "joint_" + spec.name
		joint.top_level = true
		add_child(joint)
		joint.global_transform = global_transform * Transform3D(Basis.IDENTITY, spec.joint)
		joint.node_a = joint.get_path_to(parts[spec.parent])
		joint.node_b = joint.get_path_to(parts[spec.name])
		joints[spec.name] = joint
		_built.append(joint)

	# The two arms pass right by each other when both hands hold the weapon.
	for right: String in ["arm_upper_r", "arm_lower_r"]:
		for left: String in ["arm_upper_l", "arm_lower_l"]:
			parts[right].add_collision_exception_with(parts[left])

	blood = max_blood
	_reset_feet()


func _dress_head(body: RigidBody3D, meshes: Array[MeshInstance3D], mats: Dictionary) -> void:
	var neck := CapsuleMesh.new()
	neck.radius = 0.048
	neck.height = 0.16
	meshes.append(_add_mesh(body, neck, Transform3D(Basis.IDENTITY, Vector3(0, -0.12, 0.005)), mats.skin))
	var nose := BoxMesh.new()
	nose.size = Vector3(0.024, 0.04, 0.03)
	meshes.append(_add_mesh(body, nose, Transform3D(Basis.IDENTITY, Vector3(0, -0.005, -0.103)), mats.skin))
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.09, 0.06, 0.04)
	eye_mat.roughness = 0.3
	for ex: float in [-0.036, 0.036]:
		var eye := SphereMesh.new()
		eye.radius = 0.012
		eye.height = 0.016
		meshes.append(_add_mesh(body, eye, Transform3D(Basis.IDENTITY, Vector3(ex, 0.012, -0.096)), eye_mat))
	var brow := BoxMesh.new()
	brow.size = Vector3(0.12, 0.018, 0.02)
	meshes.append(_add_mesh(body, brow, Transform3D(Basis.IDENTITY, Vector3(0, 0.03, -0.094)), mats.skin))
	if helmet:
		var dome := SphereMesh.new()
		dome.radius = 0.128
		dome.height = 0.128
		dome.is_hemisphere = true
		meshes.append(_add_mesh(body, dome, Transform3D(Basis.from_scale(Vector3(1, 1.15, 1.05)), Vector3(0, 0.035, 0.005)), mats.steel))
		var brim := CylinderMesh.new()
		brim.top_radius = 0.205
		brim.bottom_radius = 0.2
		brim.height = 0.012
		meshes.append(_add_mesh(body, brim, Transform3D(Basis(Vector3.RIGHT, 0.08), Vector3(0, 0.035, 0.0)), mats.steel))
	else:
		var hair := SphereMesh.new()
		hair.radius = 0.113
		hair.height = 0.17
		meshes.append(_add_mesh(body, hair, Transform3D(Basis.IDENTITY, Vector3(0, 0.035, 0.012)), mats.hair))
	for mi in meshes:
		mi.layers = head_layers


func _add_shape(body: RigidBody3D, shape: Shape3D, xf: Transform3D) -> void:
	var col := CollisionShape3D.new()
	col.shape = shape
	col.transform = xf
	body.add_child(col)


func _add_mesh(body: Node3D, mesh: Mesh, xf: Transform3D, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	mi.material_override = mat
	body.add_child(mi)
	return mi


## Gives this fighter a sword, held in the right fist.
func equip(new_sword: Sword) -> void:
	sword = new_sword
	sword.wielder = self
	sword.top_level = true
	add_child(sword)
	_attach_sword()


func _attach_sword() -> void:
	sword.global_transform = Transform3D(sword_target, root_to_world(HAND_R))
	sword.linear_velocity = Vector3.ZERO
	sword.angular_velocity = Vector3.ZERO
	sword.reset_physics_interpolation()
	var joint := PinJoint3D.new()
	joint.name = "joint_sword"
	joint.top_level = true
	add_child(joint)
	joint.global_position = sword.global_position
	joint.node_a = joint.get_path_to(parts.arm_lower_r)
	joint.node_b = joint.get_path_to(sword)
	_sword_joint = joint
	_built.append(joint)
	_exclude.append(sword.get_rid())


func _mark_severed(part_name: String) -> void:
	_severed[part_name] = true
	for child: String in _children.get(part_name, []):
		_mark_severed(child)


func _parent_of(part_name: String) -> String:
	for spec: Dictionary in _specs:
		if spec.name == part_name:
			return spec.parent
	return ""


## 0..1 muscle strength left in a limb after its wounds.
func limb_health(part_name: String) -> float:
	if _severed.has(part_name):
		return 0.0
	return clampf(health[part_name] / max_health[part_name], 0.12, 1.0)


func _surface_normal(body: RigidBody3D, point: Vector3) -> Vector3:
	var axis := (body.global_basis * Vector3.UP).normalized()
	var rel := point - body.global_position
	var n := rel - axis * axis.dot(rel)
	return n.normalized() if n.length_squared() > 1e-6 else rel.normalized()


func _open_wound(part_name: String, point: Vector3) -> void:
	if not parts.has(part_name):
		return
	var body: RigidBody3D = parts[part_name]
	var local := body.global_transform.affine_inverse() * point
	if _bleeders.has(part_name) and is_instance_valid(_bleeders[part_name]):
		_bleeders[part_name].position = local
	else:
		_bleeders[part_name] = Gore.bleeder(body, local)


# --- Simulation ----------------------------------------------------------

func _physics_process(delta: float) -> void:
	if parts.pelvis.global_position.y < -20.0:
		respawn()
	_think(delta)
	_update_state(delta)
	_update_blood(delta)
	_update_ground()
	_apply_locomotion(delta)
	_apply_pose(delta)
	_apply_sword(delta)
	_check_kick()


func _update_state(delta: float) -> void:
	_state_time += delta
	stagger = maxf(0.0, stagger - delta * 1.1)
	_dodge_cooldown = maxf(0.0, _dodge_cooldown - delta)
	# Commitment: whipping a weapon around fast costs balance.
	if sword and not is_down():
		var chest: RigidBody3D = parts.chest
		var swing_speed := (sword.linear_velocity - chest.linear_velocity).length()
		stagger = maxf(stagger, clampf((swing_speed - 5.0) / 14.0, 0.0, swing_wobble))
	var vitality := clampf(blood / max_blood * 1.4, 0.2, 1.0)
	match state:
		State.ACTIVE:
			strength = 0.0 if limp else vitality
			var up: Vector3 = parts.chest.global_basis.y
			if up.angle_to(Vector3.UP) > deg_to_rad(knock_tilt_degrees):
				_tilt_time += delta
			else:
				_tilt_time = 0.0
			if _tilt_time > 0.2 or blood < max_blood * 0.25 or _leg_support() < 0.3:
				_tilt_time = 0.0
				knock_down()
		State.KNOCKED:
			strength = 0.0
			if _state_time > knock_duration and not limp and blood > max_blood * 0.3 and _leg_support() >= 0.3:
				state = State.RECOVERING
				_state_time = 0.0
				_reset_feet()
		State.RECOVERING:
			strength = clampf(_state_time / recover_duration, 0.0, 1.0) * vitality
			if limp:
				knock_down()
			elif _state_time >= recover_duration:
				state = State.ACTIVE
				_state_time = 0.0
				got_up.emit()
		State.DEAD:
			strength = 0.0


func _update_blood(delta: float) -> void:
	var total := 0.0
	for part_name: String in bleed:
		var b: float = bleed[part_name]
		if b <= 0.0:
			continue
		# Wounds slowly clot; stumps bleed far longer.
		var stump := _severed.has(part_name) or _has_severed_child(part_name)
		b *= exp(-(0.03 if stump else 0.12) * delta)
		bleed[part_name] = b
		if not _severed.has(part_name):
			total += b
		var drip: CPUParticles3D = _bleeders.get(part_name)
		if drip and is_instance_valid(drip):
			drip.emitting = b > 0.15
			drip.speed_scale = clampf(0.6 + b * 0.4, 0.6, 2.0)
	blood = maxf(0.0, blood - total * delta)
	if blood <= 0.0:
		die()
	# Drips leave stains on the ground.
	_drip_timer -= delta
	if _drip_timer <= 0.0:
		_drip_timer = 0.3
		var space := get_world_3d().direct_space_state
		for part_name: String in _bleeders:
			var drip: CPUParticles3D = _bleeders[part_name]
			if not is_instance_valid(drip) or not drip.emitting or randf() > 0.6:
				continue
			var from := drip.global_position
			var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0, 1)
			var hit := space.intersect_ray(q)
			if hit:
				Gore.stain(get_parent(), hit.position, hit.normal,
						clampf(0.07 + float(bleed[part_name]) * 0.05, 0.07, 0.3))


func _has_severed_child(part_name: String) -> bool:
	for child: String in _children.get(part_name, []):
		if _severed.has(child):
			return true
	return false


## How well the legs can hold the body up (0 = not at all).
func _leg_support() -> float:
	var worst := 1.0
	for side in ["_r", "_l"]:
		if _severed.has("leg_upper" + side) or _severed.has("leg_lower" + side):
			return 0.0
		worst = minf(worst, minf(limb_health("leg_upper" + side), limb_health("leg_lower" + side)))
	return 0.35 + 0.65 * worst


func _update_ground() -> void:
	var from: Vector3 = parts.pelvis.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (hover_height + 0.6), 1, _exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	_ground_distance = INF
	grounded = false
	if hit:
		_ground_y = (hit.position as Vector3).y
		_ground_distance = from.y - _ground_y
		grounded = _ground_distance < hover_height + 0.3


func _apply_locomotion(_delta: float) -> void:
	var pelvis: RigidBody3D = parts.pelvis
	var chest: RigidBody3D = parts.chest
	var s := strength * (1.0 - stagger * 0.6) * _leg_support()

	# Hover spring: carries the body's weight at the hips while the legs
	# plant and step underneath.
	var target_height := hover_height - (crouch_depth if crouching else 0.0)
	if grounded and s > 0.0:
		var k := hover_frequency * hover_frequency
		var c := 2.0 * 0.9 * hover_frequency
		var err := target_height - _ground_distance
		var f := total_mass * (GRAVITY + err * k - pelvis.linear_velocity.y * c)
		f = clampf(f, 0.0, total_mass * GRAVITY * 3.0) * s
		pelvis.apply_central_force(Vector3.UP * f)

	# Horizontal drive, pushed through the hips and the chest.
	var v := center_of_mass_velocity()
	var speed := sprint_speed if sprinting and not crouching else walk_speed
	if crouching:
		speed *= 0.6
	var want := move_input.limit_length(1.0) * speed
	var dv := want - Vector3(v.x, 0.0, v.z)
	var accel := ground_accel if grounded else air_accel
	var force := (dv * 6.0).limit_length(accel) * total_mass * s
	pelvis.apply_central_force(force * 0.55)
	chest.apply_central_force(force * 0.45)


func _apply_pose(delta: float) -> void:
	var hq := heading_quat()
	var s := strength * (1.0 - stagger)
	var limb := lerpf(limp_strength, 1.0, s)
	var balance := s * (1.0 if grounded else 0.35) * _leg_support()
	var pelvis: RigidBody3D = parts.pelvis
	var chest: RigidBody3D = parts.chest

	var v := center_of_mass_velocity()
	var local_v := hq.inverse() * Vector3(v.x, 0.0, v.z)

	# Balance: external "cheat" torques that keep hips and torso upright.
	var lean := clampf(-local_v.z * 0.05, -0.1, 0.25) + (0.18 if crouching else 0.0)
	var chest_q := hq * Quaternion(Vector3.UP, -chest_twist) * Quaternion(Vector3.RIGHT, -lean)
	# The chest carries the head, arms and weapon; the pelvis carries the legs.
	_drive_rotation(pelvis, hq, null, balance_frequency, 1.0, balance_torque * 0.8 * balance, 5.0)
	_drive_rotation(chest, chest_q, null, balance_frequency, 1.0, balance_torque * balance, 7.0)
	if not _severed.has("head"):
		_drive_rotation(parts.head, hq * Quaternion(Vector3.RIGHT, look_pitch * 0.5), chest,
				limb_frequency, 1.0, 40.0 * limb)

	# Legs: plant the feet and step with IK.
	var targets := _update_feet(delta)
	var kicking := _kick_t > 0.0
	for side in ["_r", "_l"]:
		var kick_leg: bool = kicking and side == "_r"
		_drive_leg(side, HIP_R if side == "_r" else HIP_L, targets[side], hq, limb * (3.0 if kick_leg else 1.0),
				limb_frequency * (1.6 if kick_leg else 1.0))

	# Arms: two-bone IK toward the hand targets.
	var right := clamp_to_reach(root_to_world(hand_target_r), SHOULDER_R)
	var left := root_to_world(hand_target_l)
	if half_sword and sword and not _severed.has("arm_lower_l"):
		left = sword.half_grip_position()
	_drive_arm("_r", SHOULDER_R, right, hq * elbow_pole_r, limb)
	_drive_arm("_l", SHOULDER_L, left, hq * elbow_pole_l, limb)


# --- Footwork ------------------------------------------------------------

func _reset_feet() -> void:
	var hq := heading_quat()
	var root := root_origin()
	for side in ["_r", "_l"]:
		var sx := 0.11 if side == "_r" else -0.11
		var p := root + hq * Vector3(sx, 0, 0)
		_feet[side] = {"planted": p, "from": p, "to": p, "t": 1.0, "rest": 0.0}


## World-space ankle targets for both feet. Feet stay planted until the body
## has drifted too far from them, then step (one at a time) to catch it.
func _update_feet(delta: float) -> Dictionary:
	var hq := heading_quat()
	var pelvis: RigidBody3D = parts.pelvis
	var out := {}
	if not grounded or state == State.KNOCKED or state == State.DEAD:
		# Legs hang under the hips.
		for side in ["_r", "_l"]:
			var hip := pelvis.global_transform * ((HIP_R if side == "_r" else HIP_L) - (pelvis.get_meta("rest_offset") as Vector3))
			out[side] = hip + Vector3.DOWN * (THIGH_LENGTH + SHIN_LENGTH - 0.05) + hq * Vector3(0, 0, -0.05)
			_feet[side].planted = Vector3(out[side].x, _ground_y, out[side].z)
			_feet[side].t = 1.0
		return out

	var v := center_of_mass_velocity()
	var hv := Vector3(v.x, 0.0, v.z)
	var speed := hv.length()
	var root := Vector3(pelvis.global_position.x, _ground_y, pelvis.global_position.z)
	var width := 0.13 if crouching else 0.11
	var desired := {}
	for side in ["_r", "_l"]:
		var sx := width if side == "_r" else -width
		desired[side] = root + hq * Vector3(sx, 0, 0.02) + hv * 0.2

	var stepping := false
	for side in ["_r", "_l"]:
		_feet[side].rest += delta
		if _feet[side].t < 1.0:
			stepping = true
	var kicking := _kick_t > 0.0
	if not stepping and not kicking:
		var best := ""
		var best_err := 0.0
		for side in ["_r", "_l"]:
			var planted: Vector3 = _feet[side].planted
			var err := Vector2(planted.x - desired[side].x, planted.z - desired[side].z).length()
			var settle: bool = err > 0.05 and _feet[side].rest > 0.7
			if (err > step_trigger or settle) and err > best_err:
				best = side
				best_err = err
		if best != "":
			var f: Dictionary = _feet[best]
			f.from = f.planted
			f.to = desired[best] + hv * 0.12
			f.t = 0.0
			f.rest = 0.0

	for side in ["_r", "_l"]:
		var f: Dictionary = _feet[side]
		var pos: Vector3 = f.planted
		if f.t < 1.0:
			var duration := clampf(step_time - speed * 0.02, 0.15, step_time)
			f.t = minf(1.0, f.t + delta / duration)
			var e := smoothstep(0.0, 1.0, f.t)
			pos = (f.from as Vector3).lerp(f.to, e) + Vector3.UP * sin(PI * f.t) * (0.09 + speed * 0.02)
			if f.t >= 1.0:
				f.planted = f.to
				pos = f.to
		out[side] = pos + Vector3.UP * ANKLE_HEIGHT

	if kicking:
		_kick_t += delta
		var k := _kick_t / KICK_TIME
		var chamber := root + hq * Vector3(0.12, 0.55, -0.25)
		var extend := root + hq * Vector3(0.1, 0.7, -1.0)
		if k < 0.25:
			out["_r"] = (out["_r"] as Vector3).lerp(chamber, k / 0.25)
		elif k < 0.5:
			out["_r"] = chamber.lerp(extend, (k - 0.25) / 0.25)
			# Lunge into it.
			pelvis.apply_central_force(hq * Vector3.FORWARD * total_mass * 6.0)
		elif k < 1.0:
			out["_r"] = extend.lerp(_feet["_r"].planted + Vector3.UP * ANKLE_HEIGHT, (k - 0.5) / 0.5)
		else:
			_kick_t = 0.0
			_feet["_r"].planted = Vector3(out["_r"].x, _ground_y, out["_r"].z)
	return out


func _drive_leg(side: String, hip_rest: Vector3, ankle: Vector3, hq: Quaternion, limb: float, freq: float) -> void:
	var thigh_name := "leg_upper" + side
	var shin_name := "leg_lower" + side
	if _severed.has(thigh_name):
		return
	var pelvis: RigidBody3D = parts.pelvis
	var thigh: RigidBody3D = parts[thigh_name]
	var shin: RigidBody3D = parts[shin_name]
	var hip := pelvis.global_transform * (hip_rest - (pelvis.get_meta("rest_offset") as Vector3))
	var knee_pole := hq * Vector3(0.1 if side == "_r" else -0.1, 0, -1)
	var ik := _two_bone(hip, ankle, THIGH_LENGTH, SHIN_LENGTH, knee_pole)
	var hurt := limb_health(thigh_name)
	_drive_rotation(thigh, _arc(Vector3.DOWN, ik[0]) * hq, pelvis, freq, 1.0, 260.0 * limb * hurt, 2.0)
	if not _severed.has(shin_name):
		_drive_rotation(shin, _arc(Vector3.DOWN, ik[1]) * hq, thigh, freq, 1.0,
				150.0 * limb * limb_health(shin_name))


## Kicks land as blunt hits on whoever the shin connects with.
func _check_kick() -> void:
	if _kick_t <= 0.0 or _kick_hit or _kick_t < KICK_TIME * 0.25:
		return
	var shin: RigidBody3D = parts.leg_lower_r
	for other in shin.get_colliding_bodies():
		if other is RigidBody3D and other.has_meta("ragdoll") and other.get_meta("ragdoll") != self:
			_kick_hit = true
			var target: ActiveRagdoll = other.get_meta("ragdoll")
			var push := heading_quat() * Vector3.FORWARD
			var speed := maxf(shin.linear_velocity.length(), 4.0)
			other.apply_central_impulse(push * 90.0)
			target.receive_hit(other, other.global_position, push, speed, 0.0, 6.0)
			target.stagger = maxf(target.stagger, 0.7)
			return


# --- Arms and weapon -----------------------------------------------------

func _drive_arm(side: String, shoulder_rest: Vector3, target: Vector3, pole: Vector3, limb: float) -> void:
	var upper_name := "arm_upper" + side
	var lower_name := "arm_lower" + side
	if _severed.has(upper_name):
		return
	var chest: RigidBody3D = parts.chest
	var upper: RigidBody3D = parts[upper_name]
	var lower: RigidBody3D = parts[lower_name]
	var shoulder := _shoulder_world(shoulder_rest)
	var ik := _two_bone(shoulder, target, UPPER_ARM_LENGTH, LOWER_ARM_LENGTH, pole)
	var hurt := minf(limb_health(upper_name), limb_health(lower_name) if not _severed.has(lower_name) else 1.0)
	var has_lower := not _severed.has(lower_name)
	_drive_direction(upper, ik[0], chest, limb_frequency, 1.0, 90.0 * limb * hurt, 3.0)
	if has_lower:
		_drive_direction(lower, ik[1], upper, limb_frequency, 1.0, 60.0 * limb * hurt, 1.5)
	# Hold the arm's own weight up, so a raised guard doesn't sag.
	var hold := limb * hurt
	var lift := Vector3.UP * GRAVITY
	var elbow := upper.global_position + (upper.global_basis * Vector3.DOWN) * UPPER_ARM_LENGTH * 0.5
	var t_upper := (upper.global_position - shoulder).cross(lift * upper.mass)
	if has_lower:
		t_upper += (lower.global_position - shoulder).cross(lift * lower.mass)
		var t_lower := (lower.global_position - elbow).cross(lift * lower.mass) * hold
		lower.apply_torque(t_lower)
		upper.apply_torque(-t_lower)
	upper.apply_torque(t_upper * hold)
	chest.apply_torque(-t_upper * hold)


## Upper and lower bone directions that reach from root toward target,
## bending toward pole.
static func _two_bone(root: Vector3, target: Vector3, l1: float, l2: float, pole: Vector3) -> Array[Vector3]:
	var to := target - root
	var d := clampf(to.length(), 0.08, l1 + l2 - 0.002)
	var dir := to.normalized() if to.length_squared() > 1e-6 else Vector3.DOWN
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var perp := pole - dir * dir.dot(pole)
	if perp.length_squared() < 1e-6:
		perp = dir.cross(Vector3.RIGHT)
	perp = perp.normalized()
	var joint := root + dir * a + perp * h
	var end := root + dir * d
	return [(joint - root).normalized(), (end - joint).normalized()]


func _shoulder_world(shoulder_rest: Vector3) -> Vector3:
	var chest: RigidBody3D = parts.chest
	return chest.global_transform * (shoulder_rest - (chest.get_meta("rest_offset") as Vector3))


## Clamps a world-space hand target to what an arm can reach.
func clamp_to_reach(target: Vector3, shoulder_rest := SHOULDER_R) -> Vector3:
	var shoulder := _shoulder_world(shoulder_rest)
	return shoulder + (target - shoulder).limit_length(UPPER_ARM_LENGTH + LOWER_ARM_LENGTH - 0.01)


func hand_position(side: String) -> Vector3:
	var lower: RigidBody3D = parts["arm_lower" + side]
	return lower.global_transform * (lower.get_meta("hand_offset") as Vector3)


func _apply_sword(delta: float) -> void:
	if sword == null or _severed.has("arm_lower_r") or not is_instance_valid(_sword_joint):
		return
	var chest: RigidBody3D = parts.chest
	_update_half_sword()
	# Track how fast the targets themselves move, so the muscles damp toward
	# the motion instead of fighting it. That keeps fast strokes snappy.
	var target := clamp_to_reach(root_to_world(hand_target_r), SHOULDER_R)
	var target_q := sword_target.get_rotation_quaternion()
	if _has_prev_sword_target:
		var v := (target - _prev_grip_target) / delta
		var w := _quat_err(_prev_sword_q, target_q) / delta
		_grip_target_velocity = _grip_target_velocity.lerp(v, 1.0 - exp(-30.0 * delta))
		_sword_target_spin = _sword_target_spin.lerp(w, 1.0 - exp(-30.0 * delta))
	_has_prev_sword_target = true
	_prev_grip_target = target
	_prev_sword_q = target_q
	var arm := minf(limb_health("arm_upper_r"), limb_health("arm_lower_r"))
	var s := strength * (1.0 - stagger * 0.5) * arm
	if s <= 0.0:
		return
	var two_hands := 1.4 if half_sword_held else 1.0
	# Grip: pull the fist (and the weapon with it) toward the hand target.
	# The equal and opposite force goes into the shoulder, so big swings
	# yank the whole body around.
	var arm_mass: float = sword.mass + parts.arm_upper_r.mass + parts.arm_lower_r.mass
	var freq := 18.0
	var rel_v := sword.linear_velocity - _grip_target_velocity
	var f := arm_mass * ((target - sword.global_position) * freq * freq - rel_v * 2.0 * 0.9 * freq)
	f += Vector3.UP * sword.mass * GRAVITY
	f = f.limit_length(grip_force * s * two_hands)
	sword.apply_force(f)
	chest.apply_force(-f, _shoulder_world(SHOULDER_R) - chest.global_position)
	# Wrist: turn the blade toward the wanted orientation. Loose enough that
	# the blade lags and whips through a stroke.
	var err := _quat_err(sword.global_basis.get_rotation_quaternion(), target_q)
	var t := _pd(sword, err, sword.angular_velocity - _sword_target_spin, 16.0 * sqrt(two_hands), 0.8,
			wrist_torque * s * two_hands * two_hands, 1.4)
	sword.apply_torque(t)
	chest.apply_torque(-t)


## Joins the off hand to the blade once it gets there, and lets go again.
func _update_half_sword() -> void:
	var can_hold := half_sword and not is_down() and not _severed.has("arm_lower_l")
	if not can_hold:
		_release_half_sword()
		return
	if half_sword_held:
		return
	var grip := sword.half_grip_position()
	if hand_position("_l").distance_to(grip) < 0.14:
		var joint := PinJoint3D.new()
		joint.name = "joint_half_sword"
		joint.top_level = true
		add_child(joint)
		joint.global_position = hand_position("_l")
		joint.node_a = joint.get_path_to(parts.arm_lower_l)
		joint.node_b = joint.get_path_to(sword)
		_half_joint = joint
		_built.append(joint)
		half_sword_held = true


func _release_half_sword() -> void:
	if _half_joint and is_instance_valid(_half_joint):
		_half_joint.queue_free()
	_half_joint = null
	half_sword_held = false


# --- Muscle math ---------------------------------------------------------

## PD muscle toward a full target orientation. With a parent the torque is
## internal (the parent gets the reaction); without one it is external.
func _drive_rotation(body: RigidBody3D, target: Quaternion, parent: RigidBody3D,
		freq: float, zeta: float, max_torque: float, load := 1.0) -> void:
	if max_torque <= 0.0:
		return
	var err := _quat_err(body.global_basis.get_rotation_quaternion(), target)
	var rel_w := body.angular_velocity
	if parent:
		rel_w -= parent.angular_velocity
	var t := _pd(body, err, rel_w, freq, zeta, max_torque, load)
	body.apply_torque(t)
	if parent:
		parent.apply_torque(-t)


## PD muscle that only aims a limb's bone (its local -Y) and leaves twist free.
func _drive_direction(body: RigidBody3D, want: Vector3, parent: RigidBody3D,
		freq: float, zeta: float, max_torque: float, load := 1.0) -> void:
	if max_torque <= 0.0:
		return
	var cur := (body.global_basis * Vector3.DOWN).normalized()
	var axis := cur.cross(want)
	var sn := axis.length()
	var cs := cur.dot(want)
	var err := Vector3.ZERO
	if sn > 1e-5:
		err = axis / sn * atan2(sn, cs)
	elif cs < 0.0:
		err = body.global_basis.x * PI
	var t := _pd(body, err, body.angular_velocity - parent.angular_velocity, freq, zeta, max_torque, load)
	body.apply_torque(t)
	parent.apply_torque(-t)


## Torque that gives the body angular acceleration kp*err - kd*w, capped.
## load scales the body's own inertia up to account for whatever it carries.
static func _pd(body: RigidBody3D, err: Vector3, rel_w: Vector3, freq: float, zeta: float,
		max_torque: float, load := 1.0) -> Vector3:
	var alpha := err * freq * freq - rel_w * 2.0 * zeta * freq
	var b := body.global_basis.orthonormalized()
	var local := b.transposed() * alpha
	var t := b * (local * body.inertia * load)
	return t.limit_length(max_torque)


## Rotation vector (axis * angle) that turns cur into target, shortest way.
static func _quat_err(cur: Quaternion, target: Quaternion) -> Vector3:
	var q := target * cur.inverse()
	if q.w < 0.0:
		q = -q
	var v := Vector3(q.x, q.y, q.z)
	var s := v.length()
	if s < 1e-6:
		return Vector3.ZERO
	return v / s * 2.0 * atan2(s, q.w)


## Shortest rotation from one unit vector to another, safe when opposite.
static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	from = from.normalized()
	to = to.normalized()
	if from.dot(to) < -0.9999:
		var axis := from.cross(Vector3.RIGHT)
		if axis.length_squared() < 1e-6:
			axis = from.cross(Vector3.FORWARD)
		return Quaternion(axis.normalized(), PI)
	return Quaternion(from, to)
