class_name Gore
extends RefCounted
## Blood effects: spray bursts, dripping wounds and stains on bodies and on
## the ground. Stains are decals, so they stick to whatever they land on.

const BLOOD := Color(0.3, 0.015, 0.015)
const MAX_STAINS := 120

static var _splats: Array[Texture2D] = []
static var _stains: Array[Decal] = []
static var _drop: Mesh


## A one-shot spray of droplets flying out along dir.
static func burst(parent: Node, point: Vector3, dir: Vector3, amount: int, speed := 3.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = maxi(amount, 1)
	p.lifetime = 1.0
	p.local_coords = false
	p.mesh = _drop_mesh()
	p.direction = dir.normalized() if dir.length_squared() > 1e-4 else Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = speed * 0.3
	p.initial_velocity_max = speed
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.8
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(p)
	p.global_position = point
	p.emitting = true
	p.finished.connect(p.queue_free)


## A continuous drip attached to a wound. Toggle emitting to start/stop it.
static func bleeder(body: Node3D, local_point: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 20
	p.lifetime = 0.8
	p.local_coords = false
	p.mesh = _drop_mesh()
	p.direction = Vector3.DOWN
	p.spread = 25.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.9
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.emitting = false
	body.add_child(p)
	p.position = local_point
	return p


## A blood stain projected onto whatever is under point, facing normal.
static func stain(parent: Node, point: Vector3, normal: Vector3, size: float, depth := 0.25) -> void:
	var d := Decal.new()
	d.texture_albedo = _splat()
	d.modulate = BLOOD
	d.albedo_mix = 0.92
	d.size = Vector3(size, depth, size)
	d.upper_fade = 0.2
	d.lower_fade = 0.5
	parent.add_child(d)
	var y := normal.normalized() if normal.length_squared() > 1e-4 else Vector3.UP
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 1e-4:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized().rotated(y, randf() * TAU)
	d.global_transform = Transform3D(Basis(x, y, x.cross(y)), point)
	_stains.append(d)
	while _stains.size() > MAX_STAINS:
		var old: Decal = _stains.pop_front()
		if is_instance_valid(old):
			old.queue_free()


static func _drop_mesh() -> Mesh:
	if _drop:
		return _drop
	var sphere := SphereMesh.new()
	sphere.radius = 0.011
	sphere.height = 0.022
	sphere.radial_segments = 6
	sphere.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BLOOD
	mat.roughness = 0.15
	sphere.material = mat
	_drop = sphere
	return _drop


## A few random splat shapes drawn once into small textures.
static func _splat() -> Texture2D:
	if _splats.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 1337
		for variant in 4:
			_splats.append(_draw_splat(rng))
	return _splats[randi() % _splats.size()]


static func _draw_splat(rng: RandomNumberGenerator) -> Texture2D:
	var size := 96
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var blobs: Array[Vector3] = [Vector3(48, 48, rng.randf_range(16, 22))]
	for i in rng.randi_range(8, 14):
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(14, 40)
		blobs.append(Vector3(48 + cos(ang) * dist, 48 + sin(ang) * dist, rng.randf_range(2, 8)))
	for y in size:
		for x in size:
			var a := 0.0
			for b in blobs:
				var d := Vector2(x - b.x, y - b.y).length()
				a = maxf(a, clampf((b.z - d) / 2.5 + 0.5, 0.0, 1.0))
			if a > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
