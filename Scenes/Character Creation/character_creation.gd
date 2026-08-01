extends CanvasLayer

# Deed Point allocation for the six character stats.
# Rules (see "Class Jobs List"):
#   - Every stat starts at a base of 10.
#   - The character has 10 Deed Points to spend at creation.
#   - Spending a Deed on a stat raises it by that stat's "Points Per Deed",
#     which depends on how the stat relates to the chosen Primary/Secondary class:
#         overlap (both classes) = 6, primary = 4, secondary = 2, off-class = 1.
#   - Left-click a stat's DP-Spent cell to spend a Deed; right-click to refund.

const STAT_ORDER := ["Might", "Awareness", "Finesse", "Intellect", "Charm", "Fate"]
const BASE_STAT := 10
const TOTAL_DEED_POINTS := 10

# Each class is associated with two stats (Class Jobs table).
const CLASS_STATS := {
	"Knight": ["Might", "Awareness"],
	"Ranger": ["Finesse", "Awareness"],
	"Scoundrel": ["Finesse", "Fate"],
	"Sage": ["Intellect", "Fate"],
	"Cleric": ["Charm", "Fate"],
	"Bard": ["Charm", "Intellect"],
	"Barbarian": ["Might", "Fate"],
	"Paladin": ["Might", "Charm"],
	"Witch": ["Fate", "Intellect"],
	"Duelist": ["Finesse", "Charm"],
}

const PPD_OVERLAP := 6
const PPD_PRIMARY := 4
const PPD_SECONDARY := 2
const PPD_OFF_CLASS := 1

const HIGHLIGHT_COLOR := Color(1.0, 0.85, 0.2)  # yellow "active" cell

const PORTRAIT_DIR := "res://Portraits/"
const PORTRAIT_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "bmp", "svg"]

var deeds_spent: Dictionary = {}   # stat name -> Deeds spent on it
var primary_class := ""
var secondary_class := ""
var active_stat := ""              # the currently highlighted DP-Spent cell

var portrait_rect: TextureRect
var portrait_paths: Array[String] = []
var portrait_index := 0

@onready var primary_list: ItemList = $Class_H_Box/Primary_Class/Primary_Class_List
@onready var secondary_list: ItemList = $Class_H_Box/Secondary_Class/Secondary_Class_List
@onready var deed_points_label: Label = $Class_H_Box/Secondary_Class/Deed_Points


func _ready() -> void:
	for stat in STAT_ORDER:
		deeds_spent[stat] = 0

	primary_list.item_selected.connect(_on_primary_class_selected)
	secondary_list.item_selected.connect(_on_secondary_class_selected)

	# Make each DP-Spent cell clickable and route its input to us.
	for stat in STAT_ORDER:
		var cell := _dp_cell(stat)
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		cell.gui_input.connect(_on_dp_cell_input.bind(stat))

	_setup_portrait()
	_refresh()


# --- Node lookups -----------------------------------------------------------
func _dp_cell(stat: String) -> Label:
	return get_node("Stats_HBox/DP_Spent_Vbox/%s_Current" % stat)

func _total_cell(stat: String) -> Label:
	return get_node("Stats_HBox/Current_VBox/%s_Current" % stat)

func _ppd_cell(stat: String) -> Label:
	return get_node("Stats_HBox/Points Per Deed_Vbox/%s_Current" % stat)


# --- Rules ------------------------------------------------------------------
func points_per_deed(stat: String) -> int:
	var in_primary: bool = primary_class != "" and stat in CLASS_STATS.get(primary_class, [])
	var in_secondary: bool = secondary_class != "" and stat in CLASS_STATS.get(secondary_class, [])
	if in_primary and in_secondary:
		return PPD_OVERLAP
	if in_primary:
		return PPD_PRIMARY
	if in_secondary:
		return PPD_SECONDARY
	return PPD_OFF_CLASS

func deeds_remaining() -> int:
	var spent := 0
	for stat in STAT_ORDER:
		spent += deeds_spent[stat]
	return TOTAL_DEED_POINTS - spent


# --- Class selection --------------------------------------------------------
func _on_primary_class_selected(index: int) -> void:
	primary_class = primary_list.get_item_text(index)
	_refresh()

func _on_secondary_class_selected(index: int) -> void:
	secondary_class = secondary_list.get_item_text(index)
	_refresh()


# --- Deed spending ----------------------------------------------------------
func _on_dp_cell_input(event: InputEvent, stat: String) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				active_stat = stat
				_spend_deed(stat)
			MOUSE_BUTTON_RIGHT:
				active_stat = stat
				_refund_deed(stat)

func _spend_deed(stat: String) -> void:
	if deeds_remaining() > 0:
		deeds_spent[stat] += 1
	_refresh()

func _refund_deed(stat: String) -> void:
	if deeds_spent[stat] > 0:
		deeds_spent[stat] -= 1
	_refresh()


# --- Rendering --------------------------------------------------------------
func _refresh() -> void:
	for stat in STAT_ORDER:
		var ppd := points_per_deed(stat)
		var total: int = BASE_STAT + int(deeds_spent[stat]) * ppd
		_dp_cell(stat).text = str(deeds_spent[stat])
		_total_cell(stat).text = str(total)
		_ppd_cell(stat).text = str(ppd)

		if stat == active_stat:
			_dp_cell(stat).add_theme_color_override("font_color", HIGHLIGHT_COLOR)
		else:
			_dp_cell(stat).remove_theme_color_override("font_color")

	deed_points_label.text = "Deed Points(DP): %d" % deeds_remaining()


# --- Portrait selection -----------------------------------------------------
# Left-click the portrait to advance through the images in the Portraits folder;
# right-click to step back. Works per-character (each shares this script).
func _setup_portrait() -> void:
	portrait_rect = _find_portrait_rect()
	if portrait_rect == null:
		return

	portrait_paths = _list_portraits()
	# Start on whatever portrait the scene already assigned, if it's in the list.
	if portrait_rect.texture != null:
		var current := portrait_rect.texture.resource_path
		var found := portrait_paths.find(current)
		if found != -1:
			portrait_index = found

	portrait_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	portrait_rect.gui_input.connect(_on_portrait_input)

func _find_portrait_rect() -> TextureRect:
	# Convention: the portrait node is named "<CanvasLayer name>_Portrait".
	var by_name := get_node_or_null("%s_Portrait" % name)
	if by_name is TextureRect:
		return by_name
	# Fallback: first TextureRect child.
	for child in get_children():
		if child is TextureRect:
			return child
	return null

func _list_portraits() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(PORTRAIT_DIR)
	if dir == null:
		push_warning("Portrait folder not found: %s" % PORTRAIT_DIR)
		return paths
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if not dir.current_is_dir():
			# In exported builds imported textures may appear as ".import"/".remap".
			var base := file
			if base.ends_with(".import") or base.ends_with(".remap"):
				base = base.get_basename()
			if base.get_extension().to_lower() in PORTRAIT_EXTENSIONS:
				var path := PORTRAIT_DIR.path_join(base)
				if not paths.has(path):
					paths.append(path)
		file = dir.get_next()
	dir.list_dir_end()
	# Natural order so Portrait_2 comes before Portrait_10.
	paths.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return paths

func _on_portrait_input(event: InputEvent) -> void:
	if portrait_paths.is_empty():
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_show_portrait(portrait_index + 1)
			MOUSE_BUTTON_RIGHT:
				_show_portrait(portrait_index - 1)

func _show_portrait(index: int) -> void:
	var count := portrait_paths.size()
	portrait_index = ((index % count) + count) % count  # wrap both directions
	portrait_rect.texture = load(portrait_paths[portrait_index])


# --- Accessors for the character-creation coordinator -----------------------
# The typed hero name, or "" if the player left it blank.
func get_hero_name() -> String:
	var line_edit := get_node_or_null("Character_Name") as LineEdit
	if line_edit == null:
		return ""
	return line_edit.text.strip_edges()

# Per-stat allocation for building the Character:
# {name: {base, deeds_spent, points_per_deed}}. Total = base + deeds * ppd.
func get_stat_data() -> Dictionary:
	var out := {}
	for stat in STAT_ORDER:
		out[stat] = {
			"base": BASE_STAT,
			"deeds_spent": int(deeds_spent[stat]),
			"points_per_deed": points_per_deed(stat),
		}
	return out

func get_primary_class() -> String:
	return primary_class

func get_secondary_class() -> String:
	return secondary_class

# res:// path of the currently shown portrait ("" if none).
func get_portrait_path() -> String:
	if portrait_rect != null and portrait_rect.texture != null:
		return portrait_rect.texture.resource_path
	return ""
