extends Node3D
## Wires the pit together: weapon hits become wounds, wounds become sounds and
## HUD readouts, and T brings in a fresh sparring partner.

const FALL_SOUND := preload("res://assets/kenney_platformer_kit/sounds/fall.ogg")

@export var player: Player
@export var dummy: TrainingDummy
@export var hud: Hud


func _ready() -> void:
	player.sword.hit.connect(_on_sword_hit)
	player.sword.clanged.connect(_on_clang)
	for fighter: ActiveRagdoll in [player, dummy]:
		fighter.wounded.connect(_on_wounded.bind(fighter))
		fighter.knocked_down.connect(_on_fall.bind(fighter))
		fighter.severed.connect(func(body: RigidBody3D) -> void:
			_play(Sfx.cut(), body.global_position, 0.7, 2.0))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_dummy"):
		dummy.respawn()


func _process(_delta: float) -> void:
	hud.show_fighter(dummy)
	hud.show_player(player)


func _on_sword_hit(target: ActiveRagdoll, body: RigidBody3D, point: Vector3, direction: Vector3,
		speed: float, edge: float, pierce: float) -> void:
	if is_instance_valid(body):
		target.receive_hit(body, point, direction, speed, edge, player.sword.mass, pierce)


func _on_wounded(body: RigidBody3D, damage: float, kind: String, point: Vector3, who: ActiveRagdoll) -> void:
	match kind:
		"cut", "stab":
			_play(Sfx.cut(), point, randf_range(0.85, 1.15), -6.0 + minf(damage, 60.0) * 0.12)
		"armor":
			_play(Sfx.clang(), point, randf_range(0.9, 1.1), -2.0)
		_:
			_play(Sfx.thud(), point, randf_range(0.85, 1.15), -6.0 + minf(damage, 40.0) * 0.15)
	if who == dummy:
		hud.log_hit(String(body.name), kind, damage)


func _on_clang(point: Vector3, speed: float) -> void:
	_play(Sfx.clang(), point, randf_range(1.2, 1.5), -16.0 + minf(speed, 8.0))


func _on_fall(who: ActiveRagdoll) -> void:
	_play(FALL_SOUND, who.parts.chest.global_position, randf_range(0.8, 0.95), -8.0)


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
