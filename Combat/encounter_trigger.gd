extends Area3D
class_name EncounterTrigger

## A walk-in fight: when the party steps into this cell, CombatManager starts an
## encounter against the monsters listed here.
##
##   - front_row / back_row: MonsterDefinition resources (e.g. Combat/Monsters/*.tres).
##     Front-row monsters are the ones melee can reach first.
##   - one_shot: once the party WINS, the trigger is spent for good (and WorldState
##     remembers that across level changes and saves). Fleeing or losing leaves it
##     live; it re-arms when the party steps out of the cell.

@export var front_row: Array[MonsterDefinition] = []
@export var back_row: Array[MonsterDefinition] = []
@export var one_shot: bool = true

var _spent: bool = false    # won and one_shot: never fires again
var _armed: bool = true     # false from the moment it fires until the party leaves

func _ready() -> void:
	monitoring = true
	add_to_group("persistent")  # WorldState saves/restores _spent
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if _spent or not _armed or not body.is_in_group("player"):
		return
	if CombatManager.is_active() or LevelManager.is_loading_level:
		return
	var enemies := _build_enemies()
	if enemies.is_empty():
		return

	_armed = false
	CombatManager.combat_ended.connect(_on_combat_ended, CONNECT_ONE_SHOT)
	CombatManager.start_encounter(enemies)
	# start_encounter bails quietly when there is no party to field; don't leave a
	# listener behind that some later, unrelated fight would trip.
	if not CombatManager.is_active():
		CombatManager.combat_ended.disconnect(_on_combat_ended)
		_armed = true

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player") and not CombatManager.is_active():
		_armed = true

func _on_combat_ended(status: int) -> void:
	if one_shot and status == Encounter.Status.WIN:
		_spent = true

func _build_enemies() -> Array:
	var enemies: Array = []
	for def in front_row:
		if def:
			enemies.append(Combatant.for_enemy(def, 0))
	for def in back_row:
		if def:
			enemies.append(Combatant.for_enemy(def, 1))
	return enemies

#region Persistence (WorldState contract)
func get_persistent_state() -> Dictionary:
	return {"spent": _spent}

func apply_persistent_state(state: Dictionary) -> void:
	_spent = bool(state.get("spent", false))
#endregion
