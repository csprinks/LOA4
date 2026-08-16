extends Node

## Autoload that runs a fight IN the game world (no scene swap). On start_encounter
## it builds the Encounter from the live party + the given enemies, locks the
## player, and spawns the CombatOverlay on top of the running level. The persistent
## hero HUD (UI_Main) stays on screen and doubles as the party display. On the
## overlay's battle_finished it unlocks the player and frees the overlay.
##
## A debug hotkey (K) starts a sample fight from anywhere, so combat is testable
## before real EncounterTriggers are placed in levels.

signal combat_started
signal combat_ended(status: int)

const OVERLAY_SCENE := preload("res://Combat/UI/combat_overlay.tscn")
const DEBUG_HOTKEY := KEY_K

var _active := false
var _overlay: CanvasLayer = null


func is_active() -> bool:
	return _active


func _unhandled_input(event: InputEvent) -> void:
	if _active:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == DEBUG_HOTKEY:
		start_encounter(sample_enemies())
		get_viewport().set_input_as_handled()


# enemy_combatants: Array[Combatant] built by the caller (a trigger or the debug
# key), each carrying its .row. Returns quietly if a fight is already running or
# there's no party to field.
func start_encounter(enemy_combatants: Array) -> void:
	if _active or enemy_combatants.is_empty():
		return

	_ensure_party()
	var party_manager := get_node_or_null("/root/PartyManager")
	if party_manager == null or party_manager.party.is_empty():
		return

	_active = true
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_combat_locked"):
		player.set_combat_locked(true)

	# Persona-style intro wipe. It covers the screen, we build the battle behind it
	# while hidden, then it sweeps off to reveal the ready board.
	var transition := CombatTransition.new()
	get_tree().root.add_child(transition)
	transition.play()
	await transition.covered

	var allies: Array = []
	for c in party_manager.party:
		allies.append(Combatant.for_ally(c))

	var enc := Encounter.new(allies, enemy_combatants)
	var controller := CombatController.new(enc, CombatRNG.new(), BasicAIStrategy.new())

	_overlay = OVERLAY_SCENE.instantiate()
	get_tree().root.add_child(_overlay)
	_overlay.battle_finished.connect(_on_battle_finished)
	_overlay.begin(enc, controller, player)
	combat_started.emit()


func _on_battle_finished(status: int) -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_combat_locked"):
		player.set_combat_locked(false)
	_active = false
	combat_ended.emit(status)


# Make sure there's a party to fight with. In normal play one always exists; this
# only fires when a fight is triggered in a freshly-booted level (dev testing),
# building the same 4 heroes the HUD then binds its cards to.
func _ensure_party() -> void:
	var party_manager := get_node_or_null("/root/PartyManager")
	if party_manager and party_manager.party.is_empty():
		party_manager.create_new_party(false)


# A sample two-row group for the debug key and placeholder triggers. Built from the
# AUTHORED monster resources in Combat/Monsters/ (stats, rewards, loot, and sprite
# all set in the .tres) so the debug fight showcases the real battlers. Each load is
# guarded; if none resolve (e.g. before the first editor import) we fall back to the
# code-built MonsterLibrary samples so the fight still works.
func sample_enemies() -> Array:
	var enemies: Array = []
	_add_monster(enemies, "res://Combat/Monsters/orc.tres", 0)
	_add_monster(enemies, "res://Combat/Monsters/goblin_bandit.tres", 0)
	_add_monster(enemies, "res://Combat/Monsters/piranha_tree.tres", 0)
	_add_monster(enemies, "res://Combat/Monsters/kobold.tres", 1)
	_add_monster(enemies, "res://Combat/Monsters/goblin_thief.tres", 1)

	if enemies.is_empty():
		enemies.append(Combatant.for_enemy(MonsterLibrary.orc(), 0))
		enemies.append(Combatant.for_enemy(MonsterLibrary.kobold(), 0))
		enemies.append(Combatant.for_enemy(MonsterLibrary.kobold_archer(), 1))
	return enemies


# Load an authored MonsterDefinition and append it as an enemy Combatant on the
# given row. Silently skips a path that fails to load or isn't a MonsterDefinition.
func _add_monster(into: Array, path: String, row: int) -> void:
	var def := load(path) as MonsterDefinition
	if def:
		into.append(Combatant.for_enemy(def, row))
