class_name SkillNode
extends BaseButton

## One skill on the character sheet: a diamond in its attribute's colour with the
## skill's position numeral (or icon), rank pips and its name beneath. Purely a view --
## CharacterSheet pushes state in through show_state() and listens for pressed /
## activated; the lines between skills belong to the SkillLattice it sits in.
##
## It animates itself: a swell on hover, a slow glow while it can be bought, a
## pop with a burst ring and sparks when a rank lands, a dip when a rank is taken
## back, and a shake when a buy is refused.

signal activated   # double-click: buy / upgrade without going through the detail panel

enum State { LOCKED, AVAILABLE, OWNED }

const NODE_SIZE := Vector2(86, 138)
const RADIUS := 26.0
const CENTER_Y := 34.0
const PIP_Y := 70.0
const NAME_BASELINE := 90.0     # first of up to two lines
const NAME_FONT_SIZE := 13
const NAME_BOTTOM := 108.0      # the lattice's lines leave from here
const ROMAN := ["I", "II", "III", "IV", "V"]

const HOVER_SWELL := 0.12       # extra scale at full hover
const HOVER_SPEED := 12.0
const PULSE_SPEED := 3.2
const POP_SCALE := 0.45         # overshoot when a rank lands
const POP_TIME := 0.45
const BURST_TIME := 0.5
const BURST_REACH := 36.0
const SPARKS := 8
const DENY_TIME := 0.32
const DENY_SHAKE := 6.0
const DENY_COLOR := Color(0.9, 0.2, 0.15)

var definition: SkillDefinition

var _state: State = State.LOCKED
var _rank := 0
var _selected := false
var _pending := false       # rank differs from what is confirmed on the Character
var _advanceable := false   # can be bought / upgraded right now

# Animation state; each is driven by _process or a tween and only read in _draw.
var _hover := 0.0           # 0..1, eased toward hovered/focused
var _clock := 0.0           # runs while _advanceable, for the idle glow
var _pop := 0.0             # added to the diamond's scale
var _burst := 1.0           # 0..1 progress of the ring + sparks (1 = finished)
var _flash := 0.0           # white wash over the diamond, fades to 0
var _deny := 0.0            # 1..0 while a refused buy shakes the node
var _fx: Tween


func _init(skill: SkillDefinition) -> void:
	definition = skill
	custom_minimum_size = NODE_SIZE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = skill.display_name
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


# `animate` plays the transition from the previous state (a rank gained or lost);
# false snaps straight to the new one (another hero was bound, first show).
func show_state(state: State, rank: int, selected: bool, pending: bool,
		advanceable: bool, animate: bool) -> void:
	var gained := rank > _rank
	var lost := rank < _rank
	var newly_owned := gained and _rank == 0

	_state = state
	_rank = rank
	_selected = selected
	_pending = pending
	_advanceable = advanceable

	if animate and gained:
		# A skill reached along a line pops as the line's light arrives.
		_play_gain(SkillLattice.LINK_TIME if newly_owned and definition.position > 1 else 0.0)
	elif animate and lost:
		_play_loss()
	queue_redraw()


# A buy that was refused (not reachable, maxed, or too expensive).
func play_denied() -> void:
	_restart_fx()
	_deny = 1.0
	_fx.tween_method(_set_deny, 1.0, 0.0, DENY_TIME)


func _play_gain(delay: float) -> void:
	_restart_fx()
	z_index = 1   # the burst spills over the neighbouring skills
	_fx.set_parallel(true)
	_fx.tween_method(_set_pop, POP_SCALE, 0.0, POP_TIME).set_delay(delay) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_fx.tween_method(_set_flash, 1.0, 0.0, POP_TIME * 0.8).set_delay(delay)
	_fx.tween_method(_set_burst, 0.0, 1.0, BURST_TIME).set_delay(delay) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_fx.chain().tween_callback(func(): z_index = 0)


func _play_loss() -> void:
	_restart_fx()
	_fx.tween_method(_set_pop, -0.22, 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _restart_fx() -> void:
	if _fx:
		_fx.kill()
	_pop = 0.0
	_burst = 1.0
	_flash = 0.0
	_deny = 0.0
	z_index = 0
	_fx = create_tween()


func _set_pop(v: float) -> void:
	_pop = v
	queue_redraw()

func _set_burst(v: float) -> void:
	_burst = v
	queue_redraw()

func _set_flash(v: float) -> void:
	_flash = v
	queue_redraw()

func _set_deny(v: float) -> void:
	_deny = v
	queue_redraw()


func _process(delta: float) -> void:
	var target := 1.0 if (is_hovered() or has_focus()) and not disabled else 0.0
	if not is_equal_approx(_hover, target):
		_hover = move_toward(_hover, target, delta * HOVER_SPEED)
		queue_redraw()
	if _advanceable:
		_clock += delta
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.double_click \
			and event.button_index == MOUSE_BUTTON_LEFT:
		activated.emit()


func _draw() -> void:
	var color := SkillTree.color_of(definition.attribute)
	var center := Vector2(size.x * 0.5, CENTER_Y)
	var owned := _state == State.OWNED

	# Opaque fills: the lattice's lines run underneath, centre to centre.
	var fill := Color(0.05, 0.035, 0.025)
	var border := UIStyle.GOLD_DIM
	var text_color := UIStyle.MUTED
	match _state:
		State.OWNED:
			fill = color.darkened(0.35)
			border = color.lightened(0.35)
			text_color = UIStyle.GOLD_BRIGHT
		State.AVAILABLE:
			fill = color.darkened(0.8)
			border = UIStyle.GOLD
			text_color = UIStyle.CREAM
	fill = fill.lightened(0.12 * _hover).lerp(Color.WHITE, _flash * 0.75).lerp(DENY_COLOR, _deny * 0.6)
	border = border.lerp(DENY_COLOR, _deny)

	# Everything below is drawn around the diamond's centre, so one transform
	# carries the swell, the pop and the refusal shake.
	var shake := sin(_deny * TAU * 3.0) * DENY_SHAKE * _deny
	var swell := 1.0 + HOVER_SWELL * _hover + _pop
	draw_set_transform(center + Vector2(shake, 0), 0.0, Vector2(swell, swell))

	if _advanceable:
		var pulse := 0.5 + 0.5 * sin(_clock * PULSE_SPEED)
		var glow := (color.lightened(0.4) if owned else UIStyle.GOLD_BRIGHT)
		glow.a = 0.15 + 0.4 * pulse
		draw_polyline(_diamond(RADIUS + 3.0 + 2.0 * pulse, true), glow, 2.0 + 1.5 * pulse, true)

	draw_colored_polygon(_diamond(RADIUS), fill)
	draw_polyline(_diamond(RADIUS, true), border, 2.5, true)
	if _selected or has_focus():
		draw_polyline(_diamond(RADIUS + 5.0, true), UIStyle.GOLD_BRIGHT, 2.0, true)

	if definition.icon:
		var icon_size := Vector2(30, 30)
		draw_texture_rect(definition.icon, Rect2(-icon_size * 0.5, icon_size), false,
			Color.WHITE if owned else Color(1, 1, 1, 0.45))
	else:
		var font_size := 20
		draw_string(UIStyle.font(), Vector2(-size.x * 0.5, font_size * 0.36),
			ROMAN[definition.position - 1], HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, text_color)

	if _burst < 1.0:
		_draw_burst(color.lightened(0.5))

	# Rank pips: filled per rank owned, bright while the rank is still unconfirmed.
	# They sit under the diamond and don't swell with it; the newest one pops.
	draw_set_transform(Vector2(shake, 0))
	for i in SkillTree.MAX_RANK:
		var pip := Vector2(center.x + (i - (SkillTree.MAX_RANK - 1) * 0.5) * 13.0, PIP_Y)
		if i < _rank:
			var newest := i == _rank - 1
			draw_circle(pip, 4.0 * (1.0 + (_pop * 2.0 if newest else 0.0)),
				(UIStyle.GOLD_BRIGHT if _pending else color.lightened(0.35)).lerp(Color.WHITE, _flash if newest else 0.0))
		else:
			draw_arc(pip, 3.5, 0.0, TAU, 16, UIStyle.GOLD_DIM, 1.4, true)
	draw_set_transform(Vector2.ZERO)

	var name_color := UIStyle.MUTED
	if _selected:
		name_color = UIStyle.GOLD_BRIGHT
	elif owned:
		name_color = UIStyle.CREAM
	draw_multiline_string(UIStyle.font(), Vector2(4, NAME_BASELINE), definition.display_name,
		HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, NAME_FONT_SIZE, 2, name_color)


# The ring and sparks thrown off when a rank lands. Drawn in the diamond's space.
func _draw_burst(color: Color) -> void:
	var fade := 1.0 - _burst
	color.a = fade
	draw_polyline(_diamond(RADIUS + BURST_REACH * _burst, true), color, 1.0 + 4.0 * fade, true)
	for i in SPARKS:
		var dir := Vector2.from_angle(TAU * (i + 0.5) / SPARKS)
		draw_circle(dir * (RADIUS * 0.8 + BURST_REACH * 1.5 * _burst), 4.0 * fade, color)


# A diamond around the origin (the caller's transform puts it on the node's centre).
func _diamond(radius: float, closed: bool = false) -> PackedVector2Array:
	var points := PackedVector2Array([
		Vector2(0, -radius), Vector2(radius, 0), Vector2(0, radius), Vector2(-radius, 0),
	])
	if closed:
		points.append(points[0])
	return points
