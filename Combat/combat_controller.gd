class_name CombatController
extends RefCounted

## Drives a fight to its conclusion. Each round it builds a FRESH initiative order
## (Finesse + Awareness + a roll), gives every living combatant one turn, resolves
## the chosen action, and ends on WIN / LOSE / FLED. Allies pick actions through an
## injected seam (a battle UI in-game, a scripted policy in tests); enemies pick
## through their AIStrategy. On WIN it awards XP, crowns, and loot.
##
## The synchronous run_to_completion() is the reference driver and what tests use.
## A turn-by-turn UI can instead reuse the public primitives -- build_initiative(),
## begin_turn(), apply_action() -- and supply the player's chosen action itself.

signal round_started(round_number: int)
signal turn_started(combatant: Combatant)
signal action_resolved(result: Dictionary)
signal combatant_downed(combatant: Combatant)
signal encounter_ended(status: int, rewards: Dictionary)

var encounter: Encounter
var resolver: CombatResolver
var rng: CombatRNG
var ai_strategy: AIStrategy

# --- Injected seams ---------------------------------------------------------
# ally_action_provider: Callable(actor, encounter, controller) -> {action, target}
var ally_action_provider: Callable = Callable()
# reroll_decider: Callable(actor, target, result) -> bool  (Fortune reroll)
var reroll_decider: Callable = Callable()
# Optional game integrations (left null in headless tests). If null, the reward
# step falls back to looking these up on the SceneTree root by autoload name.
var inventory_manager = null
var crowns = null
var party_manager = null

var round_number: int = 0

func _init(enc: Encounter, combat_rng: CombatRNG = null, strategy: AIStrategy = null) -> void:
	encounter = enc
	rng = combat_rng if combat_rng else CombatRNG.new()
	resolver = CombatResolver.new(rng)
	ai_strategy = strategy if strategy else BasicAIStrategy.new()

#region Driver
# Run the whole fight and return the final Encounter.Status.
func run_to_completion(max_rounds: int = 100) -> int:
	encounter.refresh_status()
	while encounter.status == Encounter.Status.ONGOING and round_number < max_rounds:
		_run_round()
	_finish()
	return encounter.status

func _run_round() -> void:
	round_number += 1
	round_started.emit(round_number)
	for actor in build_initiative():
		if actor.is_downed:
			continue   # died earlier this round
		if encounter.status != Encounter.Status.ONGOING:
			return
		begin_turn(actor)
		var decision := _decide(actor)
		if decision.is_empty() or decision.get("action") == null:
			continue   # passed
		apply_action(actor, decision["action"], decision.get("target", null))
#endregion

#region Public primitives (reusable by a turn-by-turn UI)
# Fresh initiative order for this round: living combatants sorted by
# Finesse + Awareness + roll, descending.
func build_initiative() -> Array:
	var scored: Array = []
	for c in encounter.all_combatants():
		if c.is_downed:
			continue
		var init_value: int = c.initiative_base + rng.randi_range(0, CombatConstants.INITIATIVE_ROLL_MAX)
		scored.append({"combatant": c, "init": init_value})
	scored.sort_custom(func(a, b): return a["init"] > b["init"])
	return scored.map(func(entry): return entry["combatant"])

# Start-of-turn bookkeeping (AP bank/refresh + status ticks) and signal.
func begin_turn(actor: Combatant) -> void:
	actor.begin_turn()
	turn_started.emit(actor)

# Validate and execute an action, emit signals, and refresh the board status.
# Returns the action's result Dictionary ({} if it was not legal).
func apply_action(actor: Combatant, action: CombatAction, target: Combatant) -> Dictionary:
	if not action.can_perform(actor, target, encounter):
		return {}
	var result := action.execute(actor, target, encounter, self)
	action_resolved.emit(result)
	if result.get("defender_downed", false):
		combatant_downed.emit(result["defender"])
	encounter.refresh_status()
	return result
#endregion

#region Decision seams
func _decide(actor: Combatant) -> Dictionary:
	if actor.is_ally:
		if ally_action_provider.is_valid():
			return ally_action_provider.call(actor, encounter, self)
		return {}   # no provider -> ally passes
	return ai_strategy.choose_action(actor, encounter, self)

func should_reroll(actor: Combatant, target: Combatant, result: Dictionary) -> bool:
	if reroll_decider.is_valid():
		return bool(reroll_decider.call(actor, target, result))
	return false

# Remove a used consumable from the shared backpack, if wired to the game.
func consume_item(item) -> void:
	var inv = _inventory()
	if inv != null and inv.has_method("remove_item"):
		inv.remove_item(item)
	# TODO: InventoryManager currently has no remove_item(); add one when the
	# battle scene lands so used potions actually leave the backpack.
#endregion

#region Rewards
func _finish() -> void:
	var rewards := {"xp": 0, "crowns": 0, "loot": []}
	if encounter.status == Encounter.Status.WIN:
		rewards = _award_rewards()
	encounter_ended.emit(encounter.status, rewards)

func _award_rewards() -> Dictionary:
	var total_xp := 0
	var total_crowns := 0
	var loot: Array = []
	for e in encounter.enemies:
		if e.monster == null:
			continue
		total_xp += e.monster.xp_reward
		total_crowns += e.monster.crowns_reward
		for drop in e.monster.loot:
			loot.append(drop)

	# XP to every surviving hero (full XP each; tune the split later if desired).
	for ally in encounter.allies:
		if not ally.is_downed and ally.character != null:
			ally.character.reward_xp(total_xp)

	# Crowns are shared party currency.
	if total_crowns > 0:
		var c = _crowns()
		if c != null and c.has_method("add_crowns"):
			c.add_crowns(total_crowns)

	# Loot to the shared backpack.
	if not loot.is_empty():
		var inv = _inventory()
		if inv != null and inv.has_method("AddItem"):
			for drop in loot:
				inv.AddItem(drop)

	return {"xp": total_xp, "crowns": total_crowns, "loot": loot}
#endregion

#region Autoload fallbacks
func _inventory():
	return inventory_manager if inventory_manager != null else _autoload("InventoryManager")

func _crowns():
	return crowns if crowns != null else _autoload("Crowns")

func _autoload(node_name: String):
	var loop := Engine.get_main_loop()
	if loop is SceneTree and loop.root != null:
		return loop.root.get_node_or_null(node_name)
	return null
#endregion
