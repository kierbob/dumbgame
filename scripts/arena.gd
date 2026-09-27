extends Node3D
## A small dirt fighting pit: a ring of sharpened palisade logs, straw bales,
## a pell (training post), a weapon rack and some barrels and crates that can
## be knocked around. Everything is built here from primitives and the
## procedural materials in Looks.

@export var radius := 11.0
@export var log_radius := 0.16

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 42
	_build_ground()
	_build_palisade()
	_build_props()


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	var shape := BoxShape3D.new()
	shape.size = Vector3(120, 1, 120)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, -0.5, 0)
	body.add_child(col)
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = Looks.dirt()
	body.add_child(mi)
	add_child(body)


func _build_palisade() -> void:
	var wood := Looks.wood()
	var count := int(TAU * radius / (log_radius * 2.05))
	var log_mesh := CylinderMesh.new()
	log_mesh.top_radius = log_radius * 0.9
	log_mesh.bottom_radius = log_radius
	log_mesh.height = 1.0
	log_mesh.radial_segments = 10
	var tip_mesh := CylinderMesh.new()
	tip_mesh.top_radius = 0.0
	tip_mesh.bottom_radius = log_radius * 0.9
	tip_mesh.height = 0.35
	tip_mesh.radial_segments = 10
	var logs := MultiMesh.new()
	logs.transform_format = MultiMesh.TRANSFORM_3D
	logs.mesh = log_mesh
	logs.instance_count = count
	var tips := MultiMesh.new()
	tips.transform_format = MultiMesh.TRANSFORM_3D
	tips.mesh = tip_mesh
	tips.instance_count = count
	for i in count:
		var ang := TAU * i / count
		var h := _rng.randf_range(2.6, 3.3)
		var pos := Vector3(cos(ang), 0, sin(ang)) * (radius + _rng.randf_range(-0.04, 0.04))
		var tilt := Basis(Vector3(-sin(ang), 0, cos(ang)), _rng.randf_range(-0.04, 0.04)) \
				* Basis(Vector3.UP, _rng.randf() * TAU)
		logs.set_instance_transform(i, Transform3D(tilt.scaled_local(Vector3(1, h, 1)), pos + tilt * Vector3(0, h * 0.5, 0)))
		tips.set_instance_transform(i, Transform3D(tilt, pos + tilt * Vector3(0, h + 0.175, 0)))
	for mm: MultiMesh in [logs, tips]:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = wood
		add_child(mmi)
	# Collision: flat panels around the ring.
	var wall := StaticBody3D.new()
	wall.name = "Palisade"
	var segments := 36
	for i in segments:
		var ang := TAU * (i + 0.5) / segments
		var box := BoxShape3D.new()
		box.size = Vector3(TAU * radius / segments + 0.1, 3.0, 0.4)
		var col := CollisionShape3D.new()
		col.shape = box
		col.transform = Transform3D(Basis(Vector3.UP, -ang + PI * 0.5), Vector3(cos(ang), 0, sin(ang)) * radius + Vector3.UP * 1.5)
		wall.add_child(col)
	add_child(wall)
	# Cross rails on the inside.
	for y: float in [0.6, 2.1]:
		for i in segments:
			var a0 := TAU * i / segments
			var a1 := TAU * (i + 1) / segments
			var p0 := Vector3(cos(a0), 0, sin(a0)) * (radius - log_radius * 1.4)
			var p1 := Vector3(cos(a1), 0, sin(a1)) * (radius - log_radius * 1.4)
			var rail := CylinderMesh.new()
			rail.top_radius = 0.06
			rail.bottom_radius = 0.06
			rail.height = p0.distance_to(p1) + 0.1
			rail.radial_segments = 8
			var mi := MeshInstance3D.new()
			mi.mesh = rail
			mi.material_override = wood
			var dir := (p1 - p0).normalized()
			mi.transform = Transform3D(Basis(ActiveRagdoll._arc(Vector3.UP, dir)), (p0 + p1) * 0.5 + Vector3.UP * y)
			add_child(mi)


func _build_props() -> void:
	# Straw bales along the wall.
	for spot: Vector3 in [Vector3(-7.5, 0, -6.5), Vector3(-8.6, 0, -4.8), Vector3(-7.9, 0.5, -5.7), Vector3(8.2, 0, 5.5)]:
		_static_box("Bale", Vector3(1.1, 0.5, 0.55), spot + Vector3.UP * 0.25, _rng.randf_range(-0.6, 0.6), Looks.straw())
	# Pell: a thick training post, good for practising cuts.
	_static_cylinder("Pell", 0.13, 1.9, Vector3(4.5, 0.95, -3.5), Looks.wood())
	# Weapon rack against the wall.
	var rack_pos := Vector3(-2.5, 0, -10.2)
	for x: float in [-0.7, 0.7]:
		_static_box("RackLeg", Vector3(0.08, 1.2, 0.08), rack_pos + Vector3(x, 0.6, 0), 0.0, Looks.wood())
	_static_box("RackBar", Vector3(1.6, 0.07, 0.1), rack_pos + Vector3(0, 1.05, 0), 0.0, Looks.wood())
	_static_box("RackBar", Vector3(1.6, 0.07, 0.1), rack_pos + Vector3(0, 0.35, 0.12), 0.0, Looks.wood())
	for i in 4:
		var spear := CylinderMesh.new()
		spear.top_radius = 0.018
		spear.bottom_radius = 0.018
		spear.height = 1.9
		var mi := MeshInstance3D.new()
		mi.mesh = spear
		mi.material_override = Looks.wood()
		mi.transform = Transform3D(Basis(Vector3.RIGHT, -0.18), rack_pos + Vector3(-0.5 + i * 0.33, 0.95, -0.05))
		add_child(mi)
	# Loose barrels and crates.
	for spot: Vector3 in [Vector3(6.5, 0, -6.8), Vector3(7.1, 0, -6.1), Vector3(-6.2, 0, 6.9)]:
		_barrel(spot)
	for spot: Vector3 in [Vector3(-3.5, 0, 7.8), Vector3(-3.0, 0.61, 7.8), Vector3(-2.4, 0, 8.3)]:
		_crate(spot)


func _static_box(node_name: String, size: Vector3, pos: Vector3, yaw: float, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)
	body.transform = Transform3D(Basis(Vector3.UP, yaw), pos)


func _static_cylinder(node_name: String, r: float, h: float, pos: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = h
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r * 1.05
	mesh.height = h
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)
	body.position = pos


func _barrel(pos: Vector3) -> void:
	var body := RigidBody3D.new()
	body.name = "Barrel"
	body.mass = 15.0
	body.collision_mask = 1 | 2 | 4 | 8
	var shape := CylinderShape3D.new()
	shape.radius = 0.3
	shape.height = 0.85
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.27
	mesh.bottom_radius = 0.27
	mesh.height = 0.85
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Looks.wood()
	body.add_child(mi)
	var belly := CylinderMesh.new()
	belly.top_radius = 0.3
	belly.bottom_radius = 0.3
	belly.height = 0.45
	var bm := MeshInstance3D.new()
	bm.mesh = belly
	bm.material_override = Looks.wood()
	body.add_child(bm)
	for y: float in [-0.3, 0.3]:
		var hoop := CylinderMesh.new()
		hoop.top_radius = 0.29
		hoop.bottom_radius = 0.29
		hoop.height = 0.04
		var hm := MeshInstance3D.new()
		hm.mesh = hoop
		hm.material_override = Looks.steel()
		hm.position = Vector3(0, y, 0)
		body.add_child(hm)
	add_child(body)
	body.position = pos + Vector3.UP * 0.43


func _crate(pos: Vector3) -> void:
	var body := RigidBody3D.new()
	body.name = "Crate"
	body.mass = 8.0
	body.collision_mask = 1 | 2 | 4 | 8
	var size := Vector3(0.6, 0.6, 0.6)
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Looks.wood()
	body.add_child(mi)
	add_child(body)
	body.transform = Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.4, 0.4)), pos + Vector3.UP * 0.3)
