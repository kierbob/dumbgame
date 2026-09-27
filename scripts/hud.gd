class_name Hud
extends CanvasLayer
## Minimal readouts in the spirit of Half Sword: a wound chart for your
## sparring partner, your own blood, a tiny crosshair and a controls card.

const INK := Color(0.92, 0.89, 0.82)
const DIM := Color(0.92, 0.89, 0.82, 0.55)
const BLOOD := Color(0.62, 0.08, 0.06)
const PANEL := Color(0.05, 0.04, 0.03, 0.55)
const PART_NAMES := {
	"head": "head", "chest": "torso", "pelvis": "hips",
	"arm_upper_r": "right arm", "arm_lower_r": "right forearm",
	"arm_upper_l": "left arm", "arm_lower_l": "left forearm",
	"leg_upper_r": "right thigh", "leg_lower_r": "right shin",
	"leg_upper_l": "left thigh", "leg_lower_l": "left shin",
}

const CONTROLS := """Mouse  look / turn        Hold LMB  drag your sword arm
Hold RMB  half-sword grip   Alt / MMB  thrust (push mouse forward)
Scroll  reach   Q / E  roll the blade   C  back to guard
WASD  move   Shift  sprint (tap + direction: dodge)   Ctrl  crouch
Space  kick   Tab  lock on   V  first person
T  new sparring partner   R  respawn   F  go limp   H  hide   Esc  free mouse"""

var _chart: WoundChart
var _status: Label
var _log: Label
var _lines: Array[String] = []
var _self_bar: ProgressBar
var _self_label: Label
var _controls: PanelContainer
var _click: Label


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var panel := _panel(root)
	panel.position = Vector2(18, 18)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	_chart = WoundChart.new()
	_chart.custom_minimum_size = Vector2(92, 170)
	row.add_child(_chart)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	_label(col, 13, DIM).text = "SPARRING PARTNER"
	_status = _label(col, 20, INK)
	_log = _label(col, 14, INK)
	_log.custom_minimum_size = Vector2(230, 0)

	var self_box := VBoxContainer.new()
	self_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	self_box.offset_bottom = -22
	self_box.offset_top = -60
	self_box.offset_left = -110
	self_box.offset_right = 110
	root.add_child(self_box)
	_self_label = _label(self_box, 13, DIM)
	_self_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_self_bar = _bar(self_box)

	var cross := Crosshair.new()
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	root.add_child(cross)

	_click = _label(root, 24, INK)
	_click.text = "Click to fight"
	_click.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_click.offset_top = 150
	_click.grow_horizontal = Control.GROW_DIRECTION_BOTH

	_controls = _panel(root)
	_controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_controls.offset_left = 18
	_controls.offset_bottom = -18
	_controls.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_label(_controls, 13, DIM).text = CONTROLS


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_help"):
		_controls.visible = not _controls.visible


func _process(_delta: float) -> void:
	_click.visible = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED


func show_fighter(fighter: ActiveRagdoll) -> void:
	_chart.fighter = fighter
	_chart.queue_redraw()
	var blood := roundi(fighter.blood / fighter.max_blood * 100.0)
	var state := "Standing"
	if fighter.is_dead():
		state = "Dead"
	elif fighter.is_down():
		state = "Down"
	_status.text = "%s  ·  blood %d%%" % [state, blood]
	_status.add_theme_color_override("font_color", BLOOD.lightened(0.3) if fighter.is_dead() else INK)


func show_player(player: Player) -> void:
	_self_bar.value = player.blood / player.max_blood * 100.0
	var state := "you are dead  ·  R to respawn" if player.is_dead() else ("you are down" if player.is_down() else "")
	if player.half_sword_held:
		state = "half-sword grip"
	elif player.thrusting:
		state = "thrust"
	_self_label.text = state


func log_hit(part_name: String, kind: String, damage: float) -> void:
	var what: String = {"cut": "Cut", "stab": "Stab", "blunt": "Blow", "armor": "Glanced off armour"}.get(kind, kind)
	_lines.push_front("%s · %s · %d" % [what, PART_NAMES.get(part_name, part_name), roundi(damage)])
	if _lines.size() > 5:
		_lines.resize(5)
	_log.text = "\n".join(_lines)


func _panel(parent: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.set_corner_radius_all(3)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	return panel


func _label(parent: Control, size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _bar(parent: Control) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(220, 6)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = BLOOD
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	bar.value = 100.0
	parent.add_child(bar)
	return bar


## Front view of a fighter, each body part shaded by how badly it is hurt.
## Severed parts are crossed out.
class WoundChart extends Control:
	var fighter: ActiveRagdoll
	# Rects in a 92 x 170 box, drawn facing the viewer (their right is our left).
	const LAYOUT := {
		"head": Rect2(36, 2, 20, 22),
		"chest": Rect2(29, 27, 34, 46),
		"pelvis": Rect2(31, 75, 30, 16),
		"arm_upper_r": Rect2(15, 28, 11, 30),
		"arm_lower_r": Rect2(11, 60, 11, 30),
		"arm_upper_l": Rect2(66, 28, 11, 30),
		"arm_lower_l": Rect2(70, 60, 11, 30),
		"leg_upper_r": Rect2(31, 94, 13, 36),
		"leg_lower_r": Rect2(30, 132, 13, 36),
		"leg_upper_l": Rect2(48, 94, 13, 36),
		"leg_lower_l": Rect2(49, 132, 13, 36),
	}

	func _draw() -> void:
		if fighter == null:
			return
		for part_name: String in LAYOUT:
			var rect: Rect2 = LAYOUT[part_name]
			if not fighter.health.has(part_name):
				continue
			if fighter.is_severed(part_name):
				draw_rect(rect, Color(0.1, 0.08, 0.07, 0.8))
				draw_line(rect.position, rect.end, Color(0.7, 0.1, 0.08), 2.0)
				draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), Color(0.7, 0.1, 0.08), 2.0)
				continue
			var h := clampf(fighter.health[part_name] / fighter.max_health[part_name], 0.0, 1.0)
			var color := Color(0.62, 0.08, 0.06).lerp(Color(0.78, 0.74, 0.64), h)
			draw_rect(rect, color)
			if fighter.bleed.get(part_name, 0.0) > 0.15:
				draw_rect(rect, Color(0.85, 0.1, 0.08), false, 2.0)


class Crosshair extends Control:
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 2.0, Color(1, 1, 1, 0.7))
