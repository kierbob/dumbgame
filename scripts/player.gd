class_name Player
extends ActiveRagdoll
## Half Sword style controls.
##
## The mouse turns the camera and body. Hold the left button and the mouse
## drags your weapon hand instead: the fist travels over a sphere around the
## shoulder, so dragging sideways sweeps a real arc, and the blade points
## outward from a pivot behind the shoulder. The edge turns into the stroke
## on its own. The weapon is a physics object with weight, so wind up, drag
## through and let it follow through.
##
## Hold the right button for the half-sword grip (off hand on the blade:
## more control, less reach). Hold Alt or the middle button to bring the
## point in line, then push the mouse forward to thrust.

const GUARD_YAW := 0.1
const GUARD_PITCH := -0.15
const GUARD_REACH := 0.42
const YAW_RANGE := Vector2(-1.5, 1.45)
const PITCH_RANGE := Vector2(-1.2, 1.4)
const REACH_RANGE := Vector2(0.16, 0.57)
const HALF_SWORD_REACH := 0.4
## Half-sword stance: fist low and close, blade angled across the body so the
## off hand can grab it.
const HALF_YAW := -0.75
const HALF_PITCH := -0.55
const HALF_REACH_START := 0.24
const HALF_BLADE := Vector3(-0.25, 0.32, -0.9)
## Blades point from this spot (relative to the shoulder) through the fist.
const BLADE_PIVOT := Vector3(-0.12, -0.38, 0.32)

@export var camera_rig: CameraRig
## Radians of arm swing per pixel of mouse movement.
@export var arm_sensitivity := 0.0032
@export var thrust_sensitivity := 0.0022
@export var roll_speed := 3.0
## How quickly the arm settles back to guard once you let go (per second).
@export var guard_return := 1.2

var arm_yaw := GUARD_YAW
var arm_pitch := GUARD_PITCH
var reach := GUARD_REACH
var blade_roll := 0.0
## Weapon hand position in root space (for the HUD).
var hand := Vector3.ZERO
var sword_mode := false
var thrusting := false

var _lmb := false
var _rmb := false
var _edge := Vector3.UP
var _hand_velocity := Vector3.ZERO
var _prev_hand := Vector3.ZERO
var _shift_down_time := -1.0


func _ready() -> void:
	super()
	hand = _hand_from_angles()
	_prev_hand = hand
	_update_sword_target(0.0)
	equip(Sword.new())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_lmb = false
		_rmb = false
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_lmb = event.pressed
			MOUSE_BUTTON_RIGHT:
				_rmb = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				reach = clampf(reach + 0.03, REACH_RANGE.x, REACH_RANGE.y)
			MOUSE_BUTTON_WHEEL_DOWN:
				reach = clampf(reach - 0.03, REACH_RANGE.x, REACH_RANGE.y)
	elif event is InputEventMouseMotion:
		var rel: Vector2 = event.relative
		if thrusting:
			# Push the mouse forward to drive the point in.
			reach = clampf(reach - rel.y * thrust_sensitivity, REACH_RANGE.x, REACH_RANGE.y)
			arm_yaw = clampf(arm_yaw + rel.x * arm_sensitivity * 0.3, YAW_RANGE.x, YAW_RANGE.y)
		elif _lmb or _rmb:
			arm_yaw = clampf(arm_yaw + rel.x * arm_sensitivity, YAW_RANGE.x, YAW_RANGE.y)
			arm_pitch = clampf(arm_pitch - rel.y * arm_sensitivity, PITCH_RANGE.x, PITCH_RANGE.y)
		elif camera_rig:
			camera_rig.orbit(rel)
	elif event.is_action_pressed("lock_on") and camera_rig:
		camera_rig.toggle_lock()
	elif event.is_action_pressed("toggle_view") and camera_rig:
		camera_rig.first_person = not camera_rig.first_person


func _think(delta: float) -> void:
	if camera_rig:
		heading_yaw = camera_rig.yaw
		look_pitch = camera_rig.pitch
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	move_input = Basis(Vector3.UP, heading_yaw) * Vector3(input.x, 0.0, input.y)
	crouching = Input.is_action_pressed("crouch")
	limp = Input.is_action_pressed("go_limp")
	_handle_shift(input)
	if Input.is_action_just_pressed("kick"):
		kick()
	if Input.is_action_just_pressed("respawn"):
		respawn()
	if Input.is_action_just_pressed("reset_guard"):
		arm_yaw = GUARD_YAW
		arm_pitch = GUARD_PITCH
		reach = GUARD_REACH
		blade_roll = 0.0
	blade_roll += Input.get_axis("roll_left", "roll_right") * roll_speed * delta

	sword_mode = _lmb or _rmb
	thrusting = Input.is_action_pressed("thrust")
	half_sword = _rmb
	if not sword_mode and not thrusting:
		# Arm settles back into a guard when you let go of it.
		var k := 1.0 - exp(-guard_return * delta)
		arm_yaw = lerpf(arm_yaw, GUARD_YAW, k)
		arm_pitch = lerpf(arm_pitch, GUARD_PITCH, k)
		reach = lerpf(reach, GUARD_REACH, k)
	if half_sword:
		if not half_sword_held:
			# Pull the sword in across the body until the off hand has it.
			var k := 1.0 - exp(-10.0 * delta)
			arm_yaw = lerpf(arm_yaw, HALF_YAW, k)
			arm_pitch = lerpf(arm_pitch, HALF_PITCH, k)
			reach = lerpf(reach, HALF_REACH_START, k)
		reach = minf(reach, HALF_SWORD_REACH)

	hand = _hand_from_angles()
	hand_target_r = hand
	chest_twist = clampf(arm_yaw * 0.3, -0.4, 0.4)
	if half_sword:
		# Turn the off shoulder forward so that hand can reach the blade.
		chest_twist = 0.3
	if sword_mode and not half_sword:
		# Free arm swings out for balance.
		hand_target_l = Vector3(-0.45, 1.15, -0.12)
	else:
		hand_target_l = Vector3(-0.2, 1.05, -0.28)
	_update_sword_target(delta)


## Tap Shift while moving to dodge; hold it to sprint.
func _handle_shift(input: Vector2) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if Input.is_action_just_pressed("sprint"):
		_shift_down_time = now
	if Input.is_action_just_released("sprint") and _shift_down_time > 0.0:
		if now - _shift_down_time < 0.2:
			var dir := move_input if input.length() > 0.1 else heading_quat() * Vector3.BACK
			dodge(dir)
		_shift_down_time = -1.0
	sprinting = Input.is_action_pressed("sprint") and now - _shift_down_time >= 0.2


func _hand_from_angles() -> Vector3:
	var dir := Vector3(sin(arm_yaw) * cos(arm_pitch), sin(arm_pitch), -cos(arm_yaw) * cos(arm_pitch))
	return SHOULDER_R + dir * reach


func _update_sword_target(delta: float) -> void:
	var hq := heading_quat()
	var blade := (hq * (hand - (SHOULDER_R + BLADE_PIVOT))).normalized()
	if half_sword:
		# Both hands on the weapon: it turns with the arms around the stance.
		var turn := Basis(Vector3.UP, -(arm_yaw - HALF_YAW)) * Basis(Vector3.RIGHT, arm_pitch - HALF_PITCH)
		blade = (hq * (turn * HALF_BLADE)).normalized()
	if thrusting and camera_rig:
		# Point in line from the fist to whatever is under the crosshair.
		var fist := root_to_world(hand)
		var aim := (camera_rig.aim_point() - fist).normalized()
		blade = blade.lerp(aim, 0.9).normalized()
	if delta > 0.0:
		var v := hq * ((hand - _prev_hand) / delta)
		_hand_velocity = _hand_velocity.lerp(v, 1.0 - exp(-18.0 * delta))
	_prev_hand = hand
	# Turn the edge toward the direction of the stroke. The blade has two
	# edges, so lead with whichever is already closer.
	var along := _hand_velocity - blade * blade.dot(_hand_velocity)
	if along.length() > 0.3:
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
	arm_yaw = GUARD_YAW
	arm_pitch = GUARD_PITCH
	reach = GUARD_REACH
	hand = _hand_from_angles()
	_prev_hand = hand
	_hand_velocity = Vector3.ZERO
	if camera_rig:
		camera_rig.yaw = heading_yaw
		camera_rig.snap()
