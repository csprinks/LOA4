extends Node2D

## The Character Creation screen: builds the party one hero at a time on a single
## CharacterSheet (in creation mode). A roster strip along the top shows all four
## heroes and jumps between them; "Start Game" unlocks once every hero has chosen
## their free starting skills.
##
## "Start Game" drops into the Showcase level when no campaign is set (no Library scene
## yet); "Return to Main Menu" goes back to the Main Menu scene.

const NEXT_SCENE := "res://Modules/Showcase/floors/floor_upper.tscn"
const MENU_SCENE := "res://Scenes/Main_Menu/main_menu.tscn"
const PARTY_SIZE := 4

# Starter hand gear so new heroes have something in their equip slots. Temporary
# until the backpack UI lets players pick their own gear.
const STARTING_PRIMARY := "res://Inventory/Resources/Weapons/sword_1h.tres"
const STARTING_SECONDARY := "res://Inventory/Resources/Weapons/shield.tres"

var _heroes: Array = []            # the party being built (Character)
var _current := 0
var _sheet: CharacterSheet
var _roster_buttons: Array = []    # one Button per hero, same order as _heroes

@onready var _start_button: Button = %StartButton


func _ready() -> void:
	_start_button.pressed.connect(_on_start_game_pressed)
	(%MainMenuButton as Button).pressed.connect(_on_main_menu_pressed)

	var group := ButtonGroup.new()
	for i in PARTY_SIZE:
		_heroes.append(_new_hero(i))

		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(330, 0)
		button.expand_icon = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_constant_override("icon_max_width", 64)
		button.add_theme_font_size_override("font_size", 18)
		button.pressed.connect(_select_hero.bind(i))
		_roster_buttons.append(button)
		%Roster.add_child(button)

	_sheet = CharacterSheet.new()
	_sheet.creation_mode = true
	_sheet.changed.connect(_refresh_roster)
	%SheetHolder.add_child(_sheet)

	_select_hero(0)


func _new_hero(index: int) -> Character:
	var character := Character.new()
	character.character_name = ""
	character.portrait = "res://Portraits/Portrait_%d.png" % (index + 1)
	_equip_starting_gear(character)
	return character


func _select_hero(index: int) -> void:
	_current = index
	_sheet.bind(_heroes[index])
	_refresh_roster()


func _display_name(index: int) -> String:
	var hero_name: String = _heroes[index].character_name
	return hero_name if hero_name != "" else "Hero %d" % (index + 1)


func _refresh_roster() -> void:
	var all_ready := true
	for i in PARTY_SIZE:
		var hero: Character = _heroes[i]
		var button: Button = _roster_buttons[i]
		var owed: int = hero.skills.free_picks_left
		var status := "Choose %d free skill%s" % [owed, "" if owed == 1 else "s"]
		if owed == 0:
			status = "Ready  (%d SP, %d ATR unspent)" % [hero.available_skill_points, hero.available_attribute_points]
		else:
			all_ready = false
		button.text = "%s\n%s" % [_display_name(i), status]
		button.set_pressed_no_signal(i == _current)
		if hero.portrait != "" and ResourceLoader.exists(hero.portrait):
			button.icon = load(hero.portrait)

	_start_button.disabled = not all_ready
	_start_button.tooltip_text = "" if all_ready else "Every hero must choose their free starting skills."


func _on_start_game_pressed() -> void:
	_build_party()
	# Hand off to LevelManager, which spawns the persistent player (HUD embedded)
	# into the first level. Then drop this creation screen; LevelManager runs its
	# fade + load as an autoload coroutine independent of this node.
	# A new game starts on the first floor of the campaign module (chosen in the
	# Level Editor); until one is set and built, it falls back to the Showcase level.
	var start := ModuleLibrary.campaign_start_scene()
	GameState.editor_test_module = ""
	LevelManager.load_level(start if start != "" else NEXT_SCENE)
	queue_free()


func _on_main_menu_pressed() -> void:
	_go_to_scene(MENU_SCENE)


func _build_party() -> void:
	var party_manager := get_node_or_null("/root/PartyManager")
	if party_manager == null:
		push_error("PartyManager autoload not found; cannot start game.")
		return

	party_manager.reset()

	# Fresh world for a brand-new game, so a new party never inherits a prior
	# session's open doors / looted chests.
	var world_state := get_node_or_null("/root/WorldState")
	if world_state:
		world_state.reset()

	# New games start with an empty shared backpack (loot comes from chests). This
	# also clears any backpack left over from a game loaded earlier this session.
	var inventory_manager := get_node_or_null("/root/InventoryManager")
	if inventory_manager and inventory_manager.has_method("reset_inventory"):
		inventory_manager.reset_inventory()

	# The sheet already wrote every choice onto the heroes; only unnamed ones
	# still need a name.
	for i in PARTY_SIZE:
		_heroes[i].character_name = _display_name(i)

	party_manager.party = _heroes
	party_manager.current_character_index = 0
	# Mark initialized so downstream systems keep this party instead of replacing
	# it with a default one. Clear the new-game flag so initialize_party() (if it
	# runs) won't rebuild a fresh party either.
	party_manager.is_initialized = true
	GameState.new_game_requested = false
	party_manager.emit_signal("party_updated")


# Give a new hero starter hand gear (serialized into its equipment dict) so the
# card's equip slots show something. Temporary demo gear until the backpack UI.
func _equip_starting_gear(character) -> void:
	var events := get_node_or_null("/root/InventoryEvents")
	character.set_equipment_slot("primary", _weapon_dict(STARTING_PRIMARY, events))
	character.set_equipment_slot("secondary", _weapon_dict(STARTING_SECONDARY, events))

func _weapon_dict(path: String, events: Node) -> Dictionary:
	if not ResourceLoader.exists(path):
		return {}
	var weapon := InventoryWeapon.new()
	weapon._resourceData = load(path)
	weapon.itemName = weapon._resourceData.itemName
	if events:
		weapon.SetInventoryEvents(events)
	return EquipmentSerializer.item_to_dict(weapon)


func _go_to_scene(path: String) -> void:
	var fade_manager := get_node_or_null("/root/FadeManager")
	if fade_manager:
		fade_manager.transition_to_scene(path)
	else:
		get_tree().change_scene_to_file(path)
