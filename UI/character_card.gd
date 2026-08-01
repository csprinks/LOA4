class_name CharacterCard
extends Control

## A single hero's HUD card: portrait, name, classes, level, HP/AP bars, and the
## six stats. Bound to a Character by set_character(); hides itself when passed
## null. Rebuilt clean for LOA4 — the LOA2 card's weapon-equip slots return in
## the inventory phase, and its stale Might/Magic/Intellect icons are dropped in
## favour of the current six-stat model.

@onready var _portrait: TextureRect = %Portrait
@onready var _name_label: Label = %NameLabel
@onready var _class_label: Label = %ClassLabel
@onready var _level_label: Label = %LevelLabel
@onready var _hp_bar: ProgressBar = %HPBar
@onready var _hp_label: Label = %HPLabel
@onready var _ap_bar: ProgressBar = %APBar
@onready var _ap_label: Label = %APLabel
@onready var _stats_grid: GridContainer = %StatsGrid

const STAT_ABBREV := {
	"Might": "MIG", "Awareness": "AWR", "Finesse": "FIN",
	"Intellect": "INT", "Charm": "CHM", "Fate": "FAT",
}

var _character: Character = null
var _stat_value_labels: Dictionary = {}   # stat name -> Label

func _ready() -> void:
	_build_stat_labels()
	# Reflect whatever was assigned before _ready (or hide if none).
	set_character(_character)

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

	if character.portrait != "" and ResourceLoader.exists(character.portrait):
		_portrait.texture = load(character.portrait)

	var hp = character.hit_points
	_hp_bar.max_value = hp.max_value
	_hp_bar.value = hp.current
	_hp_label.text = "%d/%d" % [hp.current, hp.max_value]

	var ap = character.action_points
	_ap_bar.max_value = ap.max_value
	_ap_bar.value = ap.current
	_ap_label.text = "%d/%d" % [ap.current, ap.max_value]

	for stat_name in Character.STAT_NAMES:
		var stat = character.get_stat(stat_name)
		if _stat_value_labels.has(stat_name) and stat:
			_stat_value_labels[stat_name].text = "%s %d" % [STAT_ABBREV.get(stat_name, stat_name), stat.total]

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
