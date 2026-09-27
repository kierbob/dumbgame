class_name Player
extends ActiveRagdoll
## The player's ragdoll. WASD walks, the mouse orbits the camera, and holding
## the left mouse button hands the mouse over to the sword arm.
##
## In sword mode the mouse moves the fist around a box in front of the body.
## The blade points away from a pivot behind the right shoulder, so sweeping
## the mouse sweeps the blade in an arc. The edge turns to face the direction
## the fist is moving, so fast strokes land as cuts. Q/E roll the blade.

## The fist's reachable box in root space (x right, y up, -z forward).
const HAND_MIN := Vector3(-0.4, 0.8, -0.8)
const HAND_MAX := Vector3(0.9, 2.2, -0.1)
const GUARD := Vector3(0.24, 1.3, -0.45)
## Blades point from this root-space pivot through the fist.
const BLADE_PIVOT := Vector3(0.1, 1.28, 0.22)

@export var camera_rig: CameraRig
@export var hand_sensitivity := 0.0024
@export var reach_step := 0.05
@export var roll_speed := 3.0

var hand := GUARD
var sword_mode := false
var blade_roll := 0.0

var _edge := Vector3.UP
var _hand_velocity := Vector3.ZERO
var _prev_hand := GUARD


func _ready() -> void:
	super()
	_update_sword_target(0.0)
	equip(Sword.new())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		sword_mode = false
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				sword_mode = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				hand.z = clampf(hand.z - reach_step, HAND_MIN.z, HAND_MAX.z)
			MOUSE_BUTTON_WHEEL_DOWN:
				hand.z = clampf(hand.z + reach_step, HAND_MIN.z, HAND_MAX.z)
	elif event is InputEventMouseMotion:
		if sword_mode:
			hand.x = clampf(hand.x + event.relative.x * hand_sensitivity, HAND_MIN.x, HAND_MAX.x)
			hand.y = clampf(hand.y - event.relative.y * hand_sensitivity, HAND_MIN.y, HAND_MAX.y)
		elif camera_rig:
			camera_rig.orbit(event.relative)


func _think(delta: float) -> void:
	if camera_rig:
		heading_yaw = camera_rig.yaw
		look_pitch = camera_rig.pitch
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	move_input = Basis(Vector3.UP, heading_yaw) * Vector3(input.x, 0.0, input.y)
	sprinting = Input.is_action_pressed("sprint")
	limp = Input.is_action_pressed("go_limp")
	if Input.is_action_just_pressed("jump"):
		jump()
	if Input.is_action_just_pressed("respawn"):
		respawn()
	if Input.is_action_just_pressed("reset_guard"):
		hand = GUARD
		blade_roll = 0.0
	blade_roll += Input.get_axis("roll_left", "roll_right") * roll_speed * delta

	hand_target_r = hand
	# Shoulders twist into the stroke, which puts real weight behind it.
	chest_twist = clampf((hand.x - 0.2) * 0.6, -0.35, 0.45)
	if sword_mode:
		# Free arm flails out for balance while swinging.
		hand_target_l = Vector3(-0.55, 1.35, -0.05)
	else:
		var swing := sin(_gait_phase) * _gait_amp * 0.5
		hand_target_l = Vector3(-0.32, 1.02, -0.1 - swing)
	_update_sword_target(delta)


func _update_sword_target(delta: float) -> void:
	var hq := heading_quat()
	var blade := (hq * (hand - BLADE_PIVOT)).normalized()
	if delta > 0.0:
		var v := hq * ((hand - _prev_hand) / delta)
		_hand_velocity = _hand_velocity.lerp(v, 1.0 - exp(-18.0 * delta))
	_prev_hand = hand
	# Turn the edge toward the direction of the stroke.
	var along := _hand_velocity - blade * blade.dot(_hand_velocity)
	if along.length() > 0.35:
		# The blade has two edges, so lead with whichever is already closer.
		var lead := along.normalized() * signf(along.dot(_edge) + 1e-6)
		_edge = _edge.lerp(lead, 1.0 - exp(-25.0 * maxf(delta, 0.0)))
	_edge -= blade * blade.dot(_edge)
	if _edge.length_squared() < 1e-4:
		_edge = Vector3.UP - blade * blade.dot(Vector3.UP)
		if _edge.length_squared() < 1e-4:
			_edge = hq * Vector3.FORWARD
	_edge = _edge.normalized()
	var edge := _edge.rotated(blade, blade_roll)
	sword_target = Basis(blade.cross(edge).normalized(), blade, edge)


func respawn() -> void:
	super()
	hand = GUARD
	_prev_hand = GUARD
	_hand_velocity = Vector3.ZERO
	if camera_rig:
		camera_rig.yaw = heading_yaw
		camera_rig.snap()
