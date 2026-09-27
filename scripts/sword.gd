class_name Sword
extends RigidBody3D
## A longsword built from primitives. Its origin is the grip, where the fist
## holds it. The blade runs along local +Y and the cutting edges face local ±Z.
##
## Reports hits on ragdolls with the impact speed and how cleanly the edge
## (rather than the flat) met the target.

## Emitted on a hit against another ragdoll's body part.
## edge is 1.0 for a clean edge cut and 0.0 for a slap with the flat.
signal hit(target: ActiveRagdoll, body: RigidBody3D, point: Vector3, speed: float, edge: float)
## Emitted when the blade bangs into something that is not a ragdoll.
signal clanged(point: Vector3, speed: float)

const BLADE_LENGTH := 0.9
const HIT_COOLDOWN := 0.25

@export var blade_color := Color(0.82, 0.85, 0.9)
@export var hilt_color := Color(0.35, 0.22, 0.12)
@export var guard_color := Color(0.85, 0.66, 0.25)

var wielder: ActiveRagdoll

var _last_hit := {}
var _last_clang := 0.0
var _touching := {}


func _init() -> void:
	name = "Sword"
	mass = 1.6
	center_of_mass_mode = CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.2, 0)
	inertia = Vector3(0.15, 0.006, 0.15)
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


func _build() -> void:
	var blade_mat := StandardMaterial3D.new()
	blade_mat.albedo_color = blade_color
	blade_mat.metallic = 0.9
	blade_mat.roughness = 0.25
	var hilt_mat := StandardMaterial3D.new()
	hilt_mat.albedo_color = hilt_color
	hilt_mat.roughness = 0.9
	var guard_mat := StandardMaterial3D.new()
	guard_mat.albedo_color = guard_color
	guard_mat.metallic = 0.7
	guard_mat.roughness = 0.35

	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.012, BLADE_LENGTH, 0.055)
	_mesh(blade_mesh, Vector3(0, 0.12 + BLADE_LENGTH * 0.5, 0), Basis.IDENTITY, blade_mat)
	var tip := PrismMesh.new()
	tip.size = Vector3(0.055, 0.11, 0.012)
	_mesh(tip, Vector3(0, 0.12 + BLADE_LENGTH + 0.055, 0), Basis(Vector3.UP, PI * 0.5), blade_mat)
	var guard := BoxMesh.new()
	guard.size = Vector3(0.035, 0.035, 0.26)
	_mesh(guard, Vector3(0, 0.1, 0), Basis.IDENTITY, guard_mat)
	var grip := CylinderMesh.new()
	grip.top_radius = 0.021
	grip.bottom_radius = 0.021
	grip.height = 0.2
	_mesh(grip, Vector3(0, -0.02, 0), Basis.IDENTITY, hilt_mat)
	var pommel := SphereMesh.new()
	pommel.radius = 0.035
	pommel.height = 0.07
	_mesh(pommel, Vector3(0, -0.13, 0), Basis.IDENTITY, guard_mat)

	# Slightly fat collision shapes so fast swings don't tunnel through.
	_shape(Vector3(0.03, BLADE_LENGTH + 0.08, 0.07), Vector3(0, 0.12 + (BLADE_LENGTH + 0.08) * 0.5, 0))
	_shape(Vector3(0.04, 0.04, 0.26), Vector3(0, 0.1, 0))


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
		var speed := absf(rel.dot(state.get_contact_local_normal(i)))
		var point := state.get_contact_collider_position(i)
		if other.has_meta("ragdoll"):
			var target: ActiveRagdoll = other.get_meta("ragdoll")
			if target == wielder or speed < 1.5:
				continue
			if now - float(_last_hit.get(target, -10.0)) < HIT_COOLDOWN:
				continue
			_last_hit[target] = now
			var edge := absf(rel.normalized().dot(edge_dir))
			hit.emit.call_deferred(target, other, point, speed, edge)
		elif speed > 3.0 and now - _last_clang > 0.2:
			_last_clang = now
			clanged.emit.call_deferred(point, speed)
	_touching = touching
