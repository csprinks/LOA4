class_name CharacterCard
extends Control

## A single hero's HUD card: portrait, name, classes, level, HP/AP bars, the six
## stats, and the two equipped hand slots (primary/secondary weapon). Bound to a
## Character by set_character(); hides itself when passed null.
##
## Equipped items are mirrored onto the character's save data (equipment dict) so
## they persist across hero switches and save/load.

@onready var _portrait: TextureRect = %Portrait
@onready var _name_label: Label = %NameLabel
@onready var _class_label: Label = %ClassLabel
@onready var _level_label: Label = %LevelLabel
@onready var _xp_label: Label = %XPLabel
@onready var _dp_label: Label = %DPLabel
@onready var _hp_bar: StatBar = %HPBar
@onready var _hp_label: Label = %HPLabel
@onready var _ap_bar: StatBar = %APBar
@onready var _ap_label: Label = %APLabel
@onready var _stats_grid: GridContainer = %StatsGrid
@onready var _armor_panel: Panel = %ArmorPanel

const STAT_ABBREV := {
	"Might": "MIG", "Awareness": "AWR", "Finesse": "FIN",
	"Intellect": "INT", "Charm": "CHM", "Fate": "FAT",
}

# Equipment slot key -> the unique node name of its InventoryContainer in the
# card scene. Weapons live on the card; the armor slots live in the ArmorPanel.
const EQUIP_SLOT_NAMES := {
	"primary": "PrimarySlot", "secondary": "SecondarySlot",
	"head": "HeadSlot", "chest": "ChestSlot", "hands": "HandsSlot",
	"feet": "FeetSlot", "neck": "NeckSlot", "ring": "RingSlot",
}

var _character: Character = null
var _stat_value_labels: Dictionary = {}   # stat name -> Label
var _slots: Dictionary = {}               # slot key -> InventoryContainer
var _inventory_events: Node = null

# Combat overlays (built lazily on first combat use): a gold turn highlight and a
# RollingNumbers popup for damage/heal on this hero during a fight.
var _combat_highlight: Panel = null
var _combat_roller: RollingNumbers = null
# True while we push saved equipment into the slots, so the resulting
# slot_changed signals don't immediately write the same data straight back.
var _restoring: bool = false

func _ready() -> void:
	_build_stat_labels()
	_setup_equipment_slots()
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

# Build one "ABBR value" label per stat once, so set_character only updates text.
func _build_stat_labels() -> void:
	if not _stats_grid or not _stat_value_labels.is_empty():
		return
	for stat_name in Character.STAT_NAMES:
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 14)
		label.text = "%s --" % STAT_ABBREV.get(stat_name, stat_name)
		_stats_grid.add_child(label)
		_stat_value_labels[stat_name] = label

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
	_class_label.text = _class_text(character)
	_level_label.text = "Lv %d" % character.level_system.current_level
	_xp_label.text = "XP %d" % character.level_system.current_xp
	_dp_label.text = "DP %d" % character.available_deed_points

	if character.portrait != "" and ResourceLoader.exists(character.portrait):
		_portrait.texture = load(character.portrait)

	var hp = character.hit_points
	_hp_bar.set_ratio(float(hp.current) / hp.max_value if hp.max_value > 0 else 0.0)
	_hp_label.text = "%d/%d" % [hp.current, hp.max_value]

	var ap = character.action_points
	_ap_bar.set_ratio(float(ap.current) / ap.max_value if ap.max_value > 0 else 0.0)
	_ap_label.text = "%d/%d" % [ap.current, ap.max_value]

	for stat_name in Character.STAT_NAMES:
		var stat = character.get_stat(stat_name)
		if _stat_value_labels.has(stat_name) and stat:
			_stat_value_labels[stat_name].text = "%s %d" % [STAT_ABBREV.get(stat_name, stat_name), stat.total]

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
		var sb := StyleBoxFlat.new()
		sb.draw_center = false
		sb.set_border_width_all(4)
		sb.border_color = Color(0.9059, 0.6980, 0.2588)
		sb.set_corner_radius_all(8)
		_combat_highlight.add_theme_stylebox_override("panel", sb)
		_combat_highlight.visible = false
		add_child(_combat_highlight)
	if _combat_roller == null:
		_combat_roller = RollingNumbers.new()
		_combat_roller.set_anchors_preset(Control.PRESET_FULL_RECT)
		_combat_roller.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_combat_roller.font = load("res://Fonts/VeniceClassic.ttf")
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
#endregion

func _class_text(character: Character) -> String:
	var primary: String = character.primary_class
	var secondary: String = character.secondary_class
	if primary != "" and secondary != "":
		return "%s / %s" % [primary, secondary]
	if primary != "":
		return primary
	if secondary != "":
		return secondary
	return "No class"
