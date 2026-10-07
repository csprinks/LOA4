class_name CharacterCard
extends Control

## A single hero's HUD card: name, XP / Attribute Points / level, title, portrait,
## the equipped hand slots (primary/secondary weapon) plus two consumable quick
## slots, and the HP/AP bars beneath them. Bound to a
## Character by set_character(); hides itself when passed null. Clicking the
## portrait or the ATR readout opens the hero's character sheet.
##
## Equipped items are mirrored onto the character's save data (equipment dict) so
## they persist across hero switches and save/load.

@onready var _portrait: TextureRect = %Portrait
@onready var _name_label: Label = %NameLabel
@onready var _title_label: Label = %TitleLabel
@onready var _level_label: Label = %LevelLabel
@onready var _xp_label: Label = %XPLabel
@onready var _atr_label: Label = %ATRLabel
@onready var _hp_bar: StatBar = %HPBar
@onready var _hp_label: Label = %HPLabel
@onready var _ap_bar: StatBar = %APBar
@onready var _ap_label: Label = %APLabel
@onready var _armor_panel: Panel = %ArmorPanel

# Equipment slot key -> the unique node name of its InventoryContainer in the
# card scene. Weapons live on the card; the armor slots live in the ArmorPanel.
const EQUIP_SLOT_NAMES := {
	"primary": "PrimarySlot", "secondary": "SecondarySlot",
	"consumable1": "Consumable1Slot", "consumable2": "Consumable2Slot",
	"head": "HeadSlot", "chest": "ChestSlot", "hands": "HandsSlot",
	"feet": "FeetSlot", "neck": "NeckSlot", "ring": "RingSlot",
}

var _character: Character = null
var _slots: Dictionary = {}               # slot key -> InventoryContainer
var _inventory_events: Node = null

# Combat overlays (built lazily on first combat use): a gold turn highlight and a
# RollingNumbers popup for damage/heal on this hero during a fight.
var _combat_highlight: Panel = null
var _combat_roller: RollingNumbers = null
# Hit-flash: a shader that pulses the portrait red when this hero is struck. The
# material is created on the first hit and left on the portrait afterward.
const HIT_FLASH_SHADER := preload("res://Combat/UI/hit_flash.gdshader")
var _flash_mat: ShaderMaterial = null
# True while we push saved equipment into the slots, so the resulting
# slot_changed signals don't immediately write the same data straight back.
var _restoring: bool = false

func _ready() -> void:
	_setup_equipment_slots()
	_atr_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_atr_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_atr_label.gui_input.connect(_on_sheet_click)
	_portrait.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_portrait.tooltip_text = "Character sheet (C)"
	_portrait.gui_input.connect(_on_sheet_click)
	# Reflect whatever was assigned before _ready (or hide if none).
	set_character(_character)

func _setup_equipment_slots() -> void:
	_inventory_events = get_node_or_null("/root/InventoryEvents")

	for key in EQUIP_SLOT_NAMES:
		var slot = get_node_or_null("%" + EQUIP_SLOT_NAMES[key])
		if slot:
			_slots[key] = slot
			slot.slot_changed.connect(_on_slot_changed.bind(key, slot))

	# The armor paperdoll shows/hides in sync with the backpack.
	if _inventory_events and _inventory_events.has_signal("ShowInventory"):
		_inventory_events.ShowInventory.connect(_on_toggle_inventory)

func _on_toggle_inventory() -> void:
	if _armor_panel:
		_armor_panel.visible = not _armor_panel.visible

func set_character(character: Character) -> void:
	_character = character

	if not character:
		visible = false
		return
	visible = true

	# _ready may not have run yet if set before the node is in the tree.
	if not is_node_ready():
		return

	_name_label.text = character.character_name
	_title_label.text = character.title
	_level_label.text = "Lv %d" % character.level_system.current_level
	_xp_label.text = "XP %d" % character.level_system.current_xp
	_refresh_atr()

	if character.portrait != "" and ResourceLoader.exists(character.portrait):
		_portrait.texture = load(character.portrait)

	var hp = character.hit_points
	_hp_bar.set_ratio(float(hp.current) / hp.max_value if hp.max_value > 0 else 0.0)
	_hp_label.text = "%d/%d" % [hp.current, hp.max_value]

	var ap = character.action_points
	_ap_bar.set_ratio(float(ap.current) / ap.max_value if ap.max_value > 0 else 0.0)
	_ap_label.text = "%d/%d" % [ap.current, ap.max_value]

	_restore_equipment()

# Push the character's saved equipment into every equip slot (hands + armor).
func _restore_equipment() -> void:
	if not _character:
		return

	_restoring = true
	for key in _slots:
		_apply_slot(_slots[key], _character.get_equipment_slot(key))
	_restoring = false

func _apply_slot(slot: InventoryContainer, item_dict: Dictionary) -> void:
	if not slot:
		return

	var item: InventoryItem = null
	if item_dict != null and not item_dict.is_empty():
		item = EquipmentSerializer.item_from_dict(item_dict, _inventory_events)

	if item:
		slot.SetData(item)
	else:
		# Empty slot: reset to the blank/placeholder state.
		slot.SetData(slot.ClearData())

# Mirror a slot's current contents onto the character whenever it changes.
func _on_slot_changed(slot_key: String, slot: InventoryContainer) -> void:
	if _restoring or not _character or not slot:
		return
	_character.set_equipment_slot(slot_key, EquipmentSerializer.item_to_dict(slot.GetData()))

#region Character sheet
# The points readout (Skill Points / Attribute Points) lights up gold while this
# hero has skills to pick or points to spend. It and the portrait both open the
# character sheet.
func _refresh_atr() -> void:
	var skill_points: int = _character.available_skill_points
	var attribute_points: int = _character.available_attribute_points
	var spendable := skill_points > 0 or attribute_points > 0 or _character.skills.free_picks_left > 0
	_atr_label.text = "SP %d  ATR %d" % [skill_points, attribute_points] + (" +" if spendable else "")
	_atr_label.add_theme_color_override("font_color", UIStyle.GOLD_BRIGHT if spendable else UIStyle.MUTED)
	_atr_label.tooltip_text = "Spend Skill and Attribute Points" if spendable else "Character sheet (C)"

func _on_sheet_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		open_sheet()

func open_sheet() -> void:
	if _character == null:
		return
	# Stats feed the fight in progress, so no skill spending mid-combat.
	var combat := get_node_or_null("/root/CombatManager")
	if combat and combat.has_method("is_active") and combat.is_active():
		return
	CharacterSheetPanel.open_for(_character, self)
#endregion

#region Potions (drag-and-drop use)
# Colors for the floating number popped over the portrait when a potion lands.
const POTION_HEAL_COLOR := Color(0.4, 1.0, 0.4)
const POTION_AP_COLOR := Color(0.45, 0.8, 1.0)

# A potion was dropped on this hero's portrait (see HeroPortrait). Returns true
# when we commit to consuming it, false to bounce it back to the backpack.
#
# In combat the CombatManager/overlay owns the rules: the potion is the ACTIVE
# hero's action for the turn (2 AP), so we hand off and let it validate turn/AP
# and consume on resolution. Out of combat it applies straight to this hero.
func try_receive_potion(item: InventoryItem, source_container: InventoryContainer) -> bool:
	if _character == null or item == null or source_container == null:
		return false
	if not (item._resourceData is PotionData):
		return false

	var combat := get_node_or_null("/root/CombatManager")
	if combat and combat.has_method("is_active") and combat.is_active():
		if combat.has_method("request_potion_use"):
			return bool(combat.request_potion_use(_character, item, source_container))
		return false

	return _use_potion_out_of_combat(item._resourceData as PotionData, source_container)

# Apply a potion directly to this hero (exploration, no turn/AP economy). Only
# consumes the potion when it actually does something, so a health potion isn't
# wasted on a hero already at full HP.
func _use_potion_out_of_combat(potion: PotionData, source_container: InventoryContainer) -> bool:
	match potion.potionType:
		PotionTypes.HEALTH:
			var hp = _character.hit_points
			if hp.current >= hp.max_value:
				return false   # already full — don't waste the potion
			var before: int = hp.current
			_character.heal(potion.amount)
			pop_number(hp.current - before, POTION_HEAL_COLOR)
		PotionTypes.ACTION_POINTS:
			var ap = _character.action_points
			if ap.current >= ap.max_value:
				return false
			var before: int = ap.current
			_character.restore_action_points(potion.amount)
			pop_number(ap.current - before, POTION_AP_COLOR)
		_:
			# MANA / ENERGY have no matching pool on Character yet — leave the
			# potion in the backpack rather than consuming it for nothing.
			return false

	source_container.ConsumeOne()
	refresh_vitals()
	return true
#endregion

#region Combat hooks
# The Character this card is currently bound to (null if empty/hidden). Lets the
# combat overlay map an ally Combatant back to its HUD card.
func get_bound_character() -> Character:
	return _character

func _ensure_combat_nodes() -> void:
	if _combat_highlight == null:
		_combat_highlight = Panel.new()
		_combat_highlight.name = "CombatHighlight"
		_combat_highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
		_combat_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_combat_highlight.add_theme_stylebox_override("panel", UIStyle.outline(UIStyle.GOLD_BRIGHT, 4, 10))
		_combat_highlight.visible = false
		add_child(_combat_highlight)
	if _combat_roller == null:
		_combat_roller = RollingNumbers.new()
		_combat_roller.set_anchors_preset(Control.PRESET_FULL_RECT)
		_combat_roller.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_combat_roller.font = UIStyle.font()
		_combat_roller.font_size = 40
		_combat_roller.display_time = 0.6
		add_child(_combat_roller)

# Show/hide the gold "it's this hero's turn" border.
func set_combat_active(active: bool) -> void:
	_ensure_combat_nodes()
	_combat_highlight.visible = active

func clear_combat() -> void:
	if _combat_highlight:
		_combat_highlight.visible = false

# Refresh the progression readouts (level / XP / Attribute Points). Rewards land
# at the END of a fight, so combat calls this once on conclude rather than every
# turn. Also safe to call after any out-of-combat XP gain (quests, puzzles).
func refresh_progression() -> void:
	if not _character or not is_node_ready():
		return
	_level_label.text = "Lv %d" % _character.level_system.current_level
	_xp_label.text = "XP %d" % _character.level_system.current_xp
	_refresh_atr()

# Refresh just the HP/AP readouts (combat writes wounds straight through to the
# Character, so this is enough to keep the card live during a fight).
func refresh_vitals() -> void:
	if not _character or not is_node_ready():
		return
	var hp = _character.hit_points
	_hp_bar.set_ratio(float(hp.current) / hp.max_value if hp.max_value > 0 else 0.0)
	_hp_label.text = "%d/%d" % [hp.current, hp.max_value]
	var ap = _character.action_points
	_ap_bar.set_ratio(float(ap.current) / ap.max_value if ap.max_value > 0 else 0.0)
	_ap_label.text = "%d/%d" % [ap.current, ap.max_value]

# Float a damage/heal number over the portrait.
func pop_number(amount: int, color: Color) -> void:
	_ensure_combat_nodes()
	var colors: Array[Color] = [color]   # RollingNumbers.digit_colors is typed
	_combat_roller.digit_colors = colors
	_combat_roller.spawn(amount)

# Impact reaction when this hero takes damage: shake the card and pulse the
# portrait red. Called by the combat overlay when damage lands.
func hit_react() -> void:
	if not is_node_ready():
		return
	_flash_portrait()
	_shake_card()

func _flash_portrait() -> void:
	if _portrait == null:
		return
	if _flash_mat == null:
		_flash_mat = ShaderMaterial.new()
		_flash_mat.shader = HIT_FLASH_SHADER
		_portrait.material = _flash_mat
	_flash_mat.set_shader_parameter("flash_amount", 0.85)
	_portrait.create_tween().tween_method(
		func(v: float): _flash_mat.set_shader_parameter("flash_amount", v),
		0.85, 0.0, 0.22)

# Shake the inner Panel (not the card root, which the HUD's VBoxContainer lays out
# and would snap back). Jitters with decaying intensity, then settles.
func _shake_card() -> void:
	var panel := get_node_or_null("Panel") as Control
	if panel == null:
		return
	var base: Vector2 = panel.position
	var t := panel.create_tween()
	for i in range(6):
		var damp := 1.0 - float(i) / 6.0
		var off := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 8.0 * damp
		t.tween_property(panel, "position", base + off, 0.035)
	t.tween_property(panel, "position", base, 0.035)
#endregion
