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
@onready var _primary_slot: InventoryContainer = %PrimarySlot
@onready var _secondary_slot: InventoryContainer = %SecondarySlot

const STAT_ABBREV := {
	"Might": "MIG", "Awareness": "AWR", "Finesse": "FIN",
	"Intellect": "INT", "Charm": "CHM", "Fate": "FAT",
}

var _character: Character = null
var _stat_value_labels: Dictionary = {}   # stat name -> Label
var _inventory_events: Node = null
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
	if _primary_slot:
		_primary_slot.slot_changed.connect(_on_slot_changed.bind("primary", _primary_slot))
	if _secondary_slot:
		_secondary_slot.slot_changed.connect(_on_slot_changed.bind("secondary", _secondary_slot))

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

# Push the character's saved equipment into the two hand slots.
func _restore_equipment() -> void:
	if not _character:
		return

	_restoring = true
	_apply_slot(_primary_slot, _character.get_equipment_slot("primary"))
	_apply_slot(_secondary_slot, _character.get_equipment_slot("secondary"))
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
