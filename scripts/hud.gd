class_name Hud
extends CanvasLayer
## Hit stats, a knock-down banner, the controls card and a small "sword pad"
## that shows where the fist is inside its reachable box.

const INK := Color(0.96, 0.95, 0.9)
const DIM := Color(0.96, 0.95, 0.9, 0.55)
const HOT := Color(1.0, 0.8, 0.25)
const PANEL := Color(0.07, 0.08, 0.1, 0.62)

const CONTROLS := """WASD  walk        Shift  sprint      Space  jump
Mouse  look        Hold LMB  control the sword
Scroll  reach in / out     Q / E  roll the blade
C  back to guard   F  go limp (hold)   R  respawn
H  hide this       Esc  free the mouse"""

var _hits := 0
var _best := 0
var _total := 0
var _stats: Label
var _last: Label
var _banner: Label
var _controls: PanelContainer
var _click: Label
var _pad: SwordPad


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var stats_box := _panel(root)
	stats_box.position = Vector2(20, 20)
	var col := VBoxContainer.new()
	stats_box.add_child(col)
	_stats = _label(col, 18, INK)
	_last = _label(col, 30, HOT)
	_refresh_stats(0, 0.0)

	_banner = _label(root, 42, HOT)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_top = 90
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_click = _label(root, 26, INK)
	_click.text = "Click to play"
	_click.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_click.offset_top = 160
	_click.grow_horizontal = Control.GROW_DIRECTION_BOTH

	_controls = _panel(root)
	_controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_controls.offset_left = 20
	_controls.offset_bottom = -20
	_controls.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var controls_label := _label(_controls, 15, INK)
	controls_label.text = CONTROLS

	_pad = SwordPad.new()
	_pad.custom_minimum_size = Vector2(170, 190)
	var pad_panel := _panel(root)
	pad_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	pad_panel.offset_right = -20
	pad_panel.offset_bottom = -20
	pad_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pad_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pad_panel.add_child(_pad)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_help"):
		_controls.visible = not _controls.visible


func _process(_delta: float) -> void:
	_click.visible = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED


func add_hit(damage: int, speed: float) -> void:
	_hits += 1
	_total += damage
	_best = maxi(_best, damage)
	_refresh_stats(damage, speed)


func set_status(player_down: bool, dummy_down: bool) -> void:
	if player_down:
		_banner.text = "You fell over"
	elif dummy_down:
		_banner.text = "Dummy down!"
	else:
		_banner.text = ""


func set_sword_state(hand: Vector3, active: bool, roll: float) -> void:
	_pad.hand = hand
	_pad.active = active
	_pad.roll = roll
	_pad.queue_redraw()


func _refresh_stats(last: int, speed: float) -> void:
	_stats.text = "HITS %d    BEST %d    TOTAL %d" % [_hits, _best, _total]
	_last.text = "%d dmg  ·  %.1f m/s" % [last, speed] if _hits > 0 else "Hit the dummy"


func _panel(parent: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	return panel


func _label(parent: Control, size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


## Front view of the fist's reachable box (x/y) with a reach bar (z).
class SwordPad extends Control:
	var hand := Vector3.ZERO
	var active := false
	var roll := 0.0

	func _draw() -> void:
		var box := Rect2(Vector2(0, 22), Vector2(140, 160))
		var accent := HOT if active else DIM
		draw_string(get_theme_default_font(), Vector2(0, 14), "SWORD" + (" — ACTIVE" if active else " — hold LMB"),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, accent)
		draw_rect(box, Color(1, 1, 1, 0.06))
		draw_rect(box, accent, false, 1.5)
		var t := Vector2(inverse_lerp(Player.HAND_MIN.x, Player.HAND_MAX.x, hand.x),
				1.0 - inverse_lerp(Player.HAND_MIN.y, Player.HAND_MAX.y, hand.y))
		var p := box.position + t * box.size
		var dir := Vector2(sin(roll), -cos(roll)) * 14.0
		draw_line(p - dir, p + dir, accent, 2.0)
		draw_circle(p, 6.0, accent)
		# Reach: top of the bar is full extension.
		var bar := Rect2(Vector2(152, 22), Vector2(12, 160))
		draw_rect(bar, Color(1, 1, 1, 0.06))
		var r := inverse_lerp(Player.HAND_MAX.z, Player.HAND_MIN.z, hand.z)
		draw_rect(Rect2(bar.position + Vector2(0, bar.size.y * (1.0 - r)), Vector2(12, bar.size.y * r)), accent)
