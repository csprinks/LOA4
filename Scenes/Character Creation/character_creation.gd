extends PanelContainer

## One hero's creation panel: portrait, name, two class dropdowns, and Deed Point
## allocation across the six stats. Built programmatically so all four panels are
## identical and easy to restyle, and themed to match the hero cards. Exposes the
## accessors the creation coordinator (character_creation_flow.gd) reads on
## "Start Game".
##
## Deed Point rules (see "Class Jobs List"): every stat starts at 10; the hero has
## 10 Deed Points; each Deed raises a stat by its Points-Per-Deed, which depends on
## the chosen classes: in both -> 6, primary only -> 4, secondary only -> 2, else 1.

const STAT_ORDER := ["Might", "Awareness", "Finesse", "Intellect", "Charm", "Fate"]
const CLASS_LIST := ["Paladin", "Knight", "Barbarian", "Duelist", "Scoundrel", "Ranger", "Bard", "Sage", "Cleric", "Witch"]

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

const BASE_STAT := 10
const TOTAL_DEED_POINTS := 10
const PPD_OVERLAP := 6
const PPD_PRIMARY := 4
const PPD_SECONDARY := 2
const PPD_OFF_CLASS := 1

const FONT := 16
const PORTRAIT_DIR := "res://Portraits/"
const PORTRAIT_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "bmp", "svg"]

var deeds_spent: Dictionary = {}
var primary_class := ""
var secondary_class := ""

var _name_edit: LineEdit
var _primary_option: OptionButton
var _secondary_option: OptionButton
var _dp_label: Label
var _portrait_rect: TextureRect
var _portrait_paths: Array[String] = []
var _portrait_index := 0
var _total_labels: Dictionary = {}
var _spent_labels: Dictionary = {}
var _ppd_labels: Dictionary = {}


func _ready() -> void:
	for stat in STAT_ORDER:
		deeds_spent[stat] = 0
	custom_minimum_size = Vector2(300, 0)
	_build()
	_setup_portrait()
	_refresh()


func _label(text: String, size: int = FONT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _build() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)

	# Portrait (click to cycle)
	_portrait_rect = TextureRect.new()
	_portrait_rect.custom_minimum_size = Vector2(120, 120)
	_portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_portrait_rect)

	var hint := _label("(click portrait to change)", 11)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)

	# Name
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Enter Hero Name"
	_name_edit.add_theme_font_size_override("font_size", FONT)
	col.add_child(_name_edit)

	# Class dropdowns
	col.add_child(_label("Primary Class"))
	_primary_option = _make_class_option()
	_primary_option.item_selected.connect(_on_primary_selected)
	col.add_child(_primary_option)

	col.add_child(_label("Secondary Class"))
	_secondary_option = _make_class_option()
	_secondary_option.item_selected.connect(_on_secondary_selected)
	col.add_child(_secondary_option)

	# Deed Points remaining
	_dp_label = _label("Deed Points (DP): %d" % TOTAL_DEED_POINTS, 18)
	col.add_child(_dp_label)

	# Stat allocation grid: Stat | Total | - | spent | + | PPD
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	col.add_child(grid)

	for header in ["Stat", "Total", "", "DP", "", "PPD"]:
		grid.add_child(_label(header, 13))

	for stat in STAT_ORDER:
		grid.add_child(_label(stat))

		var total := _label(str(BASE_STAT))
		_total_labels[stat] = total
		grid.add_child(total)

		var minus := Button.new()
		minus.text = "-"
		minus.add_theme_font_size_override("font_size", FONT)
		minus.pressed.connect(_refund.bind(stat))
		grid.add_child(minus)

		var spent := _label("0")
		spent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		spent.custom_minimum_size = Vector2(18, 0)
		_spent_labels[stat] = spent
		grid.add_child(spent)

		var plus := Button.new()
		plus.text = "+"
		plus.add_theme_font_size_override("font_size", FONT)
		plus.pressed.connect(_spend.bind(stat))
		grid.add_child(plus)

		var ppd := _label(str(PPD_OFF_CLASS))
		_ppd_labels[stat] = ppd
		grid.add_child(ppd)


func _make_class_option() -> OptionButton:
	var ob := OptionButton.new()
	ob.add_theme_font_size_override("font_size", FONT)
	ob.get_popup().add_theme_font_size_override("font_size", FONT)
	ob.add_item("(none)")
	for class_name_ in CLASS_LIST:
		ob.add_item(class_name_)
	return ob


func _on_primary_selected(index: int) -> void:
	primary_class = "" if index == 0 else _primary_option.get_item_text(index)
	_refresh()


func _on_secondary_selected(index: int) -> void:
	secondary_class = "" if index == 0 else _secondary_option.get_item_text(index)
	_refresh()


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


func _spend(stat: String) -> void:
	if deeds_remaining() > 0:
		deeds_spent[stat] += 1
		_refresh()


func _refund(stat: String) -> void:
	if deeds_spent[stat] > 0:
		deeds_spent[stat] -= 1
		_refresh()


func _refresh() -> void:
	for stat in STAT_ORDER:
		var ppd := points_per_deed(stat)
		_total_labels[stat].text = str(BASE_STAT + int(deeds_spent[stat]) * ppd)
		_spent_labels[stat].text = str(deeds_spent[stat])
		_ppd_labels[stat].text = str(ppd)
	_dp_label.text = "Deed Points (DP): %d" % deeds_remaining()


# --- Portrait selection -----------------------------------------------------
func _setup_portrait() -> void:
	_portrait_paths = _list_portraits()
	if not _portrait_paths.is_empty():
		_show_portrait(0)
	_portrait_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_portrait_rect.gui_input.connect(_on_portrait_input)


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
			var base := file
			if base.ends_with(".import") or base.ends_with(".remap"):
				base = base.get_basename()
			if base.get_extension().to_lower() in PORTRAIT_EXTENSIONS:
				var path := PORTRAIT_DIR.path_join(base)
				if not paths.has(path):
					paths.append(path)
		file = dir.get_next()
	dir.list_dir_end()
	paths.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return paths


func _on_portrait_input(event: InputEvent) -> void:
	if _portrait_paths.is_empty():
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_show_portrait(_portrait_index + 1)
			MOUSE_BUTTON_RIGHT:
				_show_portrait(_portrait_index - 1)


func _show_portrait(index: int) -> void:
	var count := _portrait_paths.size()
	_portrait_index = ((index % count) + count) % count
	_portrait_rect.texture = load(_portrait_paths[_portrait_index])


# --- Accessors read by the creation coordinator -----------------------------
func get_hero_name() -> String:
	return _name_edit.text.strip_edges() if _name_edit else ""

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

func get_portrait_path() -> String:
	if _portrait_rect != null and _portrait_rect.texture != null:
		return _portrait_rect.texture.resource_path
	return ""
