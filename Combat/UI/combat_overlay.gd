class_name CombatOverlay
extends CanvasLayer

## In-world battle UI, laid over the running level (the CombatManager spawns it and
## locks the player). Renders what the combat logic core (Combat/) resolves:
##   - a Turn Order strip along the top,
##   - the enemy monsters in depth-staggered rows (front row = meleeable, drawn IN
##     FRONT and highlighted; back rows recede behind),
##   - a combat log on the LEFT ("what is happening"),
##   - an action menu (Attack / Flee / End Turn) for the active hero.
## The PARTY is the persistent hero HUD (UI_Main character cards): the active hero's
## card gets a gold border, wounds refresh live, and damage numbers pop over it —
## so there is no separate party strip.
##
## It drives CombatController turn-by-turn with build_initiative / begin_turn /
## apply_action so an ally's turn can pause for the player's click. Placeholder art.

# --- Palette / layout tunables ----------------------------------------------
const CARD_COLOR := Color(0.06, 0.06, 0.07, 0.92)
const CARD_BORDER := Color(0.45, 0.45, 0.48)
const FRONT_BORDER := Color(1, 1, 1)                 # front (meleeable) row
const TARGET_BORDER := Color(0.36, 0.92, 0.45)       # selectable target
const DEAD_MODULATE := Color(0.35, 0.25, 0.25, 0.55)
const GOLD := Color(0.9059, 0.6980, 0.2588)
const ALLY_CHIP := Color(0.20, 0.30, 0.45)
const ENEMY_CHIP := Color(0.42, 0.20, 0.20)
const HP_COLOR := Color(0.90, 0.42, 0.40)
const DAMAGE_COLOR := Color(1, 0.75, 0.2)
const HEAL_COLOR := Color(0.4, 1.0, 0.4)

const ENEMY_AREA := Rect2(380, 150, 1080, 540)       # x, y, w, h — clears the right HUD cards
const ROW_SCALE := 0.82                              # each row back shrinks by this
const CARD_W := 190.0
const CARD_H := 262.0

signal battle_finished(status: int)
signal _player_decided(decision: Dictionary)

# --- Combat model ------------------------------------------------------------
var encounter: Encounter
var controller: CombatController
var ai_strategy: AIStrategy
var round_number := 0

# --- View bookkeeping --------------------------------------------------------
var _enemy_views := {}      # Combatant -> { card, name_label, hp_label, button, roll }
var _ally_cards := {}       # Combatant -> CharacterCard (from the live HUD)
var _chip_views := {}       # Combatant -> Panel
var _font: FontFile

var _active_ally: Combatant = null
var _targeting := false

# Enemy formation: the frontmost (meleeable) row value and how many monsters it
# holds. As front-row monsters die, back-row monsters are promoted forward to keep
# the front filled up to this capacity.
var _front_row := 0
var _front_capacity := 1

# --- Node refs (built in code) ----------------------------------------------
var _root: Control
var _turn_order_box: HBoxContainer
var _enemy_area: Control
var _action_bar: HBoxContainer
var _target_bar: HBoxContainer
var _log_label: RichTextLabel
var _banner: Panel
var _banner_label: Label
var _continue_button: Button


# Entry point: CombatManager hands over the built encounter/controller and the
# player (whose HUD cards we drive as the party display).
func begin(enc: Encounter, ctrl: CombatController, player: Node) -> void:
	layer = 40   # above the HUD (UI_Main) so action buttons sit on top
	encounter = enc
	controller = ctrl
	ai_strategy = ctrl.ai_strategy
	_font = load("res://Fonts/VeniceClassic.ttf")

	_build_static_ui()
	_find_ally_cards(player)
	_build_enemy_cards()
	_refresh_party()
	_run_battle()


#region Party (via the live HUD cards)
func _find_ally_cards(player: Node) -> void:
	_ally_cards.clear()
	if player == null:
		return
	var cards_box := player.get_node_or_null("UI_Main/UI_Main_Control/Cards")
	if cards_box == null:
		return

	var cards: Array = []
	for child in cards_box.get_children():
		if child is CharacterCard:
			cards.append(child)

	for ally in encounter.allies:
		for card in cards:
			if card.get_bound_character() == ally.character:
				_ally_cards[ally] = card
				break


func _refresh_party() -> void:
	for ally in _ally_cards.keys():
		var card: CharacterCard = _ally_cards[ally]
		card.refresh_vitals()
		card.set_combat_active(ally == _active_ally and not ally.is_downed)


func _clear_party_combat() -> void:
	for card in _ally_cards.values():
		card.clear_combat()
#endregion


#region Static UI construction
func _build_static_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE   # gaps pass through to the HUD
	_root.theme = load("res://UI/game_theme.tres")
	add_child(_root)

	# --- Turn Order strip (top) ---
	var top_label := _make_label("Turn Order", 26, GOLD)
	top_label.position = Vector2(40, 24)
	top_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(top_label)

	_turn_order_box = HBoxContainer.new()
	_turn_order_box.add_theme_constant_override("separation", 8)
	_turn_order_box.position = Vector2(240, 20)
	_turn_order_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_turn_order_box)

	# --- Combat log (LEFT — "what is happening") ---
	var log_panel := Panel.new()
	log_panel.position = Vector2(24, 470)
	log_panel.size = Vector2(340, 470)
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(log_panel)

	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.scroll_following = true
	_log_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_label.add_theme_constant_override("margin_left", 12)
	_log_label.add_theme_constant_override("margin_top", 12)
	_log_label.add_theme_constant_override("margin_right", 12)
	_log_label.add_theme_constant_override("margin_bottom", 12)
	_log_label.add_theme_font_size_override("normal_font_size", 18)
	log_panel.add_child(_log_label)

	# --- Enemy area ---
	_enemy_area = Control.new()
	_enemy_area.position = ENEMY_AREA.position
	_enemy_area.size = ENEMY_AREA.size
	_enemy_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_enemy_area)

	# --- Action bar + targeting bar (bottom-left, clear of the HUD cards) ---
	_action_bar = HBoxContainer.new()
	_action_bar.add_theme_constant_override("separation", 12)
	_action_bar.position = Vector2(400, 950)
	_action_bar.visible = false
	_root.add_child(_action_bar)
	_build_action_buttons()

	_target_bar = HBoxContainer.new()
	_target_bar.add_theme_constant_override("separation", 12)
	_target_bar.position = Vector2(400, 950)
	_target_bar.visible = false
	_root.add_child(_target_bar)
	var target_hint := _make_label("Choose a target", 24, Color.WHITE)
	target_hint.custom_minimum_size = Vector2(0, 56)
	_target_bar.add_child(target_hint)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.add_theme_font_size_override("font_size", 22)
	cancel.pressed.connect(_cancel_targeting)
	_target_bar.add_child(cancel)

	# --- End banner (hidden until the fight ends) ---
	_banner = Panel.new()
	_banner.position = Vector2(560, 400)
	_banner.size = Vector2(600, 240)
	_banner.visible = false
	_root.add_child(_banner)
	var banner_vbox := VBoxContainer.new()
	banner_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	banner_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	banner_vbox.add_theme_constant_override("separation", 24)
	_banner.add_child(banner_vbox)
	_banner_label = _make_label("", 48, GOLD)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_vbox.add_child(_banner_label)
	_continue_button = Button.new()
	_continue_button.text = "Continue"
	_continue_button.add_theme_font_size_override("font_size", 28)
	_continue_button.pressed.connect(_on_continue_pressed)
	var continue_wrap := CenterContainer.new()
	continue_wrap.add_child(_continue_button)
	banner_vbox.add_child(continue_wrap)


func _build_action_buttons() -> void:
	_add_action_button("Attack", _on_attack_pressed)
	_add_action_button("Flee", _on_flee_pressed)
	_add_action_button("End Turn", _on_end_turn_pressed)


func _add_action_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.name = text.replace(" ", "")
	b.custom_minimum_size = Vector2(120, 56)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(handler)
	_action_bar.add_child(b)
	return b
#endregion


#region Enemy cards
func _build_enemy_cards() -> void:
	for child in _enemy_area.get_children():
		child.queue_free()
	_enemy_views.clear()

	# The frontmost row is the smallest row value present; its monster count is the
	# capacity we keep the front filled to as monsters die.
	var min_row := 1 << 30
	for cb in encounter.enemies:
		min_row = mini(min_row, cb.row)
	_front_row = min_row if encounter.enemies.size() > 0 else 0
	_front_capacity = 0
	for cb in encounter.enemies:
		if cb.row == _front_row:
			_front_capacity += 1
		_make_enemy_card(cb)

	_layout_enemies(false)
	_refresh_enemies()


# Each enemy is a HOLDER Control (positioned/sized by _layout_enemies, tweened when
# the formation changes) wrapping a CARD Panel (which idle-bobs on its own y). The
# split lets layout and the bob animate independently without fighting.
func _make_enemy_card(cb: Combatant) -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = Vector2(CARD_W, CARD_H)
	_enemy_area.add_child(holder)

	var card := Panel.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE   # the button below captures clicks
	card.size = holder.size
	card.add_theme_stylebox_override("panel", _card_style(CARD_BORDER))
	holder.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 6)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	var name_label := _make_label(cb.display_name, 22, Color.WHITE)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)

	var hp_label := _make_label("", 18, HP_COLOR)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hp_label)

	# Transparent full-card button captures target clicks (enabled only while
	# targeting, so the board isn't clickable mid-resolution).
	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.focus_mode = Control.FOCUS_NONE
	btn.modulate = Color(1, 1, 1, 0)
	btn.disabled = true
	btn.pressed.connect(_on_enemy_clicked.bind(cb))
	card.add_child(btn)

	var roll := _make_roller()
	card.add_child(roll)

	_enemy_views[cb] = {
		"holder": holder, "card": card, "name_label": name_label,
		"hp_label": hp_label, "button": btn, "roll": roll, "dead": false,
		"bob": _start_bob(card),
	}


# A gentle, endless up/down bob so idle monsters feel alive. Random amplitude and
# period per card so they drift out of sync.
func _start_bob(card: Panel) -> Tween:
	var amp := randf_range(4.0, 9.0)
	var dur := randf_range(1.1, 1.9)
	card.position.y = randf_range(-amp, amp)
	var t := card.create_tween().set_loops()
	t.tween_property(card, "position:y", amp, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(card, "position:y", -amp, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return t


# Position every LIVING enemy by its current row (front row lowest/largest/on top;
# back rows recede up and shrink). animate=true tweens holders to their new spots,
# so a promoted monster visibly steps forward.
func _layout_enemies(animate: bool) -> void:
	var rows := {}
	for cb in encounter.enemies:
		if cb.is_downed or cb.current_hp <= 0:
			continue
		if not rows.has(cb.row):
			rows[cb.row] = []
		rows[cb.row].append(cb)

	var row_keys := rows.keys()
	row_keys.sort()   # frontmost living row first

	for idx in range(row_keys.size()):
		var row: Array = rows[row_keys[idx]]
		var scale := pow(ROW_SCALE, idx)
		var card_w := CARD_W * scale
		var card_h := CARD_H * scale
		var gap := 28.0 * scale
		var total_w := row.size() * card_w + (row.size() - 1) * gap
		var start_x := ENEMY_AREA.size.x * 0.5 - total_w * 0.5
		var row_y := ENEMY_AREA.size.y - card_h - idx * (card_h * 0.55)
		for j in range(row.size()):
			var cb: Combatant = row[j]
			var view: Dictionary = _enemy_views[cb]
			var holder: Control = view["holder"]
			var card: Panel = view["card"]
			var target_pos := Vector2(start_x + j * (card_w + gap), row_y)
			var target_size := Vector2(card_w, card_h)
			holder.z_index = -idx * 10   # front row draws on top
			if animate:
				var t := holder.create_tween().set_parallel(true)
				t.tween_property(holder, "position", target_pos, 0.35) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				t.tween_property(holder, "size", target_size, 0.35)
				t.tween_property(card, "size", target_size, 0.35)
			else:
				holder.position = target_pos
				holder.size = target_size
				card.size = target_size


# Pull back-row monsters forward to keep the front row filled to capacity. Returns
# true if any monster changed row.
func _promote_forward() -> bool:
	var changed := false
	while true:
		var living := encounter.living_enemies()
		var front_count := living.filter(func(e): return e.row == _front_row).size()
		if front_count >= _front_capacity:
			break
		var back: Array = living.filter(func(e): return e.row > _front_row)
		if back.is_empty():
			break
		back.sort_custom(func(a, b): return a.row < b.row)
		back[0].row = _front_row
		changed = true
	return changed


# After an action: fade any newly-dead monsters, promote back-row monsters forward,
# and re-lay-out (tweened) so the formation slides into its new shape.
func _update_board_after_action() -> void:
	var changed := false
	for cb in _enemy_views.keys():
		var view: Dictionary = _enemy_views[cb]
		var dead: bool = cb.is_downed or cb.current_hp <= 0
		if dead and not view["dead"]:
			view["dead"] = true
			_fade_out_card(view)
			changed = true
	if _promote_forward():
		changed = true
	if changed:
		_layout_enemies(true)
	_refresh_enemies()


func _fade_out_card(view: Dictionary) -> void:
	view["button"].disabled = true
	if view["bob"] and view["bob"].is_valid():
		view["bob"].kill()
	var holder: Control = view["holder"]
	var t := holder.create_tween()
	t.tween_property(holder, "modulate:a", 0.0, 0.4)
	t.tween_callback(func(): holder.visible = false)


func _refresh_enemies() -> void:
	var front_row := encounter.front_enemy_row()
	for cb in _enemy_views.keys():
		var view: Dictionary = _enemy_views[cb]
		if view["dead"]:
			continue
		view["hp_label"].text = "HP %d/%d" % [max(0, cb.current_hp), cb.max_hp]
		var border := FRONT_BORDER if cb.row == front_row else CARD_BORDER
		if _targeting and _active_ally and _is_reachable(cb):
			border = TARGET_BORDER
		view["card"].add_theme_stylebox_override("panel", _card_style(border))


func _is_reachable(cb: Combatant) -> bool:
	return encounter.reachable_enemies(_active_ally).has(cb)
#endregion


#region Turn order strip
func _build_turn_order(order: Array) -> void:
	for child in _turn_order_box.get_children():
		child.queue_free()
	_chip_views.clear()

	for cb in order:
		var chip := Panel.new()
		chip.custom_minimum_size = Vector2(104, 104)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var base := ALLY_CHIP if cb.is_ally else ENEMY_CHIP
		chip.add_theme_stylebox_override("panel", _chip_style(base, CARD_BORDER))

		var label := _make_label(cb.display_name, 16, Color.WHITE)
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(label)

		_turn_order_box.add_child(chip)
		_chip_views[cb] = chip


func _highlight_turn_order(actor: Combatant) -> void:
	for cb in _chip_views.keys():
		var chip: Panel = _chip_views[cb]
		var base := ALLY_CHIP if cb.is_ally else ENEMY_CHIP
		if cb == actor:
			chip.add_theme_stylebox_override("panel", _chip_style(base, GOLD, 4))
			chip.modulate = Color.WHITE
		else:
			chip.add_theme_stylebox_override("panel", _chip_style(base, CARD_BORDER))
			chip.modulate = Color(1, 1, 1, 0.6) if cb.is_downed else Color.WHITE
#endregion


#region Battle driver (turn-by-turn)
func _run_battle() -> void:
	encounter.refresh_status()
	while encounter.status == Encounter.Status.ONGOING:
		round_number += 1
		_log("[color=gold]— Round %d —[/color]" % round_number)
		var order: Array = controller.build_initiative()
		_build_turn_order(order)

		for actor in order:
			if actor.is_downed:
				continue
			if encounter.status != Encounter.Status.ONGOING:
				break
			_active_ally = actor if actor.is_ally else null
			controller.begin_turn(actor)
			_highlight_turn_order(actor)
			_refresh_party()

			if actor.is_ally:
				await _take_player_turn(actor)
			else:
				await _take_enemy_turn(actor)

			_update_board_after_action()   # fade deaths + promote back rows forward
			_refresh_party()
			if encounter.status != Encounter.Status.ONGOING:
				break
			await _sleep(0.2)

	_conclude()


func _take_enemy_turn(actor: Combatant) -> void:
	await _sleep(0.5)
	var decision: Dictionary = ai_strategy.choose_action(actor, encounter, controller)
	if decision.is_empty() or decision.get("action") == null:
		return
	var result := controller.apply_action(actor, decision["action"], decision.get("target"))
	_narrate(result, actor)
	await _sleep(0.5)


func _take_player_turn(actor: Combatant) -> void:
	_active_ally = actor
	_refresh_party()
	_show_action_bar(actor)
	_log("[color=silver]%s's turn.[/color]" % actor.display_name)

	var decision: Dictionary = await _player_decided
	_hide_action_bar()
	_targeting = false
	_refresh_enemies()

	if decision.is_empty() or decision.get("action") == null:
		return
	var result := controller.apply_action(actor, decision["action"], decision.get("target"))
	_narrate(result, actor)
	await _sleep(0.4)


func _conclude() -> void:
	_active_ally = null
	_hide_action_bar()
	_clear_party_combat()
	controller.conclude()   # awards XP / crowns / loot on WIN and emits its signal
	_refresh_party()
	_refresh_enemies()

	var text := ""
	match encounter.status:
		Encounter.Status.WIN: text = "Victory!"
		Encounter.Status.LOSE: text = "Defeated..."
		Encounter.Status.FLED: text = "Fled the battle"
		_: text = "Battle over"
	_log("[color=gold]%s[/color]" % text)
	_banner_label.text = text
	_banner.visible = true
	_continue_button.grab_focus()
#endregion


#region Action handlers
func _show_action_bar(actor: Combatant) -> void:
	_action_bar.visible = true
	_target_bar.visible = false
	var attack := AttackAction.new()
	var flee := FleeAction.new()
	_button("Attack").disabled = actor.action_points < attack.ap_cost_for(actor) \
		or encounter.reachable_enemies(actor).is_empty()
	_button("Flee").disabled = actor.action_points < flee.ap_cost_for(actor)


func _hide_action_bar() -> void:
	_action_bar.visible = false
	_target_bar.visible = false


func _button(text: String) -> Button:
	return _action_bar.get_node(text.replace(" ", "")) as Button


func _on_attack_pressed() -> void:
	# Enter targeting mode: light up reachable enemies and wait for a card click.
	_targeting = true
	_action_bar.visible = false
	_target_bar.visible = true
	_refresh_enemies()
	for cb in _enemy_views.keys():
		var btn: Button = _enemy_views[cb]["button"]
		btn.disabled = not _is_reachable(cb)


func _cancel_targeting() -> void:
	_targeting = false
	_target_bar.visible = false
	_action_bar.visible = true
	for cb in _enemy_views.keys():
		_enemy_views[cb]["button"].disabled = true
	_refresh_enemies()


func _on_enemy_clicked(cb: Combatant) -> void:
	if not _targeting:
		return
	for other in _enemy_views.keys():
		_enemy_views[other]["button"].disabled = true
	_player_decided.emit({"action": AttackAction.new(), "target": cb})


func _on_flee_pressed() -> void:
	_player_decided.emit({"action": FleeAction.new(), "target": null})


func _on_end_turn_pressed() -> void:
	_player_decided.emit({})


func _unhandled_input(event: InputEvent) -> void:
	if _targeting and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_targeting()
		get_viewport().set_input_as_handled()
#endregion


#region Narration / effects
func _narrate(result: Dictionary, actor: Combatant) -> void:
	if result.is_empty():
		return
	match result.get("action"):
		"attack":
			var defender: Combatant = result["defender"]
			if result.get("hit"):
				var dmg: int = result.get("damage", 0)
				var crit: bool = result.get("crit", false)
				_spawn_damage(defender, dmg)
				var reroll := " (Fortune!)" if result.get("fortune_rerolled") else ""
				_log("%s hits %s for [color=#ff6666]%d[/color]%s%s." % [
					actor.display_name, defender.display_name, dmg,
					" CRIT!" if crit else "", reroll])
				if result.get("defender_downed"):
					_log("[color=silver]%s is downed![/color]" % defender.display_name)
			else:
				_log("%s misses %s." % [actor.display_name, result["defender"].display_name])
		"flee":
			if result.get("success"):
				_log("[color=gold]%s flees the battle![/color]" % actor.display_name)
			else:
				_log("%s tries to flee, but fails." % actor.display_name)
		"item":
			if result.has("healed"):
				var target: Combatant = result.get("target")
				if target:
					_spawn_heal(target, result["healed"])
				_log("%s uses an item (+%d HP)." % [actor.display_name, result["healed"]])
			else:
				_log("%s uses an item." % actor.display_name)


func _spawn_damage(cb: Combatant, amount: int) -> void:
	_pop_over(cb, amount, DAMAGE_COLOR)


func _spawn_heal(cb: Combatant, amount: int) -> void:
	_pop_over(cb, amount, HEAL_COLOR)


func _pop_over(cb: Combatant, amount: int, color: Color) -> void:
	if _enemy_views.has(cb):
		var roll: RollingNumbers = _enemy_views[cb]["roll"]
		var colors: Array[Color] = [color]   # RollingNumbers.digit_colors is typed
		roll.digit_colors = colors
		roll.spawn(amount)
	elif _ally_cards.has(cb):
		_ally_cards[cb].pop_number(amount, color)


func _log(bbcode: String) -> void:
	_log_label.append_text(bbcode + "\n")
#endregion


#region Exit
func _on_continue_pressed() -> void:
	battle_finished.emit(encounter.status)
#endregion


#region Small builders
func _sleep(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _make_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 3)
	return l


func _make_roller() -> RollingNumbers:
	var roll := RollingNumbers.new()
	roll.set_anchors_preset(Control.PRESET_FULL_RECT)
	roll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	roll.font = _font
	roll.font_size = 40
	roll.display_time = 0.6
	return roll


func _card_style(border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_COLOR
	sb.set_border_width_all(3)
	sb.border_color = border
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _chip_style(bg: Color, border: Color, width: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(width)
	sb.border_color = border
	sb.set_corner_radius_all(6)
	return sb
#endregion
