class_name Sword
extends RigidBody3D
## A longsword built from primitives. Its origin is the grip, where the fist
## holds it. The blade runs along local +Y and the cutting edges face local ±Z.
##
## Reports hits on ragdolls with the impact speed and how cleanly the edge
## (rather than the flat) met the target.

## Emitted on a hit against another fighter's body part. direction is the
## blade's motion relative to the target; edge is 1.0 for a clean edge cut
## and 0.0 for a slap with the flat; pierce is 1.0 for a point-first thrust.
signal hit(target: ActiveRagdoll, body: RigidBody3D, point: Vector3, direction: Vector3,
		speed: float, edge: float, pierce: float)
## Emitted when the blade bangs into something that is not a ragdoll.
signal clanged(point: Vector3, speed: float)

const BLADE_LENGTH := 0.9
const HIT_COOLDOWN := 0.25
## Where the off hand grabs the blade for the half-sword grip.
const HALF_GRIP := 0.3

@export var blade_color := Color(0.74, 0.76, 0.78)
@export var hilt_color := Color(0.22, 0.13, 0.08)

var wielder: ActiveRagdoll

var _last_hit := {}
var _whoosh: AudioStreamPlayer3D
var _whoosh_playback: AudioStreamGeneratorPlayback
var _prev_tip := Vector3.ZERO
var _tip_speed := 0.0
var _noise_lp := 0.0
var _noise_lp2 := 0.0
var _whoosh_amp := 0.0
var _last_clang := 0.0
var _touching := {}


func _init() -> void:
	name = "Sword"
	mass = 1.5
	center_of_mass_mode = CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.16, 0)
	inertia = Vector3(0.14, 0.005, 0.14)
	collision_layer = 4
	collision_mask = 1 | 8
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 8
	can_sleep = false
	angular_damp = 0.5
	var phys := PhysicsMaterial.new()
	phys.friction = 0.4
	physics_material_override = phys
	_build()


func _ready() -> void:
	# Wind noise whose loudness and pitch follow the speed of the tip.
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.12
	_whoosh = AudioStreamPlayer3D.new()
	_whoosh.stream = gen
	_whoosh.unit_size = 4.0
	_whoosh.volume_db = -4.0
	add_child(_whoosh)
	_whoosh.play()
	_whoosh_playback = _whoosh.get_stream_playback() as AudioStreamGeneratorPlayback
	_prev_tip = tip_position()


func _process(delta: float) -> void:
	var tip := tip_position()
	if delta > 0.0:
		_tip_speed = lerpf(_tip_speed, tip.distance_to(_prev_tip) / delta, 1.0 - exp(-20.0 * delta))
	_prev_tip = tip
	if _whoosh_playback == null:
		return
	var target_amp := clampf((_tip_speed - 5.0) / 18.0, 0.0, 1.0)
	var brightness := clampf(0.04 + _tip_speed * 0.012, 0.04, 0.45)
	for i in _whoosh_playback.get_frames_available():
		_whoosh_amp += (target_amp - _whoosh_amp) * 0.002
		var n := randf() * 2.0 - 1.0
		_noise_lp += (n - _noise_lp) * brightness
		_noise_lp2 += (_noise_lp - _noise_lp2) * brightness * 0.5
		var v := (_noise_lp - _noise_lp2) * _whoosh_amp * 2.5
		_whoosh_playback.push_frame(Vector2(v, v))


func _build() -> void:
	var blade_mat := StandardMaterial3D.new()
	blade_mat.albedo_color = blade_color
	blade_mat.metallic = 0.95
	blade_mat.roughness = 0.3
	var fuller_mat := StandardMaterial3D.new()
	fuller_mat.albedo_color = blade_color.darkened(0.35)
	fuller_mat.metallic = 0.95
	fuller_mat.roughness = 0.4
	var iron := Looks.steel()
	var leather := Looks.cloth(hilt_color, 0.7, 0.15)

	# Longsword: tapering blade with a fuller, straight cross-guard, a long
	# leather grip for two hands and a wheel pommel.
	var base := 0.12
	var blade_mesh := CylinderMesh.new()
	blade_mesh.top_radius = 0.018
	blade_mesh.bottom_radius = 0.028
	blade_mesh.height = BLADE_LENGTH
	blade_mesh.radial_segments = 4
	blade_mesh.rings = 1
	# A 4-sided cylinder squashed flat reads as a diamond-section blade.
	_mesh(blade_mesh, Vector3(0, base + BLADE_LENGTH * 0.5, 0),
			Basis(Vector3.UP, PI * 0.25).scaled(Vector3(0.28, 1.0, 1.0)), blade_mat)
	var tip := CylinderMesh.new()
	tip.top_radius = 0.0
	tip.bottom_radius = 0.018
	tip.height = 0.1
	tip.radial_segments = 4
	tip.rings = 1
	_mesh(tip, Vector3(0, base + BLADE_LENGTH + 0.05, 0),
			Basis(Vector3.UP, PI * 0.25).scaled(Vector3(0.28, 1.0, 1.0)), blade_mat)
	var fuller := BoxMesh.new()
	fuller.size = Vector3(0.0125, BLADE_LENGTH * 0.6, 0.008)
	_mesh(fuller, Vector3(0, base + BLADE_LENGTH * 0.32, 0), Basis.IDENTITY, fuller_mat)
	var guard := BoxMesh.new()
	guard.size = Vector3(0.022, 0.022, 0.24)
	_mesh(guard, Vector3(0, 0.1, 0), Basis.IDENTITY, iron)
	var grip := CylinderMesh.new()
	grip.top_radius = 0.016
	grip.bottom_radius = 0.019
	grip.height = 0.24
	_mesh(grip, Vector3(0, -0.03, 0), Basis.IDENTITY, leather)
	var pommel := CylinderMesh.new()
	pommel.top_radius = 0.032
	pommel.bottom_radius = 0.032
	pommel.height = 0.02
	_mesh(pommel, Vector3(0, -0.16, 0), Basis(Vector3.FORWARD, PI * 0.5), iron)

	# Slightly fat collision shapes so fast swings don't tunnel through.
	_shape(Vector3(0.03, BLADE_LENGTH + 0.08, 0.07), Vector3(0, base + (BLADE_LENGTH + 0.08) * 0.5, 0))
	_shape(Vector3(0.04, 0.04, 0.24), Vector3(0, 0.1, 0))


func _mesh(mesh: Mesh, pos: Vector3, basis: Basis, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = Transform3D(basis, pos)
	mi.material_override = mat
	add_child(mi)


func _shape(size: Vector3, pos: Vector3) -> void:
	var box := BoxShape3D.new()
	box.size = size
	var col := CollisionShape3D.new()
	col.shape = box
	col.position = pos
	add_child(col)


## World position of the off-hand grab point on the blade.
func half_grip_position() -> Vector3:
	return global_transform * Vector3(0, HALF_GRIP, 0)


## World position of the blade tip.
func tip_position() -> Vector3:
	return global_transform * Vector3(0, 0.12 + BLADE_LENGTH + 0.1, 0)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var edge_dir := state.transform.basis.z.normalized()
	var touching := {}
	for i in state.get_contact_count():
		var other := state.get_contact_collider_object(i)
		if other == null:
			continue
		var fresh := not _touching.has(other)
		touching[other] = true
		if not fresh:
			continue
		# Closing speed along the contact normal, so scraping along something
		# (or leaning on it) does not count as a hit.
		var rel := state.get_contact_local_velocity_at_position(i) - state.get_contact_collider_velocity_at_position(i)
		var speed := maxf(absf(rel.dot(state.get_contact_local_normal(i))),
				rel.dot(state.transform.basis.y.normalized()))
		var point := state.get_contact_collider_position(i)
		if other.has_meta("ragdoll"):
			var target: ActiveRagdoll = other.get_meta("ragdoll")
			if target == wielder or speed < 1.5:
				continue
			if now - float(_last_hit.get(target, -10.0)) < HIT_COOLDOWN:
				continue
			_last_hit[target] = now
			var edge := absf(rel.normalized().dot(edge_dir))
			# Point-first: moving along the blade and touching near the tip.
			var along := rel.normalized().dot(state.transform.basis.y.normalized())
			var near_tip := (state.transform.affine_inverse() * point).y > BLADE_LENGTH * 0.55
			var pierce := clampf(along, 0.0, 1.0) if near_tip else 0.0
			hit.emit.call_deferred(target, other, point, rel.normalized(), speed, edge, pierce)
		elif speed > 3.0 and now - _last_clang > 0.2:
			_last_clang = now
			clanged.emit.call_deferred(point, speed)
	_touching = touching
