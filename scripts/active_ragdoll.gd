class_name ActiveRagdoll
extends Node3D
## A wobbly, physics-driven humanoid in the spirit of Human: Fall Flat.
##
## Every body part is a RigidBody3D pinned to its parent with a ball joint.
## Nothing is animated. "Muscles" apply PD torques that pull each part toward
## a target pose, a hover spring holds the pelvis up, and balance torques keep
## the torso upright. Every muscle has a strength cap, so heavy swings, sword
## hits and bumps can overpower it and make the body stumble or fall over.
##
## Subclasses steer the body by overriding _think() and writing the intent
## variables (heading_yaw, move_input, hand targets, ...) every physics tick.

signal knocked_down
signal got_up
signal jumped
## Emitted on touching down after a fall; speed is the downward speed in m/s.
signal landed(speed: float)

enum State { ACTIVE, KNOCKED, RECOVERING }

const GRAVITY := 9.8
## Pelvis height above the feet in the rest pose.
const PELVIS_HEIGHT := 0.98
const UPPER_ARM_LENGTH := 0.28
## Elbow to the centre of the fist (where a sword is held).
const LOWER_ARM_LENGTH := 0.31
const SHOULDER_R := Vector3(0.3, 1.6, 0.0)
const SHOULDER_L := Vector3(-0.3, 1.6, 0.0)
const HAND_R := Vector3(0.3, 1.01, 0.0)

@export_group("Look")
@export var body_color := Color(0.93, 0.93, 0.95)
@export var accent_color := Color(0.25, 0.5, 0.95)
@export var skin_color := Color(1.0, 0.84, 0.7)

@export_group("Physics layers")
@export_flags_3d_physics var body_layer := 2
@export_flags_3d_physics var body_mask := 11

@export_group("Movement")
@export var walk_speed := 3.0
@export var sprint_speed := 5.2
@export var ground_accel := 20.0
@export var air_accel := 4.0
@export var jump_speed := 3.8
## Target distance from the pelvis to the ground while standing.
@export var hover_height := 0.96
@export var hover_frequency := 9.0

@export_group("Muscles")
@export var balance_frequency := 6.0
@export var balance_torque := 320.0
@export var limb_frequency := 14.0
## Muscle strength left over while knocked down (0 = completely floppy).
@export var limp_strength := 0.08
@export var grip_force := 650.0
@export var wrist_torque := 70.0
## How much balance a full-speed sword swing costs (0..1).
@export var swing_wobble := 0.65
## Balance left while airborne (0..1).
@export var air_balance := 0.35
@export var knock_tilt_degrees := 68.0
@export var knock_duration := 1.6
@export var recover_duration := 1.1
## Relative sword speed (m/s) that knocks this body over outright.
@export var knockout_hit_speed := 13.0

# --- Intent. Written by subclasses in _think(). ---------------------------
var heading_yaw := 0.0
## World-space horizontal move direction, length 0..1.
var move_input := Vector3.ZERO
var sprinting := false
var limp := false
## Hand targets in root space: x right, y up from the feet, -z forward.
var hand_target_r := Vector3(0.3, 1.0, -0.05)
var hand_target_l := Vector3(-0.3, 1.0, -0.05)
## Direction each elbow should point, in root space.
var elbow_pole_r := Vector3(0.6, -1.0, 0.5)
var elbow_pole_l := Vector3(-0.6, -1.0, 0.5)
## Chest twist in radians (positive turns the shoulders to the right).
var chest_twist := 0.0
## Look up/down in radians, used for the head.
var look_pitch := 0.0
## Wanted world orientation of the held sword (y = blade, z = edge).
var sword_target := Basis.IDENTITY

# --- State ---------------------------------------------------------------
var state := State.ACTIVE
## 0..1 overall muscle strength (0 while knocked down).
var strength := 1.0
## 0..1 temporary weakness after taking a hit.
var stagger := 0.0
var grounded := false
var parts := {}
var total_mass := 0.0
var sword: Sword = null

var _specs: Array = []
var _meshes := {}
var _exclude: Array[RID] = []
var _spawn := Transform3D.IDENTITY
var _state_time := 0.0
var _tilt_time := 0.0
var _gait_phase := 0.0
var _gait_amp := 0.0
var _jump_cooldown := 0.0
var _no_hover_time := 0.0
var _jump_queued := false
var _ground_distance := INF
var _has_prev_sword_target := false
var _prev_grip_target := Vector3.ZERO
var _prev_sword_q := Quaternion.IDENTITY
var _grip_target_velocity := Vector3.ZERO
var _sword_target_spin := Vector3.ZERO
var _flash_time := {}
var _flash_material: StandardMaterial3D


func _ready() -> void:
	_spawn = global_transform
	heading_yaw = global_rotation.y
	_build()


## Override to steer the body. Called at the start of every physics tick.
func _think(_delta: float) -> void:
	pass


func jump() -> void:
	_jump_queued = true


func is_down() -> bool:
	return state != State.ACTIVE


func part(part_name: String) -> RigidBody3D:
	return parts[part_name]


## Root frame origin: under the pelvis, at foot level.
func root_origin() -> Vector3:
	var p: Vector3 = parts.pelvis.global_position
	return Vector3(p.x, p.y - PELVIS_HEIGHT, p.z)


func heading_quat() -> Quaternion:
	return Quaternion(Vector3.UP, heading_yaw)


func root_to_world(local: Vector3) -> Vector3:
	return root_origin() + heading_quat() * local


func center_of_mass_velocity() -> Vector3:
	var v := Vector3.ZERO
	for body: RigidBody3D in parts.values():
		v += body.linear_velocity * body.mass
	return v / total_mass


func knock_down() -> void:
	if state == State.KNOCKED:
		_state_time = 0.0
		return
	state = State.KNOCKED
	_state_time = 0.0
	strength = 0.0
	knocked_down.emit()


## Called by whatever hit us. speed is the relative impact speed in m/s.
func take_hit(body: RigidBody3D, speed: float) -> void:
	stagger = clampf(maxf(stagger, speed / 18.0), 0.0, 0.85)
	if speed >= knockout_hit_speed:
		knock_down()
	_flash_time[body] = 0.12
	for mesh: MeshInstance3D in _meshes.get(body, []):
		mesh.material_overlay = _flash_material


func respawn() -> void:
	_place_at(_spawn)
	heading_yaw = _spawn.basis.get_euler().y
	state = State.ACTIVE
	strength = 1.0
	stagger = 0.0
	_tilt_time = 0.0
	_has_prev_sword_target = false
	_grip_target_velocity = Vector3.ZERO
	_sword_target_spin = Vector3.ZERO


# --- Construction --------------------------------------------------------

func _part_specs() -> Array:
	var specs := [
		{"name": "pelvis", "parent": "", "a": Vector3(-0.12, 0.98, 0), "b": Vector3(0.12, 0.98, 0),
			"r": 0.14, "mass": 10.0, "color": "accent"},
		{"name": "chest", "parent": "pelvis", "joint": Vector3(0, 1.08, 0),
			"a": Vector3(0, 1.2, 0), "b": Vector3(0, 1.5, 0), "r": 0.2, "mass": 16.0, "color": "body"},
		{"name": "head", "parent": "chest", "joint": Vector3(0, 1.72, 0),
			"a": Vector3(0, 1.87, 0), "b": Vector3(0, 1.89, 0), "r": 0.155, "mass": 4.0, "color": "skin"},
	]
	for side: int in [1, -1]:
		var s := "_r" if side > 0 else "_l"
		var x := 0.3 * side
		var lx := 0.11 * side
		specs.append({"name": "arm_upper" + s, "parent": "chest", "joint": Vector3(x, 1.6, 0),
			"a": Vector3(x, 1.6, 0), "b": Vector3(x, 1.34, 0), "r": 0.065, "mass": 2.2, "color": "body"})
		specs.append({"name": "arm_lower" + s, "parent": "arm_upper" + s, "joint": Vector3(x, 1.32, 0),
			"a": Vector3(x, 1.3, 0), "b": Vector3(x, 1.1, 0), "r": 0.055, "mass": 1.4, "color": "body",
			"sphere": [Vector3(x, 1.01, 0), 0.068, "skin"]})
		specs.append({"name": "leg_upper" + s, "parent": "pelvis", "joint": Vector3(lx, 0.92, 0),
			"a": Vector3(lx, 0.9, 0), "b": Vector3(lx, 0.54, 0), "r": 0.085, "mass": 6.0, "color": "accent"})
		specs.append({"name": "leg_lower" + s, "parent": "leg_upper" + s, "joint": Vector3(lx, 0.5, 0),
			"a": Vector3(lx, 0.47, 0), "b": Vector3(lx, 0.12, 0), "r": 0.07, "mass": 3.5, "color": "accent",
			"box": [Vector3(lx, 0.045, -0.05), Vector3(0.12, 0.09, 0.25), "body"]})
	return specs


func _build() -> void:
	_specs = _part_specs()
	var colors := {"body": body_color, "accent": accent_color, "skin": skin_color}
	var materials := {}
	for key: String in colors:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colors[key]
		mat.roughness = 0.75
		materials[key] = mat
	_flash_material = StandardMaterial3D.new()
	_flash_material.albedo_color = Color(1, 0.25, 0.2, 0.75)
	_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var phys := PhysicsMaterial.new()
	phys.friction = 0.8

	for spec: Dictionary in _specs:
		var a: Vector3 = spec.a
		var b: Vector3 = spec.b
		var r: float = spec.r
		var mass: float = spec.mass
		var mid := (a + b) * 0.5
		var bone := b - a
		var length := bone.length()
		var dir := bone / length
		if dir.y < 0.0:
			dir = -dir

		var body := RigidBody3D.new()
		body.name = spec.name
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
		# Explicit inertia (capsule approximated as a cylinder, padded for
		# stability) so the PD muscles know exactly what they are pushing.
		var h := length + r * 1.4
		var i_axis := maxf(0.5 * mass * r * r, 0.004) * 1.5
		var i_perp := maxf(mass * (3.0 * r * r + h * h) / 12.0, 0.004) * 1.5
		var along_x := absf(dir.x) > 0.5
		body.inertia = Vector3(i_axis, i_perp, i_perp) if along_x else Vector3(i_perp, i_axis, i_perp)

		var shape_basis := Basis(_arc(Vector3.UP, dir))
		var capsule := CapsuleShape3D.new()
		capsule.radius = r
		capsule.height = length + 2.0 * r
		var col := CollisionShape3D.new()
		col.shape = capsule
		col.transform = Transform3D(shape_basis, Vector3.ZERO)
		body.add_child(col)
		var meshes: Array[MeshInstance3D] = []
		var cmesh := CapsuleMesh.new()
		cmesh.radius = r
		cmesh.height = length + 2.0 * r
		meshes.append(_add_mesh(body, cmesh, Transform3D(shape_basis, Vector3.ZERO), materials[spec.color]))

		if spec.has("sphere"):
			var c: Vector3 = spec.sphere[0]
			var sr: float = spec.sphere[1]
			var sshape := SphereShape3D.new()
			sshape.radius = sr
			var scol := CollisionShape3D.new()
			scol.shape = sshape
			scol.position = c - mid
			body.add_child(scol)
			var smesh := SphereMesh.new()
			smesh.radius = sr
			smesh.height = sr * 2.0
			meshes.append(_add_mesh(body, smesh, Transform3D(Basis.IDENTITY, c - mid), materials[spec.sphere[2]]))
		if spec.has("box"):
			var c: Vector3 = spec.box[0]
			var size: Vector3 = spec.box[1]
			var bshape := BoxShape3D.new()
			bshape.size = size
			var bcol := CollisionShape3D.new()
			bcol.shape = bshape
			bcol.position = c - mid
			body.add_child(bcol)
			var bmesh := BoxMesh.new()
			bmesh.size = size
			meshes.append(_add_mesh(body, bmesh, Transform3D(Basis.IDENTITY, c - mid), materials[spec.box[2]]))
		if spec.name == "head":
			var eye_mat := StandardMaterial3D.new()
			eye_mat.albedo_color = Color(0.08, 0.08, 0.1)
			for ex: float in [-0.055, 0.055]:
				var eye := SphereMesh.new()
				eye.radius = 0.028
				eye.height = 0.056
				_add_mesh(body, eye, Transform3D(Basis.IDENTITY, Vector3(ex, 0.02, -0.14)), eye_mat)

		add_child(body)
		body.global_transform = global_transform * Transform3D(Basis.IDENTITY, mid)
		parts[spec.name] = body
		_meshes[body] = meshes
		_exclude.append(body.get_rid())
		total_mass += mass

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


func _add_mesh(body: Node3D, mesh: Mesh, xf: Transform3D, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	mi.material_override = mat
	body.add_child(mi)
	return mi


## Gives this ragdoll a sword, held in the right fist.
func equip(new_sword: Sword) -> void:
	sword = new_sword
	sword.wielder = self
	sword.top_level = true
	add_child(sword)
	sword.global_transform = Transform3D(sword_target, global_transform * HAND_R)
	var joint := PinJoint3D.new()
	joint.name = "joint_sword"
	joint.top_level = true
	add_child(joint)
	joint.global_position = sword.global_position
	joint.node_a = joint.get_path_to(parts.arm_lower_r)
	joint.node_b = joint.get_path_to(sword)
	_exclude.append(sword.get_rid())


func _place_at(xf: Transform3D) -> void:
	var flat := Transform3D(Basis(Vector3.UP, xf.basis.get_euler().y), xf.origin)
	for spec: Dictionary in _specs:
		var body: RigidBody3D = parts[spec.name]
		body.global_transform = flat * Transform3D(Basis.IDENTITY, (spec.a + spec.b) * 0.5)
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.reset_physics_interpolation()
	if sword:
		sword.global_transform = Transform3D(flat.basis, flat * HAND_R)
		sword.linear_velocity = Vector3.ZERO
		sword.angular_velocity = Vector3.ZERO
		sword.reset_physics_interpolation()


# --- Simulation ----------------------------------------------------------

func _physics_process(delta: float) -> void:
	if parts.pelvis.global_position.y < -20.0:
		respawn()
	_think(delta)
	_update_state(delta)
	_update_ground()
	_apply_locomotion(delta)
	_apply_pose(delta)
	_apply_sword(delta)
	_update_flash(delta)


func _update_state(delta: float) -> void:
	_state_time += delta
	stagger = maxf(0.0, stagger - delta * 1.1)
	# Commitment: whipping the sword around fast costs balance.
	if sword:
		var chest: RigidBody3D = parts.chest
		var swing_speed := (sword.linear_velocity - chest.linear_velocity).length()
		stagger = maxf(stagger, clampf((swing_speed - 5.0) / 14.0, 0.0, swing_wobble))
	match state:
		State.ACTIVE:
			strength = 0.0 if limp else 1.0
			var up: Vector3 = parts.chest.global_basis.y
			if up.angle_to(Vector3.UP) > deg_to_rad(knock_tilt_degrees):
				_tilt_time += delta
			else:
				_tilt_time = 0.0
			if _tilt_time > 0.2:
				_tilt_time = 0.0
				knock_down()
		State.KNOCKED:
			strength = 0.0
			if _state_time > knock_duration and not limp:
				state = State.RECOVERING
				_state_time = 0.0
		State.RECOVERING:
			strength = clampf(_state_time / recover_duration, 0.0, 1.0)
			if limp:
				knock_down()
			elif strength >= 1.0:
				state = State.ACTIVE
				_state_time = 0.0
				got_up.emit()


func _update_ground() -> void:
	var from: Vector3 = parts.pelvis.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (hover_height + 0.6), 1, _exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	_ground_distance = INF
	var was_grounded := grounded
	grounded = false
	if hit:
		_ground_distance = from.y - (hit.position as Vector3).y
		grounded = _ground_distance < hover_height + 0.3
	var fall_speed: float = -parts.pelvis.linear_velocity.y
	if grounded and not was_grounded and fall_speed > 2.0:
		landed.emit(fall_speed)
		if fall_speed > 3.0:
			# Hard landing: legs buckle for a moment.
			stagger = maxf(stagger, clampf(fall_speed * 0.1, 0.0, 0.7))



func _apply_locomotion(delta: float) -> void:
	var pelvis: RigidBody3D = parts.pelvis
	var chest: RigidBody3D = parts.chest
	var s := strength * (1.0 - stagger * 0.6)
	_jump_cooldown = maxf(0.0, _jump_cooldown - delta)
	_no_hover_time = maxf(0.0, _no_hover_time - delta)

	# Hover spring: holds the pelvis at standing height, legs just dangle
	# onto the floor underneath it.
	if grounded and _no_hover_time <= 0.0 and s > 0.0:
		var k := hover_frequency * hover_frequency
		var c := 2.0 * 0.9 * hover_frequency
		var err := hover_height - _ground_distance
		var f := total_mass * (GRAVITY + err * k - pelvis.linear_velocity.y * c)
		f = clampf(f, 0.0, total_mass * GRAVITY * 3.0) * s
		pelvis.apply_central_force(Vector3.UP * f)

	# Horizontal drive, pushed through the hips and the chest.
	var v := center_of_mass_velocity()
	var speed := sprint_speed if sprinting else walk_speed
	var want := move_input.limit_length(1.0) * speed
	var dv := want - Vector3(v.x, 0.0, v.z)
	var accel := ground_accel if grounded else air_accel
	var force := (dv * 6.0).limit_length(accel) * total_mass * s
	pelvis.apply_central_force(force * 0.55)
	chest.apply_central_force(force * 0.45)

	if _jump_queued:
		_jump_queued = false
		if grounded and _jump_cooldown <= 0.0 and state == State.ACTIVE:
			_jump_cooldown = 0.6
			_no_hover_time = 0.25
			var up_speed := maxf(0.0, jump_speed - v.y)
			for body: RigidBody3D in parts.values():
				body.apply_central_impulse(Vector3.UP * up_speed * body.mass)
			if sword:
				sword.apply_central_impulse(Vector3.UP * up_speed * sword.mass)
			jumped.emit()


func _apply_pose(delta: float) -> void:
	var hq := heading_quat()
	var s := strength * (1.0 - stagger)
	var limb := lerpf(limp_strength, 1.0, s)
	var balance := s * (1.0 if grounded else air_balance)
	var pelvis: RigidBody3D = parts.pelvis
	var chest: RigidBody3D = parts.chest

	var v := center_of_mass_velocity()
	var hv := Vector3(v.x, 0.0, v.z)
	var spd := hv.length()
	var fwd := hq * Vector3.FORWARD
	var local_v := hq.inverse() * hv

	# Balance: external "cheat" torques that keep hips and torso upright.
	var lean := clampf(-local_v.z * 0.05, -0.1, 0.25)
	var chest_q := hq * Quaternion(Vector3.UP, -chest_twist) * Quaternion(Vector3.RIGHT, -lean)
	# The chest carries the head, arms and sword; the pelvis carries the legs.
	_drive_rotation(pelvis, hq, null, balance_frequency, 1.0, balance_torque * 0.8 * balance, 5.0)
	_drive_rotation(chest, chest_q, null, balance_frequency, 1.0, balance_torque * balance, 7.0)
	_drive_rotation(parts.head, hq * Quaternion(Vector3.RIGHT, look_pitch * 0.5), chest,
			limb_frequency, 1.0, 40.0 * limb)

	# Legs: a simple procedural gait along the direction of travel.
	var target_amp := clampf(spd * 0.16, 0.0, 0.6) if grounded and spd > 0.3 else 0.0
	_gait_amp = lerpf(_gait_amp, target_amp, 1.0 - exp(-8.0 * delta))
	if _gait_amp > 0.01:
		_gait_phase = fmod(_gait_phase + delta * (5.0 + spd * 1.7), TAU)
	var move_dir := hv / spd if spd > 0.2 else fwd
	for side: int in [1, -1]:
		var sfx := "_r" if side > 0 else "_l"
		var ph := _gait_phase + (0.0 if side > 0 else PI)
		var swing := sin(ph) * _gait_amp
		var knee := maxf(0.0, cos(ph)) * _gait_amp * 1.6 + 0.04
		if not grounded:
			swing = 0.3 if side > 0 else 0.05
			knee = 0.7 if side > 0 else 0.35
		var thigh_dir := Vector3.DOWN * cos(swing) + move_dir * sin(swing)
		var shin_dir := Vector3.DOWN * cos(swing - knee) + move_dir * sin(swing - knee)
		var thigh: RigidBody3D = parts["leg_upper" + sfx]
		var shin: RigidBody3D = parts["leg_lower" + sfx]
		_drive_rotation(thigh, _arc(Vector3.DOWN, thigh_dir) * hq, pelvis, limb_frequency, 1.0, 220.0 * limb, 2.0)
		_drive_rotation(shin, _arc(Vector3.DOWN, shin_dir) * hq, thigh, limb_frequency, 1.0, 130.0 * limb)

	# Arms: two-bone IK toward the hand targets.
	_drive_arm("_r", SHOULDER_R, root_to_world(hand_target_r), hq * elbow_pole_r, limb)
	_drive_arm("_l", SHOULDER_L, root_to_world(hand_target_l), hq * elbow_pole_l, limb)


func _drive_arm(sfx: String, shoulder_rest: Vector3, target: Vector3, pole: Vector3, limb: float) -> void:
	var chest: RigidBody3D = parts.chest
	var upper: RigidBody3D = parts["arm_upper" + sfx]
	var lower: RigidBody3D = parts["arm_lower" + sfx]
	var shoulder := _shoulder_world(shoulder_rest)
	var l1 := UPPER_ARM_LENGTH
	var l2 := LOWER_ARM_LENGTH
	var to := target - shoulder
	var d := clampf(to.length(), 0.08, l1 + l2 - 0.002)
	var dir := to.normalized() if to.length_squared() > 1e-6 else Vector3.DOWN
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var perp := pole - dir * dir.dot(pole)
	if perp.length_squared() < 1e-6:
		perp = dir.cross(Vector3.RIGHT)
	perp = perp.normalized()
	var elbow := shoulder + dir * a + perp * h
	var hand := shoulder + dir * d
	_drive_direction(upper, (elbow - shoulder).normalized(), chest, limb_frequency, 1.0, 90.0 * limb, 2.0)
	_drive_direction(lower, (hand - elbow).normalized(), upper, limb_frequency, 1.0, 60.0 * limb)


func _shoulder_world(shoulder_rest: Vector3) -> Vector3:
	var chest: RigidBody3D = parts.chest
	return chest.global_transform * (shoulder_rest - (chest.get_meta("rest_offset") as Vector3))


## Clamps a world-space hand target to what the right arm can reach.
func clamp_to_reach_r(target: Vector3) -> Vector3:
	var shoulder := _shoulder_world(SHOULDER_R)
	return shoulder + (target - shoulder).limit_length(UPPER_ARM_LENGTH + LOWER_ARM_LENGTH - 0.01)


func _apply_sword(delta: float) -> void:
	if sword == null:
		return
	var chest: RigidBody3D = parts.chest
	# Track how fast the targets themselves move, so the muscles damp toward
	# the motion instead of fighting it. That keeps fast strokes snappy.
	var target := clamp_to_reach_r(root_to_world(hand_target_r))
	var target_q := sword_target.get_rotation_quaternion()
	if _has_prev_sword_target:
		var v := (target - _prev_grip_target) / delta
		var w := _quat_err(_prev_sword_q, target_q) / delta
		_grip_target_velocity = _grip_target_velocity.lerp(v, 1.0 - exp(-30.0 * delta))
		_sword_target_spin = _sword_target_spin.lerp(w, 1.0 - exp(-30.0 * delta))
	_has_prev_sword_target = true
	_prev_grip_target = target
	_prev_sword_q = target_q
	var s := strength * (1.0 - stagger * 0.5)
	if s <= 0.0:
		return
	# Grip: pull the fist (and the sword with it) toward the hand target.
	# The equal and opposite force goes into the chest, so big swings yank
	# the whole body around.
	var arm_mass: float = sword.mass + parts.arm_upper_r.mass + parts.arm_lower_r.mass
	var freq := 20.0
	var rel_v := sword.linear_velocity - _grip_target_velocity
	var f := arm_mass * ((target - sword.global_position) * freq * freq - rel_v * 2.0 * 0.9 * freq)
	f += Vector3.UP * sword.mass * GRAVITY
	f = f.limit_length(grip_force * s)
	sword.apply_force(f)
	# React at the shoulder so hard strokes twist and rock the torso.
	chest.apply_force(-f, _shoulder_world(SHOULDER_R) - chest.global_position)
	# Wrist: turn the blade toward the wanted orientation.
	var err := _quat_err(sword.global_basis.get_rotation_quaternion(), target_q)
	var t := _pd(sword, err, sword.angular_velocity - _sword_target_spin, 22.0, 0.85, wrist_torque * s, 1.4)
	sword.apply_torque(t)
	chest.apply_torque(-t)


func _update_flash(delta: float) -> void:
	for body: RigidBody3D in _flash_time.keys():
		_flash_time[body] -= delta
		if _flash_time[body] <= 0.0:
			_flash_time.erase(body)
			for mesh: MeshInstance3D in _meshes.get(body, []):
				mesh.material_overlay = null


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
