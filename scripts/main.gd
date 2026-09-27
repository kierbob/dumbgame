extends Node3D
## Wires the arena together: sword hits turn into damage numbers, sounds and
## HUD stats, and a stack of crates gets built for knocking over.

const HIT_SOUND := preload("res://assets/kenney_fps_kit/sounds/enemy_hurt.ogg")
const CLANG_SOUND := preload("res://assets/kenney_fps_kit/sounds/weapon_change.ogg")
const FALL_SOUND := preload("res://assets/kenney_platformer_kit/sounds/fall.ogg")
const JUMP_SOUND := preload("res://assets/kenney_fps_kit/sounds/jump_a.ogg")
const LAND_SOUND := preload("res://assets/kenney_fps_kit/sounds/land.ogg")
const CRATE_TEXTURE := preload("res://addons/kenney_prototype_textures/orange/texture_08.png")

## Damage per m/s of relative blade speed.
const DAMAGE_PER_SPEED := 6.0

@export var player: Player
@export var dummy: TrainingDummy
@export var hud: Hud
@export var crate_origin := Vector3(-6, 0, -3)


func _ready() -> void:
	player.sword.hit.connect(_on_sword_hit)
	player.sword.clanged.connect(_on_clang)
	dummy.knocked_down.connect(_on_knocked.bind(dummy))
	player.knocked_down.connect(_on_knocked.bind(player))
	player.jumped.connect(func() -> void:
		_play(JUMP_SOUND, player.parts.pelvis.global_position, randf_range(0.95, 1.1), -6.0))
	player.landed.connect(func(speed: float) -> void:
		_play(LAND_SOUND, player.parts.pelvis.global_position, randf_range(0.9, 1.1), -12.0 + minf(speed, 6.0) * 1.5))
	_build_crates()


func _process(_delta: float) -> void:
	hud.set_sword_state(player.hand, player.sword_mode, player.blade_roll)
	hud.set_status(player.is_down(), dummy.is_down())


func _on_sword_hit(target: ActiveRagdoll, body: RigidBody3D, point: Vector3, speed: float, edge: float) -> void:
	var part_bonus := 1.5 if body.name == "head" else 1.0
	var damage := roundi(speed * DAMAGE_PER_SPEED * lerpf(0.5, 1.4, edge) * part_bonus)
	target.take_hit(body, speed)
	var kind := "CUT" if edge > 0.6 else ("SLAP" if edge < 0.3 else "")
	if body.name == "head":
		kind = "HEAD" + (" " + kind if kind else "")
	_spawn_number(point, damage, kind)
	_play(HIT_SOUND, point, clampf(0.8 + speed * 0.03, 0.8, 1.4), -4.0 + minf(speed, 12.0))
	hud.add_hit(damage, speed)


func _on_clang(point: Vector3, speed: float) -> void:
	_play(CLANG_SOUND, point, randf_range(1.3, 1.6), -14.0 + minf(speed, 8.0))


func _on_knocked(who: ActiveRagdoll) -> void:
	_play(FALL_SOUND, who.parts.chest.global_position, randf_range(0.9, 1.1), -4.0)


func _spawn_number(point: Vector3, damage: int, kind: String) -> void:
	var label := Label3D.new()
	label.text = str(damage) if kind.is_empty() else "%d  %s" % [damage, kind]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.001
	label.font_size = 26 + mini(damage, 120) / 6
	label.outline_size = 8
	label.modulate = Color(1, 0.92, 0.3) if damage < 60 else Color(1, 0.35, 0.25)
	label.outline_modulate = Color(0.1, 0.05, 0.05)
	label.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(label)
	label.global_position = point + Vector3(randf_range(-0.35, 0.35), randf_range(0.1, 0.4), 0)
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "global_position", label.global_position + Vector3.UP * 0.7, 0.9) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(label, "modulate:a", 0.0, 0.4).set_delay(0.5)
	tween.chain().tween_callback(label.queue_free)


func _play(stream: AudioStream, point: Vector3, pitch: float, volume_db: float) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(p)
	p.global_position = point
	p.finished.connect(p.queue_free)
	p.play()


func _build_crates() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = CRATE_TEXTURE
	mat.uv1_scale = Vector3(3, 2, 1)
	var size := 0.5
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * size
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size
	mesh.material = mat
	var rows := 4
	for row in rows:
		for i in rows - row:
			var crate := RigidBody3D.new()
			crate.name = "Crate"
			crate.mass = 4.0
			crate.collision_layer = 1
			crate.collision_mask = 1 | 2 | 4 | 8
			var col := CollisionShape3D.new()
			col.shape = shape
			crate.add_child(col)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			crate.add_child(mi)
			add_child(crate)
			var x := (i - (rows - row - 1) * 0.5) * (size + 0.02)
			crate.global_position = crate_origin + Vector3(x, size * 0.5 + row * size, 0)
